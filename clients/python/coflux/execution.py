import typing as t
import multiprocessing
import multiprocessing.connection
import threading
import time
import enum
import asyncio
import datetime as dt
import traceback
import sys
import tempfile
import os
import contextlib
import mimetypes
import zipfile
import itertools
import signal
from pathlib import Path
from contextvars import ContextVar
from contextlib import contextmanager

from . import server, blobs, models, serialisation, decorators, loader


_EXECUTION_THRESHOLD_S = 1.0
_AGENT_THRESHOLD_S = 5.0


T = t.TypeVar("T")

_channel_context: t.Optional["Channel"] = None
_timeout: ContextVar[float | None] = ContextVar("timeout", default=None)


class Timeout(Exception):
    pass


class Future(t.Generic[T]):
    def __init__(self):
        self._event = threading.Event()
        self._result: T | None = None
        self._error: t.Any | None = None

    def result(self, timeout: float | None = None):
        if not self._event.wait(timeout):
            raise Timeout()
        if self._error:
            raise Exception(self._error)
        else:
            return t.cast(T, self._result)

    def set_success(self, result):
        assert not self._result and not self._error
        self._result = result
        self._event.set()

    def set_error(self, error):
        assert not self._result and not self._error
        self._error = error
        self._event.set()


class ExecutionStatus(enum.Enum):
    STARTING = 0
    # TODO: preparing?
    EXECUTING = 1
    ABORTING = 2
    STOPPING = 3


class Error(t.NamedTuple):
    type: str
    message: str
    frames: list[tuple[str, int, str, str | None]]


class ExecutingNotification(t.NamedTuple):
    pass


class RecordResultRequest(t.NamedTuple):
    value: models.Value


class RecordErrorRequest(t.NamedTuple):
    error: Error


class SubmitExecutionRequest(t.NamedTuple):
    type: t.Literal["workflow", "task"]
    repository: str
    target: str
    arguments: list[models.Value]
    wait_for: set[int]
    cache: models.Cache | None
    defer: models.Defer | None
    memo: list[int] | bool
    execute_after: dt.datetime | None
    retries: models.Retries | None
    requires: models.Requires | None


class ResolveReferenceRequest(t.NamedTuple):
    execution_id: int


class PersistAssetRequest(t.NamedTuple):
    type: int
    path: str
    blob_key: str
    metadata: dict[str, t.Any]


class ResolveAssetRequest(t.NamedTuple):
    asset_id: int


class SuspendRequest(t.NamedTuple):
    execute_after: dt.datetime | None
    execution_ids: list[int]


class RecordCheckpointRequest(t.NamedTuple):
    arguments: list[models.Value]


class LogMessageRequest(t.NamedTuple):
    level: int
    template: str
    labels: dict[str, t.Any]
    timestamp: int


class RemoteException(Exception):
    def __init__(self, message, remote_type):
        super().__init__(message)
        self.remote_type = remote_type


def _exception_type(exception: Exception):
    if isinstance(exception, RemoteException):
        return exception.remote_type
    t = type(exception)
    if t.__module__ == "builtins":
        return t.__name__
    return f"{t.__module__}.{t.__name__}"


def _serialise_exception(exception: Exception) -> Error:
    type_ = _exception_type(exception)
    message = getattr(exception, "message", str(exception))
    frames = [
        (f.filename, f.lineno or 0, f.name, f.line)
        for f in traceback.extract_tb(exception.__traceback__)
    ]
    return Error(type_, message, frames)


class LineBuffer(t.IO[str]):
    def __init__(self, fn):
        self._fn = fn
        self._buffer = ""

    def write(self, content):
        self._buffer += content
        lines = self._buffer.split("\n")
        for line in lines[:-1]:
            self._fn(line)
        self._buffer = lines[-1]
        return len(content)

    def flush(self):
        if self._buffer:
            self._fn(self._buffer)
            self._buffer = ""


