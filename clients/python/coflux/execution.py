import typing as t
import multiprocessing
import threading
import time
import enum
import asyncio
import datetime as dt
import hashlib
import contextvars
import traceback
import sys
import tempfile
import os
import contextlib
import mimetypes
import zipfile
import itertools
from pathlib import Path

from . import server, blobs, models, serialisation


_EXECUTION_THRESHOLD_S = 1.0
_AGENT_THRESHOLD_S = 5.0


T = t.TypeVar("T")

channel_context = contextvars.ContextVar("channel")


class Future(t.Generic[T]):
    def __init__(self):
        self._event = threading.Event()
        self._result: T | None = None
        self._exception: BaseException | None = None

    def result(self, timeout: float | None = None):
        self._event.wait(timeout)
        if self._exception:
            raise self._exception
        else:
            return t.cast(T, self._result)

    def set_result(self, result):
        assert not self._result and not self._exception
        self._result = result
        self._event.set()

    def set_exception(self, exception):
        assert not self._result and not self._exception
        self._exception = exception
        self._event.set()


class ExecutionStatus(enum.Enum):
    STARTING = 0
    # TODO: preparing?
    EXECUTING = 1
    ABORTING = 2
    STOPPING = 3


class ExecutingNotification(t.NamedTuple):
    pass


class RecordResultRequest(t.NamedTuple):
    value: models.Value


class RecordErrorRequest(t.NamedTuple):
    type: str
    message: str
    frames: list[tuple[str, int, str, str | None]]


class ScheduleExecutionRequest(t.NamedTuple):
    schedule_id: int
    repository: str
    target: str
    arguments: list[models.Value]
    execute_after: dt.datetime | None
    cache_key: str | None
    cache_max_age: int | float | None
    defer_key: str | None
    memo_key: str | None
    retry_count: int
    retry_delay_min: int
    retry_delay_max: int


class ResolveReferenceRequest(t.NamedTuple):
    execution_id: int


class PersistAssetRequest(t.NamedTuple):
    persist_id: int
    type: int
    path: str
    blob_key: str
    metadata: dict[str, t.Any]


class ResolveAssetRequest(t.NamedTuple):
    asset_id: int


class RecordCheckpointRequest(t.NamedTuple):
    arguments: list[models.Value]


class LogMessageRequest(t.NamedTuple):
    level: int
    template: str
    labels: dict[str, t.Any]
    timestamp: int


class ExecutionScheduledResponse(t.NamedTuple):
    schedule_id: int
    execution_id: int


class ScheduleExecutionFailedResponse(t.NamedTuple):
    schedule_id: int
    error: str


class ResultResolvedResponse(t.NamedTuple):
    execution_id: int
    result: models.Result


class ResolveResultFailedResponse(t.NamedTuple):
    execution_id: int
    error: str


class AssetPersistedResponse(t.NamedTuple):
    persist_id: int
    asset_id: str


class PersistAssetFailedResponse(t.NamedTuple):
    persist_id: int
    error: str


class AssetResolvedResponse(t.NamedTuple):
    asset_id: int
    asset_type: int
    path: str
    blob_key: str


class ResolveAssetFailedResponse(t.NamedTuple):
    asset_id: int
    error: str


class RemoteException(Exception):
    def __init__(self, message, remote_type):
        super().__init__(message)
        self.remote_type = remote_type


def _parse_retries(
    retries: int | tuple[int, int] | tuple[int, int, int]
) -> tuple[int, int, int]:
    # TODO: parse string (e.g., '1h')
    match retries:
        case int(count):
            return (count, 0, 0)
        case (count, delay):
            return (count, delay, delay)
        case (count, delay_min, delay_max):
            return (count, delay_min, delay_max)
        case other:
            raise ValueError(other)


def _parse_cache(
    cache: bool | int | float | dt.timedelta,
    cache_key: t.Callable[[t.Tuple[t.Any, ...]], str] | None,
    namespace: str,
    arguments: tuple[t.Any, ...],
    serialised_arguments: list[models.Value],
) -> tuple[str | None, int | float | None]:
    if cache is False:
        return None, None
    cache_key_ = _build_key(
        cache_key or True,
        arguments,
        serialised_arguments,
        namespace,
    )
    if cache is True:
        return cache_key_, None
    cache_max_age = cache.total_seconds() if isinstance(cache, dt.timedelta) else cache
    return cache_key_, cache_max_age


