import typing as t
import multiprocessing
import threading
import time
import enum
import asyncio
import datetime as dt
import hashlib
import json
import pickle
import contextvars
import contextlib
import concurrent.futures as cf

from . import server, future, blobs
from .types import Value

_BLOB_THRESHOLD = 100
_EXECUTION_THRESHOLD_S = 1.0
_AGENT_THRESHOLD_S = 5.0


T = t.TypeVar("T")

channel_context = contextvars.ContextVar("channel")


class ExecutionStatus(enum.Enum):
    STARTING = 0
    # TODO: preparing?
    EXECUTING = 1
    ABORTING = 2
    STOPPING = 3


class ExecutingNotification(t.NamedTuple):
    pass


class RecordResultRequest(t.NamedTuple):
    value: Value


class RecordErrorRequest(t.NamedTuple):
    error: t.Any


class ScheduleExecutionRequest(t.NamedTuple):
    schedule_id: int
    repository: str
    target: str
    arguments: list[Value]
    execute_after: dt.datetime | None
    cache_key: str | None
    deduplicate_key: str | None
    memo_key: str | None
    retry_count: int
    retry_delay_min: int
    retry_delay_max: int


class ResolveReferenceRequest(t.NamedTuple):
    execution_id: str


class RecordCheckpointRequest(t.NamedTuple):
    arguments: list[Value]


class LogMessageRequest(t.NamedTuple):
    level: int
    template: str
    labels: dict[str, t.Any]
    timestamp: int


class ExecutionScheduledResponse(t.NamedTuple):
    schedule_id: int
    execution_id: str


class ExecutionScheduleFailedResponse(t.NamedTuple):
    schedule_id: int
    error: str


class ResultResolvedResponse(t.NamedTuple):
    execution_id: str
    result: tuple[str, str, str]


class ResultResolveFailedResponse(t.NamedTuple):
    execution_id: str
    error: str


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


def _build_key(
    key: bool | t.Callable[[tuple[t.Any]], str],
    arguments: tuple[t.Any, ...],
    serialised_arguments: list[Value],
    prefix: str | None = None,
) -> str | None:
    if not key:
        return None
    cache_key = (
        key(*arguments)
        if callable(key)
        else "\0".join(x for a in serialised_arguments for x in a)
    )
    if prefix is not None:
        cache_key = prefix + "\0" + cache_key
    return hashlib.sha256(cache_key.encode()).hexdigest()