@contextlib.contextmanager
def capture_streams(*, stdout, stderr):
    original = (sys.stdout, sys.stderr)
    sys.stdout = LineBuffer(stdout)
    sys.stderr = LineBuffer(stderr)
    yield
    sys.stdout.flush()
    sys.stderr.flush()
    sys.stdout, sys.stderr = original


@contextlib.contextmanager
def working_directory():
    with tempfile.TemporaryDirectory() as temp_dir:
        path = Path(temp_dir)
        original = os.getcwd()
        os.chdir(path)
        yield path
        os.chdir(original)


def counter():
    count = itertools.count()
    return lambda: next(count)


class Channel:
    def __init__(self, execution_id: str, blob_url_format: str, connection):
        self._execution_id = execution_id
        self._blob_url_format = blob_url_format
        self._connection = connection
        self._request_id = counter()
        self._requests: dict[int, Future[t.Any]] = {}
        self._cache: dict[t.Any, Future[t.Any]] = {}
        self._running = True
        self._exit_stack = contextlib.ExitStack()

    def __enter__(self):
        self._exit_stack.enter_context(
            capture_streams(
                stdout=lambda m: self.log_message(1, m),
                stderr=lambda m: self.log_message(3, m),
            )
        )
        self._directory = self._exit_stack.enter_context(working_directory())
        self._blob_store = self._exit_stack.enter_context(
            blobs.Store(self._blob_url_format)
        )
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self._exit_stack.close()

    @property
    def directory(self) -> Path:
        return self._directory

    @property
    def blob_store(self) -> blobs.Store:
        return self._blob_store

    def run(self):
        while self._running:
            if self._connection.poll(1):
                message = self._connection.recv()
                match message:
                    case ("success_result", (request_id, result)):
                        self._requests.pop(request_id).set_success(result)
                    case ("error_result", (request_id, error)):
                        self._requests.pop(request_id).set_error(error)
                    case other:
                        raise Exception(f"Received unhandled response: {other}")

    def _send(self, *message):
        self._connection.send(message)

    def _request(self, request, *, key=None, timeout=None):
        if key and key in self._cache:
            return self._cache[key].result(timeout)
        request_id = self._request_id()
        future = Future()
        self._requests[request_id] = future
        if key:
            self._cache[key] = future
        self._send("request", request_id, request)
        return future.result(timeout)

    def _notify(self, notification):
        self._send("notify", notification)

    def notify_executing(self):
        self._notify(ExecutingNotification())

    def record_result(self, data: t.Any):
        value = serialisation.serialise(data, self._blob_store)
        self._notify(RecordResultRequest(value))
        # TODO: wait for confirmation?
        self._running = False

    def record_error(self, exception):
        self._notify(RecordErrorRequest(_serialise_exception(exception)))
        # TODO: wait for confirmation?
        self._running = False

    def submit_execution(
        self,
        type: t.Literal["workflow", "task"],
        repository: str,
        target: str,
        arguments: tuple[t.Any, ...],
        *,
        wait_for: set[int] | None = None,
        cache: models.Cache | None = None,
        retries: models.Retries | None = None,
        defer: models.Defer | None = None,
        execute_after: dt.datetime | None = None,
        delay: float | dt.timedelta = 0,
        memo: list[int] | bool = False,
        requires: models.Requires | None = None,
    ) -> models.Execution[t.Any]:
        if delay:
            delay = (
                dt.timedelta(seconds=delay)
                if isinstance(delay, (int, float))
                else delay
            )
            execute_after = (execute_after or dt.datetime.now()) + delay
        # TODO: parallelise?
        serialised_arguments = [
            serialisation.serialise(a, self._blob_store) for a in arguments
        ]
        execution_id = self._request(
            SubmitExecutionRequest(
                type,
                repository,
                target,
                serialised_arguments,
                wait_for or set(),
                cache,
                defer,
                memo,
                execute_after,
                retries,
                requires,
            )
        )
        return models.Execution(
            lambda: self.resolve_reference(execution_id),
            execution_id,
        )

    @contextmanager
    def suspense(self, timeout: float | None):
        token = _timeout.set(timeout)
        try:
            yield
        finally:
            _timeout.reset(token)

    def suspend(self, delay: float | dt.timedelta | dt.datetime | None = None):
        execute_after = None
        if isinstance(delay, dt.datetime):
            execute_after = delay
        elif isinstance(delay, (int, float)):
            execute_after = dt.datetime.now() + dt.timedelta(seconds=delay)
        elif isinstance(delay, dt.timedelta):
            execute_after = dt.datetime.now() + delay
        self._notify(SuspendRequest(execute_after, []))

    def resolve_reference(self, execution_id):
        try:
            result = self._request(
                ResolveReferenceRequest(execution_id),
                key=("result", execution_id),
                timeout=_timeout.get(),
            )
            return _deserialise_result(result, self, "reference")
        except Timeout:
            self._notify(SuspendRequest(None, [execution_id]))

    def record_checkpoint(self, arguments):
        serialised_arguments = [
            serialisation.serialise(a, self._blob_store) for a in arguments
        ]
        self._notify(RecordCheckpointRequest(serialised_arguments))

    def persist_asset(
        self, path: Path | str | None = None, *, match: str | None = None
    ) -> models.Asset:
        if isinstance(path, str):
            path = Path(path)
        path = path or self._directory
        if not path.exists():
            raise Exception(f"path '{path}' doesn't exist")
        path = path.resolve()
        if not path.is_relative_to(self._directory):
            raise Exception(f"path ({path}) not in execution directory")
        # TODO: zip all assets?
        path_str = str(path.relative_to(self._directory))
        if path.is_file():
            if match:
                raise Exception("match cannot be specified for file")
            asset_type = 0
            blob_key = self._blob_store.upload(path)
            (mime_type, _) = mimetypes.guess_type(path)
            metadata = {"size": path.stat().st_size, "type": mime_type}
        elif path.is_dir():
            asset_type = 1
            sizes = []
            with tempfile.NamedTemporaryFile() as zip_file:
                zip_path = Path(zip_file.name)
                with zipfile.ZipFile(zip_path, "w") as zip:
                    for root, _, files in os.walk(path):
                        root = Path(root)
                        for file in files:
                            file_path = root.joinpath(file)
                            if not match or file_path.match(match):
                                zip.write(
                                    file_path, arcname=file_path.relative_to(path)
                                )
                                sizes.append(file_path.stat().st_size)
                blob_key = self._blob_store.upload(zip_path)
            metadata = {"totalSize": sum(sizes), "count": len(sizes)}
        else:
            raise Exception(f"path ({path}) isn't a file or a directory")
        asset_id = self._request(
            PersistAssetRequest(asset_type, path_str, blob_key, metadata)
        )
        return models.Asset(asset_id)

    def restore_asset(
        self, asset: models.Asset, *, to: Path | str | None = None
    ) -> Path:
        assert isinstance(asset, models.Asset)
        if to:
            if isinstance(to, str):
                to = Path(to)
            if not to.is_absolute():
                to = self._directory.joinpath(to)
            if not to.is_relative_to(self._directory):
                raise Exception("asset must be restored to execution directory")
        # TODO: use timeout?
        asset_type, path_str, blob_key = self._request(
            ResolveAssetRequest(asset.id), key=("asset", asset.id)
        )
        target = to or self._directory.joinpath(path_str)
        target.parent.mkdir(parents=True, exist_ok=True)
        if asset_type == 0:
            self._blob_store.download(blob_key, target)
        elif asset_type == 1:
            target.mkdir()
            with tempfile.NamedTemporaryFile() as zip_file:
                zip_path = Path(zip_file.name)
                self._blob_store.download(blob_key, zip_path)
                with zipfile.ZipFile(zip_path, "r") as zip:
                    zip.extractall(target)
        else:
            raise Exception(f"unrecognised asset type ({asset_type})")
        return target

    def log_message(self, level, template, **kwargs):
        timestamp = time.time() * 1000
        self._notify(LogMessageRequest(level, str(template), kwargs, int(timestamp)))