def _value_key(value: models.Value) -> str:
    # TODO: tidy
    match value:
        case ["raw", content, format, placeholders]:
            # TODO: better/safer encoding
            placeholders_ = ";".join(
                f"{k}={v1}|{v2}" for k, (v1, v2) in sorted(placeholders.items())
            )
            return f"raw:{format}:{placeholders_}:{content}"
        case ["blob", key, _metadata, format, placeholders]:
            # TODO: better/safer encoding
            placeholders_ = ";".join(
                f"{k}={v1}|{v2}" for k, (v1, v2) in sorted(placeholders.items())
            )
            return f"blob:{format}:{placeholders_}:{key}"


def _build_key(
    key: bool | t.Callable[[tuple[t.Any]], str],
    arguments: tuple[t.Any, ...],
    serialised_arguments: list[models.Value],
    prefix: str | None = None,
) -> str | None:
    if not key:
        return None
    cache_key = (
        key(*arguments)
        if callable(key)
        else "\0".join(_value_key(v) for v in serialised_arguments)
    )
    if prefix is not None:
        cache_key = prefix + "\0" + cache_key
    return hashlib.sha256(cache_key.encode()).hexdigest()


def _exception_type(exception: Exception):
    if isinstance(exception, RemoteException):
        return exception.remote_type
    t = type(exception)
    if t.__module__ == "builtins":
        return t.__name__
    return f"{t.__module__}.{t.__name__}"


def _serialise_exception(
    exception: Exception,
) -> tuple[str, str, list[tuple[str, int, str, str | None]]]:
    type_ = _exception_type(exception)
    message = getattr(exception, "message", str(exception))
    frames = [
        (f.filename, f.lineno or 0, f.name, f.line)
        for f in traceback.extract_tb(exception.__traceback__)
    ]
    return type_, message, frames


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
        self._next_schedule_id = counter()
        self._next_persist_id = counter()
        self._schedules: dict[int, Future[str]] = {}
        self._persists: dict[int, Future[str]] = {}
        self._execution_resolves: dict[int, Future[models.Result]] = {}
        self._asset_resolves: dict[int, Future[tuple[int, str, str]]] = {}
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
                    case ExecutionScheduledResponse(schedule_id, execution_id):
                        self._schedules.pop(schedule_id).set_result(execution_id)
                    case ScheduleExecutionFailedResponse(schedule_id, error):
                        self._schedules.pop(schedule_id).set_exception(Exception(error))
                    case ResultResolvedResponse(execution_id, result):
                        self._execution_resolves.pop(execution_id).set_result(result)
                    case ResolveResultFailedResponse(execution_id, error):
                        self._execution_resolves.pop(execution_id).set_exception(
                            Exception(error)
                        )
                    case AssetPersistedResponse(persist_id, asset_id):
                        self._persists.pop(persist_id).set_result(asset_id)
                    case PersistAssetFailedResponse(persist_id, error):
                        self._persists.pop(persist_id).set_exception(Exception(error))
                    case AssetResolvedResponse(asset_id, asset_type, path, blob_key):
                        self._asset_resolves.pop(asset_id).set_result(
                            (asset_type, path, blob_key)
                        )
                    case ResolveAssetFailedResponse(asset_id, error):
                        self._asset_resolves.pop(asset_id).set_exception(
                            Exception(error)
                        )
                    case other:
                        raise Exception(f"Received unhandled response: {other}")

    def _send(self, message):
        self._connection.send(message)

    def notify_executing(self):
        self._send(ExecutingNotification())

    def record_result(self, data: t.Any):
        value = serialisation.serialise(data, self._blob_store, self._directory)
        self._send(RecordResultRequest(value))
        # TODO: wait for confirmation?
        self._running = False

    def record_error(self, exception):
        type_, message, frames = _serialise_exception(exception)
        self._send(RecordErrorRequest(type_, message, frames))
        # TODO: wait for confirmation?
        self._running = False

    def schedule_execution(
        self,
        repository: str,
        target: str,
        arguments: tuple[t.Any, ...],
        *,
        cache: bool | int | float | dt.timedelta = False,
        cache_key: t.Callable[[t.Tuple[t.Any, ...]], str] | None = None,
        cache_namespace: str | None = None,
        retries: int | tuple[int, int] | tuple[int, int, int] = 0,
        defer: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
        execute_after: dt.datetime | None = None,
        delay: int | float | dt.timedelta = 0,
        memo: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
    ) -> str:
        if delay:
            delay = (
                dt.timedelta(seconds=delay)
                if isinstance(delay, (int, float))
                else delay
            )
            execute_after = (execute_after or dt.datetime.now()) + delay
        # TODO: parallelise?
        serialised_arguments = [
            serialisation.serialise(a, self._blob_store, self._directory)
            for a in arguments
        ]
        default_namespace = f"{repository}:{target}"
        cache_key_, cache_max_age = _parse_cache(
            cache,
            cache_key,
            cache_namespace or default_namespace,
            arguments,
            serialised_arguments,
        )
        defer_key = _build_key(
            defer, arguments, serialised_arguments, default_namespace
        )
        memo_key = _build_key(memo, arguments, serialised_arguments, default_namespace)
        retry_count, retry_delay_min, retry_delay_max = _parse_retries(retries)

        schedule_id = self._next_schedule_id()
        future = Future()
        self._schedules[schedule_id] = future
        self._send(
            ScheduleExecutionRequest(
                schedule_id,
                repository,
                target,
                serialised_arguments,
                execute_after,
                cache_key_,
                cache_max_age,
                defer_key,
                memo_key,
                retry_count,
                retry_delay_min,
                retry_delay_max,
            )
        )
        return future.result()

    def resolve_reference(self, execution_id):
        future = self._execution_resolves.get(execution_id)
        if not future:
            future = Future()
            self._execution_resolves[execution_id] = future
            self._send(ResolveReferenceRequest(execution_id))
        result = future.result()
        return _deserialise_result(result, self._blob_store, self, "reference")

    def record_checkpoint(self, arguments):
        serialised_arguments = [
            serialisation.serialise(a, self._blob_store, self._directory)
            for a in arguments
        ]
        self._send(RecordCheckpointRequest(serialised_arguments))

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
        persist_id = self._next_persist_id()
        future = Future()
        self._persists[persist_id] = future
        self._send(
            PersistAssetRequest(persist_id, asset_type, path_str, blob_key, metadata)
        )
        asset_id = future.result()
        return models.Asset(asset_id)

    def restore_asset(
        self, asset: models.Asset, *, to: Path | str | None = None
    ) -> Path:
        if to:
            if isinstance(to, str):
                to = Path(to)
            if not to.is_absolute():
                to = self._directory.joinpath(to)
            if not to.is_relative_to(self._directory):
                raise Exception("asset must be restored to execution directory")
        future = self._asset_resolves.get(asset.id)
        if not future:
            future = Future()
            self._asset_resolves[asset.id] = future
            self._send(ResolveAssetRequest(asset.id))
        asset_type, path_str, blob_key = future.result()
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
        self._send(LogMessageRequest(level, template, kwargs, int(timestamp)))


