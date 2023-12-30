import typing as t
import multiprocessing
import threading
import time
import enum
import inspect
import asyncio
import datetime as dt
import hashlib
import json
import pickle
import contextvars
import traceback
import contextlib

from . import server, future, blobs

_BLOB_THRESHOLD = 100
_EXECUTION_THRESHOLD_S = 1.0
_AGENT_THRESHOLD_S = 5.0


channel_context = contextvars.ContextVar("channel")


class ExecutionStatus(enum.Enum):
    STARTING = 0
    # TODO: preparing?
    EXECUTING = 1
    ABORTING = 2
    STOPPING = 3


class ExecutingNotification(t.NamedTuple):
    pass


class RecordCursorRequest(t.NamedTuple):
    value: t.Any


class RecordResultRequest(t.NamedTuple):
    value: t.Any


class RecordErrorRequest(t.NamedTuple):
    error: t.Any


class ScheduleExecutionRequest(t.NamedTuple):
    schedule_id: int
    repository: str
    target: str
    arguments: t.Tuple[t.Any, ...]
    execute_after: dt.datetime | None
    cache_key: str | None
    deduplicate_key: str | None
    retry_count: int
    retry_delay_min: int
    retry_delay_max: int


class ResolveReferenceRequest(t.NamedTuple):
    execution_id: str


class LogMessageRequest(t.NamedTuple):
    level: int
    message: str
    timestamp: int


class ExecutionScheduledResponse(t.NamedTuple):
    schedule_id: int
    execution_id: str


class ResultResolvedResponse(t.NamedTuple):
    execution_id: str
    result: t.Any


def _parse_retries(
    retries: int | tuple[int, int] | tuple[int, int, int]
) -> tuple[int, int, int]:
    if isinstance(retries, int):
        return (retries, 0, 0)
    assert isinstance(retries, tuple)
    assert isinstance(retries[0], int)
    # TODO: parse string (e.g., '1h')
    if len(retries) == 3:
        return retries
    if len(retries) == 2:
        return (retries[0], retries[1], retries[1])


def _build_key(
    key: bool | t.Callable[[t.Tuple[t.Any, ...]], str],
    arguments: t.Tuple[t.Any, ...],
    serialised_arguments: list[t.Tuple[str, str, str]],
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


def _serialise_value(value: t.Any, blob_store: blobs.Store) -> t.Tuple[str, str, str]:
    if isinstance(value, future.Future):
        return value.serialise()
    try:
        json_value = _json_dumps(value)
    except TypeError:
        pass
    else:
        if len(json_value) >= _BLOB_THRESHOLD:
            key = blob_store.put(json_value.encode())
            return ["blob", "json", key]
        return ["raw", "json", json_value]
    pickle_value = pickle.dumps(value)
    key = blob_store.put(pickle_value)
    return ["blob", "pickle", key]


class Future:
    def __init__(self):
        self._event = threading.Event()
        self._value = None

    def set(self, value):
        self._value = value
        self._event.set()

    def get(self, timeout=None):
        if not self._event.wait(timeout):
            raise Exception("Timed out")
        return self._value


class Channel:
    def __init__(self, execution_id: str, server_host: str, connection):
        self._execution_id = execution_id
        self._connection = connection
        self._blob_store = blobs.Store(server_host)
        self._last_schedule_id = 0
        self._schedules: dict[int, Future] = {}
        self._resolves: dict[int, Future] = {}
        self._running = True

    def run(self):
        while self._running:
            if self._connection.poll(1):
                message = self._connection.recv()
                match message:
                    case ExecutionScheduledResponse(schedule_id, execution_id):
                        self._schedules.pop(schedule_id).set(execution_id)
                    case ResultResolvedResponse(execution_id, result):
                        self._resolves.pop(execution_id).set(result)
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

    def record_result(self, value):
        self._send(RecordResultRequest(_serialise_value(value, self._blob_store)))
        # TODO: wait for confirmation?
        self._running = False

    def record_cursor(self, value):
        self._send(RecordCursorRequest(_serialise_value(value, self._blob_store)))
        # TODO: wait for confirmation?

    def record_error(self, exception):
        error = str(exception)[:200]
        self._send(RecordErrorRequest(error))
        # TODO: wait for confirmation?
        self._running = False

    def schedule_execution(
        self,
        repository: str,
        target: str,
        arguments: t.Tuple[t.Any, ...],
        *,
        cache: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
        cache_namespace: str | None = None,
        retries: int | tuple[int, int] | tuple[int, int, int] = 0,
        deduplicate: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
        execute_after: dt.datetime | None = None,
        delay: int | float | dt.timedelta = 0,
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
        cache_key = _build_key(
            cache,
            arguments,
            serialised_arguments,
            cache_namespace or f"{repository}:{target}",
        )
        deduplicate_key = _build_key(deduplicate, arguments, serialised_arguments)
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
                cache_key,
                deduplicate_key,
                retry_count,
                retry_delay_min,
                retry_delay_max,
            )
        )
        return future.get()

    def resolve_reference(self, execution_id):
        future = self._resolves.get(execution_id)
        if not future:
            future = Future()
            self._resolves[execution_id] = future
            self._send(ResolveReferenceRequest(execution_id))
        value = future.get()
        return _deserialise_value(value, self._blob_store)

    def log_message(self, level, message):
        timestamp = time.time() * 1000
        self._send(LogMessageRequest(level, message, timestamp))