def get_channel() -> Channel | None:
    return _channel_context


def _build_exception(type_, message):
    # TODO: better way to re-create exception?
    parts = type_.rsplit(type_, maxsplit=1)
    module = "builtins" if len(parts) == 1 else parts[0]
    name = parts[-1]
    if module in sys.modules:
        class_ = sys.modules[module].get(name)
        if class_:
            return class_(message)
    return RemoteException(message, type_)


def _deserialise_result(result: models.Result, channel: Channel, description: str):
    match result:
        case ["value", value]:
            return _deserialise_value(value, channel, description)
        case ["error", type_, message]:
            raise _build_exception(type_, message)
        case ["abandoned"]:
            raise Exception("abandoned")
        case ["cancelled"]:
            raise Exception("cancelled")
        case ["suspended"]:
            raise Exception("suspended")
        case result:
            raise Exception(f"unexpected result ({result})")


# TODO: move into serialisation module?
def _deserialise_value(
    value: models.Value,
    channel: Channel,
    description: str,
) -> t.Any:
    match value:
        case ("raw", content, format, placeholders):
            return serialisation.deserialise(
                format,
                content,
                placeholders,
                channel.resolve_reference,
            )
        case ("blob", blob_key, _metadata, format, placeholders):
            content = channel.blob_store.get(blob_key)
            return serialisation.deserialise(
                format,
                content,
                placeholders,
                channel.resolve_reference,
            )