def _json_dumps(obj: t.Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


def _serialise_value(value: t.Any, blob_store: blobs.Store) -> Value:
    if isinstance(value, future.Future):
        return value.serialise()
    try:
        json_value = _json_dumps(value)
    except TypeError:
        pass
    else:
        if len(json_value) >= _BLOB_THRESHOLD:
            key = blob_store.put(json_value.encode())
            return ("blob", "json", key)
        return ("raw", "json", json_value)
    pickle_value = pickle.dumps(value)
    key = blob_store.put(pickle_value)
    return ("blob", "pickle", key)


class Channel:
    def __init__(self, execution_id: str, server_host: str, connection):
        self._execution_id = execution_id
        self._connection = connection
        self._blob_store = blobs.Store(server_host)
        self._last_schedule_id = 0
        self._schedules: dict[int, cf.Future] = {}
        self._resolves: dict[str, cf.Future] = {}
        self._running = True

    def run(self):
        while self._running:
            if self._connection.poll(1):
                message = self._connection.recv()
                match message:
                    case ExecutionScheduledResponse(schedule_id, execution_id):
                        self._schedules.pop(schedule_id).set_result(execution_id)
                    case ExecutionScheduleFailedResponse(schedule_id, error):
                        self._schedules.pop(schedule_id).set_exception(Exception(error))
                    case ResultResolvedResponse(execution_id, result):
                        self._resolves.pop(execution_id).set_result(result)
                    case ResultResolveFailedResponse(execution_id, error):
                        self._resolves.pop(execution_id).set_exception(Exception(error))
                    case other:
                        raise Exception(f"Received unhandled response: {other}")

    def get_blob(self, key: str):
        return self._blob_store.get(key)

    def _next_schedule_id(self):
        self._last_schedule_id += 1
        return self._last_schedule_id

    def _send(self, message):
        self._connection.send(message)

    def notify_executing(self):
        self._send(ExecutingNotification())

    def record_result(self, value: t.Any):
        self._send(RecordResultRequest(_serialise_value(value, self._blob_store)))
        # TODO: wait for confirmation?
        self._running = False

    def record_error(self, exception):
        error = str(exception)[:200]
        self._send(RecordErrorRequest(error))
        # TODO: wait for confirmation?
        self._running = False

    def schedule_execution(
        self,
        repository: str,
        target: str,
        arguments: tuple[t.Any, ...],
        *,
        cache: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
        cache_namespace: str | None = None,
        retries: int | tuple[int, int] | tuple[int, int, int] = 0,
        deduplicate: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
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
            _serialise_value(a, self._blob_store) for a in arguments
        ]
        default_namespace = f"{repository}:{target}"
        cache_key = _build_key(
            cache,
            arguments,
            serialised_arguments,
            cache_namespace or default_namespace,
        )
        deduplicate_key = _build_key(
            deduplicate, arguments, serialised_arguments, default_namespace
        )
        memo_key = _build_key(memo, arguments, serialised_arguments, default_namespace)
        retry_count, retry_delay_min, retry_delay_max = _parse_retries(retries)

        schedule_id = self._next_schedule_id()
        future = cf.Future()
        self._schedules[schedule_id] = future
        self._send(
            ScheduleExecutionRequest(
                schedule_id,
                repository,
                target,
                serialised_arguments,
                execute_after,
                cache_key,
                deduplicate_key,
                memo_key,
                retry_count,
                retry_delay_min,
                retry_delay_max,
            )
        )
        return future.result()

    def resolve_reference(self, execution_id):
        future = self._resolves.get(execution_id)
        if not future:
            future = cf.Future()
            self._resolves[execution_id] = future
            self._send(ResolveReferenceRequest(execution_id))
        value = future.result()
        return _deserialise_value(value, self._blob_store, "reference")

    def record_checkpoint(self, arguments):
        serialised_arguments = [
            _serialise_value(a, self._blob_store) for a in arguments
        ]
        self._send(RecordCheckpointRequest(serialised_arguments))

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


def _deserialise_value(value: Value, blob_store: blobs.Store, description: str):
    match value:
        case ("raw", "json", data):
            return _deserialise(data, json.loads, description)
        case ("blob", "json", key):
            content = blob_store.get(key)
            return _deserialise(content, json.loads, description)
        case ("blob", "pickle", key):
            content = blob_store.get(key)
            return _deserialise(content, pickle.loads, description)
        case ("error", error):
            # TODO: reconstruct exception state
            raise Exception(error)
        case ("abandoned"):
            raise Exception("abandoned")
        case ("cancelled"):
            raise Exception("cancelled")
        case result:
            raise Exception(f"unexeptected result ({result})")


def _resolve_argument(argument: Value, channel: Channel, description: str) -> t.Any:
    match argument:
        case ("raw", "json", value):
            return _deserialise(value, json.loads, description)
        case ("blob", "json", key):
            content = channel.get_blob(key)
            return _deserialise(content, json.loads, description)
        case ("blob", "pickle", key):
            content = channel.get_blob(key)
            return _deserialise(content, pickle.loads, description)
        case ("reference", execution_id):
            return future.Future(
                lambda: channel.resolve_reference(execution_id),
                argument,
            )
        case _:
            raise Exception(f"unrecognised argument ({argument})")


def _resolve_arguments(arguments: list[Value], channel: Channel) -> list[t.Any]:
    # TODO: parallelise
    return [
        _resolve_argument(a, channel, f"argument {i}") for i, a in enumerate(arguments)
    ]


class Capture(t.IO[str]):
    def __init__(self, channel: Channel, level: int):
        self._channel = channel
        self._level = level
        self._buffer = ""

    def write(self, content):
        self._buffer += content
        lines = self._buffer.split("\n")
        for line in lines[:-1]:
            self._channel.log_message(self._level, line)
        self._buffer = lines[-1]

    def flush(self):
        if self._buffer:
            self._channel.log_message(self._level, self._buffer)
            self._buffer = ""


def _execute(
    target: t.Callable,
    arguments: list[Value],
    execution_id: str,
    server_host: str,
    conn,
):
    channel = Channel(execution_id, server_host, conn)
    thread = threading.Thread(target=channel.run)
    thread.start()
    token = channel_context.set(channel)
    try:
        resolved_arguments = _resolve_arguments(arguments, channel)
        channel.notify_executing()
        with contextlib.redirect_stdout(Capture(channel, 1)) as stdout_capture:
            with contextlib.redirect_stderr(Capture(channel, 3)) as stderr_capture:
                value = target(*resolved_arguments)
        stdout_capture.flush()
        stderr_capture.flush()
    except Exception as e:
        channel.record_error(e)
    else:
        channel.record_result(value)
    finally:
        channel_context.reset(token)


class Execution:
    def __init__(
        self,
        execution_id: str,
        target: t.Callable,
        arguments: list[Value],
        server_host: str,
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
            args=(target, arguments, execution_id, server_host, child_conn),
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
                self._server_notify("put_result", (self._id, value))
                self._process.join()
            case RecordErrorRequest(error):
                self._status = ExecutionStatus.STOPPING
                self._server_notify("put_error", (self._id, error, {}))
                self._process.join()
            case RecordCheckpointRequest(arguments):
                self._server_notify("record_checkpoint", (self._id, arguments))
            case ScheduleExecutionRequest(
                schedule_id,
                repository,
                target,
                arguments,
                execute_after,
                cache_key,
                deduplicate_key,
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
                        arguments,
                        self._id,
                        execute_after_ms,
                        cache_key,
                        deduplicate_key,
                        memo_key,
                        retry_count,
                        retry_delay_min,
                        retry_delay_max,
                    ),
                    lambda execution_id: self._try_send(
                        ExecutionScheduledResponse(schedule_id, execution_id)
                    ),
                    lambda error: self._try_send(
                        ExecutionScheduleFailedResponse(schedule_id, error)
                    ),
                )
            case ResolveReferenceRequest(execution_id):
                # TODO: set (and unset) state on Execution to indicate waiting?
                self._server_request(
                    "get_result",
                    (execution_id, self._id),
                    lambda result: self._try_send(
                        ResultResolvedResponse(execution_id, result)
                    ),
                    lambda error: self._try_send(
                        ResultResolveFailedResponse(execution_id, error)
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
    def __init__(self, connection: server.Connection, server_host: str):
        self._connection = connection
        self._server_host = server_host
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
        arguments: list[Value],
        loop: asyncio.AbstractEventLoop,
    ):
        if execution_id in self._executions:
            raise Exception(f"Execution ({execution_id}) already running")
        execution = Execution(
            execution_id,
            target,
            arguments,
            self._server_host,
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