def get_channel() -> Channel:
    return channel_context.get(None)


def _deserialise_value(value: t.Any, blob_store: blobs.Store):
    match value:
        case ["raw", "json", value]:
            return json.loads(value)
        case ["blob", "json", key]:
            content = blob_store.get(key)
            return json.loads(content)
        case ["blob", "pickle", key]:
            content = blob_store.get(key)
            return pickle.loads(content)
        case ["error", error]:
            # TODO: reconstruct exception state
            raise Exception(error)
        case ["abandoned"]:
            raise Exception("abandoned")
        case ["cancelled"]:
            raise Exception("cancelled")
        case result:
            raise Exception(f"unexeptected result ({result})")


def _resolve_argument(argument: list, channel: Channel) -> t.Any:
    match argument:
        case ["raw", "json", value]:
            return json.loads(value)
        case ["blob", "json", key]:
            content = channel.get_blob(key)
            return json.loads(content)
        case ["blob", "pickle", key]:
            content = channel.get_blob(key)
            return pickle.loads(content)
        case ["reference", execution_id]:
            return future.Future(
                lambda: channel.resolve_reference(execution_id),
                argument,
            )
        case _:
            raise Exception(f"unrecognised argument ({argument})")


def _resolve_arguments(arguments: list[list], channel: Channel) -> list[t.Any]:
    # TODO: parallelise
    return [_resolve_argument(a, channel) for a in arguments]


class Capture:
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
    arguments: list[list[t.Any]],
    execution_id: str,
    server_host: str,
    conn,
):
    channel = Channel(execution_id, server_host, conn)
    thread = threading.Thread(target=channel.run)
    thread.start()
    resolved_arguments = _resolve_arguments(arguments, channel)
    token = channel_context.set(channel)
    channel.notify_executing()
    try:
        with contextlib.redirect_stdout(Capture(channel, 1)) as stdout_capture:
            with contextlib.redirect_stderr(Capture(channel, 3)) as stderr_capture:
                value = target(*resolved_arguments)
        stdout_capture.flush()
        stderr_capture.flush()
    except Exception as e:
        traceback.print_exc()
        channel.record_error(e)
    else:
        if inspect.isgenerator(value):
            for cursor in value:
                if cursor is not None:
                    channel.record_cursor(cursor)
            channel.record_result()
        else:
            channel.record_result(value)
    finally:
        channel_context.reset(token)