def _resolve_arguments(
    arguments: list[models.Value],
    channel: Channel,
) -> list[t.Any]:
    # TODO: parallelise
    return [
        _deserialise_value(v, channel, f"argument {i}") for i, v in enumerate(arguments)
    ]


def _execute(
    module_name: str,
    target_name: str,
    arguments: list[models.Value],
    execution_id: str,
    blob_url_format: str,
    conn,
):
    global _channel_context
    module = loader.load_module(module_name)
    with Channel(execution_id, blob_url_format, conn) as channel:
        threading.Thread(target=channel.run).start()
        _channel_context = channel
        try:
            resolved_arguments = _resolve_arguments(arguments, channel)
            channel.notify_executing()
            target = getattr(module, target_name)
            if not isinstance(target, decorators.Target) or target.definition.is_stub:
                raise Exception("not valid target")
            value = target.fn(*resolved_arguments)
        except KeyboardInterrupt:
            pass
        except Exception as e:
            channel.record_error(e)
        else:
            channel.record_result(value)
        finally:
            _channel_context = None


def _json_safe_value(value: models.Value):
    # TODO: tidy
    match value:
        case ("raw", content, format, placeholders):
            return ["raw", content.decode(), format, placeholders]
        case ("blob", key, metadata, format, placeholders):
            return ["blob", key, metadata, format, placeholders]


def _json_safe_arguments(arguments: list[models.Value]):
    return [_json_safe_value(v) for v in arguments]


def _parse_value(value: t.Any) -> models.Value:
    match value:
        case ["raw", content, format, placeholders]:
            return ("raw", content.encode(), format, placeholders)
        case ["blob", key, metadata, format, placeholders]:
            return ("blob", key, metadata, format, placeholders)
        case other:
            raise Exception(f"unrecognised value: {other}")


def _parse_result(result: t.Any) -> models.Result:
    match result:
        case ["error", type_, message]:
            return ("error", type_, message)
        case ["value", value]:
            return ("value", _parse_value(value))
        case ["abandoned"]:
            return ("abandoned",)
        case ["cancelled"]:
            return ("cancelled",)
        case other:
            raise Exception(f"unrecognised result: {other}")