def get_channel() -> Channel:
    return channel_context.get(None)


def _deserialise(
    data: T, deserialiser: t.Callable[[T], t.Any], description: str
) -> t.Any:
    try:
        return deserialiser(data)
    except ValueError as e:
        raise Exception(f"Failed to deserialise {description}") from e


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


def _deserialise_result(
    result: models.Result, blob_store: blobs.Store, channel: Channel, description: str
):
    match result:
        case ["value", value]:
            return _deserialise_value(value, channel, description)
        case ["error", type_, message]:
            raise _build_exception(type_, message)
        case ["abandoned"]:
            raise Exception("abandoned")
        case ["cancelled"]:
            raise Exception("cancelled")
        case result:
            raise Exception(f"unexeptected result ({result})")


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
    target: t.Callable,
    arguments: list[models.Value],
    execution_id: str,
    blob_url_format: str,
    conn,
):
    with Channel(execution_id, blob_url_format, conn) as channel:
        thread = threading.Thread(target=channel.run)
        thread.start()
        token = channel_context.set(channel)
        try:
            resolved_arguments = _resolve_arguments(arguments, channel)
            channel.notify_executing()
            value = target(*resolved_arguments)
        except Exception as e:
            channel.record_error(e)
        else:
            channel.record_result(value)
        finally:
            channel_context.reset(token)


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
        target: t.Callable,
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
        mp_context = multiprocessing.get_context("fork")
        parent_conn, child_conn = mp_context.Pipe()
        self._connection = parent_conn
        self._process = mp_context.Process(
            target=_execute,
            args=(target, arguments, execution_id, blob_url_format, child_conn),
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

    def abort(self) -> bool:
        self._status = ExecutionStatus.ABORTING
        self._process.kill()
        return True

    def _server_notify(self, request, params):
        coro = self._server.notify(request, params)
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        future.result()

    def _server_request(self, request, params, on_success, on_error):
        coro = self._server.request(request, params, on_success, on_error)
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        return future.result()

    def _try_send(self, message):
        try:
            self._connection.send(message)
        except BrokenPipeError:
            pass

    def _handle_message(self, message):
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
            case RecordErrorRequest(type_, message_, frames):
                self._status = ExecutionStatus.STOPPING
                self._server_notify("put_error", (self._id, type_, message_, frames))
                self._process.join()
            case RecordCheckpointRequest(arguments):
                self._server_notify(
                    "record_checkpoint",
                    (self._id, _json_safe_arguments(arguments)),
                )
            case ScheduleExecutionRequest(
                schedule_id,
                repository,
                target,
                arguments,
                execute_after,
                cache_key,
                cache_max_age,
                defer_key,
                memo_key,
                retry_count,
                retry_delay_min,
                retry_delay_max,
            ):
                execute_after_ms = execute_after and (execute_after.timestamp() * 1000)
                self._server_request(
                    "schedule",
                    (
                        repository,
                        target,
                        _json_safe_arguments(arguments),
                        self._id,
                        execute_after_ms,
                        cache_key,
                        cache_max_age,
                        defer_key,
                        memo_key,
                        retry_count,
                        retry_delay_min,
                        retry_delay_max,
                    ),
                    lambda execution_id: self._try_send(
                        ExecutionScheduledResponse(schedule_id, execution_id)
                    ),
                    lambda error: self._try_send(
                        ScheduleExecutionFailedResponse(schedule_id, error)
                    ),
                )
            case ResolveReferenceRequest(execution_id):
                # TODO: set (and unset) state on Execution to indicate waiting?
                self._server_request(
                    "get_result",
                    (execution_id, self._id),
                    lambda result: self._try_send(
                        ResultResolvedResponse(execution_id, _parse_result(result))
                    ),
                    lambda error: self._try_send(
                        ResolveResultFailedResponse(execution_id, error)
                    ),
                )
            case PersistAssetRequest(persist_id, type, path, blob_key, metadata):
                self._server_request(
                    "put_asset",
                    (self._id, type, path, blob_key, metadata),
                    lambda asset_id: self._try_send(
                        AssetPersistedResponse(persist_id, asset_id)
                    ),
                    lambda error: self._try_send(
                        PersistAssetFailedResponse(persist_id, error)
                    ),
                )

            case ResolveAssetRequest(asset_id):
                self._server_request(
                    "get_asset",
                    (asset_id, self._id),
                    lambda result: self._try_send(
                        AssetResolvedResponse(asset_id, *result)
                    ),
                    lambda error: self._try_send(
                        ResolveAssetFailedResponse(asset_id, error)
                    ),
                )
            case LogMessageRequest(level, template, labels, timestamp):
                self._server_notify(
                    "log_messages", ([self._id, timestamp, level, template, labels],)
                )
            case other:
                raise Exception(f"Received unhandled message: {other!r}")

    def run(self):
        self._process.start()
        while self._process.is_alive():
            if self._connection.poll(1):
                try:
                    message = self._connection.recv()
                except EOFError:
                    pass
                else:
                    self._handle_message(message)


class Manager:
    def __init__(self, connection: server.Connection, blob_url_format: str):
        self._connection = connection
        self._blob_url_format = blob_url_format
        self._executions: dict[str, Execution] = {}
        self._last_heartbeat_sent = None

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

    async def run(self):
        await self._send_heartbeats()

    def execute(
        self,
        execution_id: str,
        target: t.Callable,
        arguments: list[models.Value],
        loop: asyncio.AbstractEventLoop,
    ):
        if execution_id in self._executions:
            raise Exception(f"Execution ({execution_id}) already running")
        execution = Execution(
            execution_id,
            target,
            arguments,
            self._blob_url_format,
            self._connection,
            loop,
        )
        thread = threading.Thread(target=self._run_execution, args=(execution, loop))
        thread.start()

    def _run_execution(self, execution: Execution, loop: asyncio.AbstractEventLoop):
        self._executions[execution.id] = execution
        try:
            execution.run()
        finally:
            del self._executions[execution.id]
            coro = self._connection.notify("notify_terminated", ([execution.id],))
            future = asyncio.run_coroutine_threadsafe(coro, loop)
            future.result()

    def abort(self, execution_id: str) -> bool:
        execution = self._executions.get(execution_id)
        if not execution:
            return False
        return execution.abort()

    def abort_all(self):
        for execution in self._executions.values():
            execution.abort()