class Execution:
    def __init__(
        self,
        execution_id: str,
        target: t.Callable,
        arguments: list[list[t.Any]],
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

    def abort(self):
        self._status = ExecutionStatus.ABORTING
        self._process.kill()

    def _server_notify(self, request, params):
        coro = self._server.notify(request, params)
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        future.result()

    def _server_request(self, request, params, callback):
        coro = self._server.request(request, params, callback)
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        return future.result()

    def _handle_message(self, message):
        match message:
            case ExecutingNotification():
                self._status = ExecutionStatus.EXECUTING
            case RecordCursorRequest(value):
                self._server_notify("put_cursor", (self._id, value))
            case RecordResultRequest(value):
                self._status = ExecutionStatus.STOPPING
                self._server_notify("put_result", (self._id, value))
                self._process.join()
            case RecordErrorRequest(error):
                self._status = ExecutionStatus.STOPPING
                self._server_notify("put_error", (self._id, error, {}))
                self._process.join()
            case ScheduleExecutionRequest(
                schedule_id,
                repository,
                target,
                arguments,
                execute_after,
                cache_key,
                deduplicate_key,
                retry_count,
                retry_delay_min,
                retry_delay_max,
            ):
                self._server_request(
                    "schedule",
                    (
                        repository,
                        target,
                        arguments,
                        self._id,
                        execute_after,
                        cache_key,
                        deduplicate_key,
                        retry_count,
                        retry_delay_min,
                        retry_delay_max,
                    ),
                    lambda execution_id: self._connection.send(
                        ExecutionScheduledResponse(schedule_id, execution_id)
                    ),
                )
            case ResolveReferenceRequest(execution_id):
                # TODO: set (and unset) state on Execution to indicate waiting?
                self._server_request(
                    "get_result",
                    (execution_id, self._id),
                    lambda result: self._connection.send(
                        ResultResolvedResponse(execution_id, result)
                    ),
                )
            case LogMessageRequest(level, message, timestamp):
                self._server_notify(
                    "log_messages", ([self._id, timestamp, level, message],)
                )
            case other:
                raise Exception(f"Received unhandled message: {other!r}")

    def run(self):
        self._process.start()
        while self._process.is_alive():
            if self._connection.poll(1):
                message = self._connection.recv()
                self._handle_message(message)
        self._server_notify("notify_terminated", ([self._id],))


class Manager:
    def __init__(self, connection: server.Connection, server_host: str):
        self._connection = connection
        self._server_host = server_host
        self._executions: dict[str, Execution] = {}
        self._last_heartbeat_sent = None

    async def _send_heartbeats(self) -> t.NoReturn:
        while True:
            now = time.time()
            executions = [
                e
                for e in self._executions.values()
                if now - e.timestamp > _EXECUTION_THRESHOLD_S
            ]
            if self._should_send_heartbeat(executions, _AGENT_THRESHOLD_S, now):
                heartbeats = {e.id: e.status.value for e in executions}
                await self._connection.notify("record_heartbeats", (heartbeats,))
                self._last_heartbeat_sent = now
                for execution in executions:
                    execution.touch(now)
            await asyncio.sleep(1)

    def _should_send_heartbeat(
        self, executions: dict, threshold_s: float, now: float
    ) -> bool:
        return (
            executions
            or not self._last_heartbeat_sent
            or (now - self._last_heartbeat_sent) > threshold_s
        )

    async def run(self):
        await self._send_heartbeats()

    def execute(
        self,
        execution_id: str,
        target: t.Callable,
        arguments: list[list[t.Any]],
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
        thread = threading.Thread(target=self._run_execution, args=(execution,))
        thread.start()

    def _run_execution(self, execution: Execution):
        self._executions[execution.id] = execution
        execution.run()
        del self._executions[execution.id]

    def abort(self, execution_id: str) -> bool:
        self._executions[execution_id].abort()