class Execution:
    def __init__(
        self,
        execution_id: str,
        module: str,
        target: str,
        arguments: list[models.Value],
        blob_url_format: str,
        server_connection: server.Connection,
        loop: asyncio.AbstractEventLoop,
    ):
        self._id = execution_id
        self._server = server_connection
        self._loop = loop
        self._timestamp = time.time()  # TODO: better name
        self._status = ExecutionStatus.STARTING
        mp_context = multiprocessing.get_context("spawn")
        parent_conn, child_conn = mp_context.Pipe()
        self._connection = parent_conn
        self._process = mp_context.Process(
            target=_execute,
            args=(module, target, arguments, execution_id, blob_url_format, child_conn),
            name=f"Execution-{execution_id}",
        )

    @property
    def id(self):
        return self._id

    @property
    def status(self):
        return self._status

    @property
    def timestamp(self):
        return self._timestamp

    def touch(self, timestamp):
        self._timestamp = timestamp

    @property
    def sentinel(self):
        return self._process.sentinel

    def interrupt(self):
        self._status = ExecutionStatus.ABORTING
        pid = self._process.pid
        if pid:
            os.kill(pid, signal.SIGINT)

    def kill(self):
        self._status = ExecutionStatus.ABORTING
        self._process.kill()

    def join(self, timeout):
        self._process.join(timeout)
        return self._process.exitcode

    def _server_notify(self, request, params):
        coro = self._server.notify(request, params)
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        future.result()

    def _server_request(self, request, params, request_id, success_parser=None):
        success_parser = success_parser or (lambda x: x)
        coro = self._server.request(
            request,
            params,
            server.Callbacks(
                on_success=lambda result: self._try_send(
                    "success_result", (request_id, success_parser(result))
                ),
                on_error=lambda error: self._try_send(
                    "error_result", (request_id, error)
                ),
            ),
        )
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        return future.result()

    def _try_send(
        self,
        type: t.Literal["success_result", "error_result"],
        value: t.Any,
    ):
        try:
            self._connection.send((type, value))
        except BrokenPipeError:
            pass

    def _handle_notify(self, message):
        match message:
            case ExecutingNotification():
                self._status = ExecutionStatus.EXECUTING
            case RecordResultRequest(value):
                self._status = ExecutionStatus.STOPPING
                self._server_notify(
                    "put_result",
                    (self._id, _json_safe_value(value)),
                )
                self._process.join()
            case RecordErrorRequest(error):
                self._status = ExecutionStatus.STOPPING
                self._server_notify("put_error", (self._id, error))
                self._process.join()
            case SuspendRequest(execute_after, execution_ids):
                self._status = ExecutionStatus.STOPPING
                execute_after_ms = execute_after and int(
                    execute_after.timestamp() * 1000
                )
                self._server_notify(
                    "suspend", (self._id, execute_after_ms, execution_ids)
                )
                self._process.join()
            case RecordCheckpointRequest(arguments):
                self._server_notify(
                    "record_checkpoint",
                    (self._id, _json_safe_arguments(arguments)),
                )
            case LogMessageRequest(level, template, labels, timestamp):
                self._server_notify(
                    "log_messages", ([self._id, timestamp, level, template, labels],)
                )
            case other:
                raise Exception(f"Received unhandled notify: {other!r}")

    def _handle_request(self, request_id, request):
        match request:
            case SubmitExecutionRequest(
                type,
                repository,
                target,
                arguments,
                wait_for,
                cache,
                defer,
                memo,
                execute_after,
                retries,
                requires,
            ):
                execute_after_ms = execute_after and int(
                    execute_after.timestamp() * 1000
                )
                self._server_request(
                    "submit",
                    (
                        type,
                        repository,
                        target,
                        _json_safe_arguments(arguments),
                        self._id,
                        list(wait_for),
                        cache and cache._asdict(),
                        defer and defer._asdict(),
                        memo,
                        execute_after_ms,
                        retries and retries._asdict(),
                        requires,
                    ),
                    request_id,
                )
            case ResolveReferenceRequest(execution_id):
                # TODO: set (and unset) state on Execution to indicate waiting?
                self._server_request(
                    "get_result", (execution_id, self._id), request_id, _parse_result
                )
            case PersistAssetRequest(type, path, blob_key, metadata):
                self._server_request(
                    "put_asset", (self._id, type, path, blob_key, metadata), request_id
                )
            case ResolveAssetRequest(asset_id):
                self._server_request("get_asset", (asset_id, self._id), request_id)
            case other:
                raise Exception(f"Received unhandled request: {other!r}")

    def run(self):
        self._process.start()
        while self._process.is_alive():
            if self._connection.poll(1):
                try:
                    message = self._connection.recv()
                except EOFError:
                    pass
                else:
                    match message:
                        case ("notify", notify):
                            self._handle_notify(notify)
                        case ("request", request_id, request):
                            self._handle_request(request_id, request)
                        case other:
                            raise Exception(f"Received unhandled message: {other!r}")


def _wait_processes(sentinels: t.Iterable[int], until: float) -> set[int]:
    remaining = set(sentinels)
    while sentinels and time.time() < until:
        ready = multiprocessing.connection.wait(remaining, until - time.time())
        for sentinel in ready:
            assert isinstance(sentinel, int)
            remaining.remove(sentinel)
    return remaining


class Manager:
    def __init__(self, connection: server.Connection, blob_url_format: str):
        self._connection = connection
        self._blob_url_format = blob_url_format
        self._executions: dict[str, Execution] = {}
        self._last_heartbeat_sent = None

    async def _declare_targets(
        self, targets: dict[str, dict[models.TargetType, list[str]]]
    ) -> None:
        await self._connection.notify("declare_targets", (targets,))

    async def _send_heartbeats(self) -> t.NoReturn:
        while True:
            now = time.time()
            executions = [e for e in self._executions.values()]
            if self._should_send_heartbeats(executions, _AGENT_THRESHOLD_S, now):
                heartbeats = {e.id: e.status.value for e in executions}
                await self._connection.notify("record_heartbeats", (heartbeats,))
                self._last_heartbeat_sent = now
                for execution in executions:
                    execution.touch(now)
            elapsed = time.time() - now
            await asyncio.sleep(_EXECUTION_THRESHOLD_S - elapsed)

    def _should_send_heartbeats(
        self, executions: list[Execution], threshold_s: float, now: float
    ) -> bool:
        return (
            any(executions)
            or not self._last_heartbeat_sent
            or (now - self._last_heartbeat_sent) > threshold_s
        )

    async def run(self, targets: dict[str, dict[models.TargetType, list[str]]]) -> None:
        # TODO: only declare targets once when starting session? (not on reconnect)
        await self._declare_targets(targets)
        await self._send_heartbeats()

    def execute(
        self,
        execution_id: str,
        module: str,
        target: str,
        arguments: list[models.Value],
        loop: asyncio.AbstractEventLoop,
    ) -> None:
        if execution_id in self._executions:
            raise Exception(f"Execution ({execution_id}) already running")
        execution = Execution(
            execution_id,
            module,
            target,
            arguments,
            self._blob_url_format,
            self._connection,
            loop,
        )
        threading.Thread(
            target=self._run_execution,
            args=(execution, loop),
        ).start()

    def _run_execution(
        self, execution: Execution, loop: asyncio.AbstractEventLoop
    ) -> None:
        self._executions[execution.id] = execution
        try:
            execution.run()
        finally:
            del self._executions[execution.id]
            coro = self._connection.notify("notify_terminated", ([execution.id],))
            future = asyncio.run_coroutine_threadsafe(coro, loop)
            future.result()

    def abort(self, execution_id: str, timeout: int = 5) -> bool:
        execution = self._executions.get(execution_id)
        if not execution:
            return False
        execution.interrupt()
        if execution.join(timeout) is not None:
            print(
                f"Execution ({execution_id}) hasn't exited within timeout {timeout}. Killing..."
            )
            execution.kill()
        return True

    def abort_all(self, timeout: int = 5):
        until = time.time() + timeout
        executions = {e.sentinel: e for e in self._executions.values()}
        for execution in executions.values():
            execution.interrupt()
        remaining = _wait_processes(executions.keys(), until)
        if remaining:
            remaining_ids = [str(executions[s].id) for s in remaining]
            print(
                f"Executions ({', '.join(remaining_ids)}) haven't exited within timeout {timeout}. Killing..."
            )
            for execution in executions.values():
                execution.kill()
