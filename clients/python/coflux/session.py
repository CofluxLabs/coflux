import asyncio
import hashlib
import json
import time
import threading
import inspect
import urllib.parse
import enum
import typing as t
import random
import traceback
import websockets
import httpx
import pickle

from . import context
from .channel import Channel
from .future import Future

_BLOB_THRESHOLD = 100


class ExecutionStatus(enum.Enum):
    STARTING = 0
    EXECUTING = 1
    WAITING = 2
    ABORTING = 3


class LogLevel(enum.Enum):
    DEBUG = 0
    INFO = 1
    WARNING = 2
    ERROR = 3


class SessionExpired(Exception):
    pass


def _json_dumps(obj: t.Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


def _manifest_parameter(parameter: inspect.Parameter) -> dict:
    result = {"name": parameter.name}
    if parameter.annotation != inspect.Parameter.empty:
        result["annotation"] = str(
            parameter.annotation
        )  # TODO: better way to serialise?
    if parameter.default != inspect.Parameter.empty:
        result["default"] = _json_dumps(parameter.default)
    return result


def _build_manifest(targets: dict) -> dict:
    return {
        name: {
            "type": type,
            "parameters": [
                _manifest_parameter(p)
                for p in inspect.signature(fn).parameters.values()
            ],
        }
        for name, (type, fn) in targets.items()
    }


def _resolve_argument(
    argument: list,
    session: "Session",
    loop: asyncio.AbstractEventLoop,
    from_execution_id: str,
) -> t.Any:
    match argument:
        case ["raw", "json", value]:
            return json.loads(value)
        case ["blob", "json", key]:
            task = session._get_blob(key)
            content = asyncio.run_coroutine_threadsafe(task, loop).result()
            return json.loads(content)
        case ["blob", "pickle", key]:
            task = session._get_blob(key)
            content = asyncio.run_coroutine_threadsafe(task, loop).result()
            return pickle.loads(content)
        case ["reference", execution_id]:
            return Future(
                lambda: session.get_result(execution_id, from_execution_id),
                argument,
                loop,
            )
        case _:
            raise Exception(f"unrecognised argument ({argument})")


class Session:
    def __init__(
        self,
        project_id: str,
        environment_name: str,
        version: str,
        server_host: str,
        concurrency: int,
    ):
        self._project_id = project_id
        self._environment_name = environment_name
        self._version = version
        self._server_host = server_host
        self._concurrency = concurrency
        self._modules = {}
        self._channel = Channel(
            {"execute": self._handle_execute, "abort": self._handle_abort}
        )
        self._results = {}
        self._executions = {}
        self._semaphore = threading.Semaphore(concurrency)
        self._last_heartbeat_sent = None

    def _url(self, scheme: str, path: str, **kwargs) -> str:
        params = {k: v for k, v in kwargs.items() if v is not None} if kwargs else None
        query_string = f"?{urllib.parse.urlencode(params)}" if params else ""
        return f"{scheme}://{self._server_host}/{path}{query_string}"

    async def _get_blob(self, key: str) -> bytes:
        # TODO: make blob url configurable
        async with httpx.AsyncClient() as client:
            response = await client.get(self._url("http", f"blobs/{key}"))
            response.raise_for_status()
            return response.content

    async def _put_blob(self, content: bytes) -> str:
        key = hashlib.sha256(content).hexdigest()
        # TODO: make blob url configurable
        # TODO: check whether already uploaded (using head request)?
        async with httpx.AsyncClient() as client:
            response = await client.put(
                self._url("http", f"blobs/{key}"), content=content
            )
            response.raise_for_status()
        return key

    async def _serialise_value(self, value: t.Any) -> t.Tuple[str, str, str]:
        if isinstance(value, Future):
            return value.serialise()
        try:
            json_value = _json_dumps(value)
        except TypeError:
            pass
        else:
            if len(json_value) >= _BLOB_THRESHOLD:
                key = await self._put_blob(json_value.encode())
                return ["blob", "json", key]
            return ["raw", "json", json_value]
        pickle_value = pickle.dumps(value)
        key = await self._put_blob(pickle_value)
        return ["blob", "pickle", key]

    async def _put_result(self, execution_id: str, value: t.Any) -> None:
        result = await self._serialise_value(value)
        await self._channel.notify("put_result", execution_id, result)

    async def _put_cursor(self, execution_id: str, value: t.Any) -> None:
        result = await self._serialise_value(value)
        await self._channel.notify("put_cursor", execution_id, result)

    async def _put_error(self, execution_id: str, exception: Exception) -> None:
        # TODO: include exception state
        await self._channel.notify("put_error", execution_id, str(exception)[:200], {})

    # TODO: consider thread safety
    def _execute_target(
        self,
        execution_id: str,
        repository: str,
        target_name: str,
        arguments: list[list[t.Any]],
        loop: asyncio.AbstractEventLoop,
    ) -> None:
        target = self._modules[repository][target_name][1]
        # TODO: fetch blobs in parallel
        arguments = [_resolve_argument(a, self, loop, execution_id) for a in arguments]
        self._semaphore.acquire()
        self._set_execution_status(execution_id, ExecutionStatus.EXECUTING)
        token = context.set_execution(execution_id, self, loop)
        try:
            value = target(*arguments)
        except Exception as e:
            traceback.print_exc()
            task = self._put_error(execution_id, e)
            asyncio.run_coroutine_threadsafe(task, loop).result()
        else:
            if inspect.isgenerator(value):
                for cursor in value:
                    if cursor is not None:
                        task = self._put_cursor(execution_id, cursor)
                        asyncio.run_coroutine_threadsafe(task, loop).result()
                    if self._executions[execution_id][2] == ExecutionStatus.ABORTING:
                        value.close()
            else:
                task = self._put_result(execution_id, value)
                asyncio.run_coroutine_threadsafe(task, loop).result()
        finally:
            del self._executions[execution_id]
            context.reset_execution(token)
            self._semaphore.release()

    async def _handle_execute(
        self,
        execution_id: str,
        repository: str,
        target_name: str,
        arguments: list[list[t.Any]],
    ) -> None:
        # TODO: check execution isn't already running?
        print(f"Handling execute '{target_name}' ({execution_id})...")
        loop = asyncio.get_running_loop()
        args = (execution_id, repository, target_name, arguments, loop)
        thread = threading.Thread(target=self._execute_target, args=args, daemon=True)
        self._executions[execution_id] = (thread, time.time(), ExecutionStatus.STARTING)
        thread.start()

    async def _handle_abort(self, execution_id: str) -> None:
        if execution_id in self._executions:
            print(f"Aborting execution ({execution_id})...")
            self._set_execution_status(execution_id, ExecutionStatus.ABORTING)
        else:
            print(f"Ignored abort for unrecognised execution ({execution_id}).")

    def _should_send_heartbeat(
        self, executions: dict, threshold_s: float, now: float
    ) -> bool:
        return (
            executions
            or not self._last_heartbeat_sent
            or (now - self._last_heartbeat_sent) > threshold_s
        )

    async def _send_heartbeats(
        self, execution_threshold_s: float = 1.0, agent_threshold_s: float = 5.0
    ) -> t.NoReturn:
        while True:
            now = time.time()
            executions = {
                id: e[2].value
                for id, e in self._executions.items()
                if now - e[1] > execution_threshold_s
            }
            if self._should_send_heartbeat(executions, agent_threshold_s, now):
                await self._channel.notify("record_heartbeats", executions)
                self._last_heartbeat_sent = now
            await asyncio.sleep(1)

    async def register_module(self, name: str, targets: dict) -> None:
        self._modules[name] = targets
        await self._channel.notify(
            "register", name, self._version, _build_manifest(targets)
        )

    async def run(self) -> None:
        while True:
            print(
                f"Connecting ({self._server_host}, {self._project_id}/{self._environment_name})..."
            )
            url = self._url(
                "ws",
                "agent",
                project=self._project_id,
                environment=self._environment_name,
                session=self._channel.session_id,
            )
            try:
                async with websockets.connect(url) as websocket:
                    print("Connected.")
                    coros = [self._channel.run(websocket), self._send_heartbeats()]
                    _, pending = await asyncio.wait(
                        coros, return_when=asyncio.FIRST_COMPLETED
                    )
                    for task in pending:
                        task.cancel()
                    if websocket.close_code == 4001:
                        raise SessionExpired()
            except OSError:
                pass
            delay = 1 + 3 * random.random()  # TODO: exponential backoff
            print(f"Disconnected (reconnecting in {delay:.1f} seconds).")
            await asyncio.sleep(delay)

    async def schedule(
        self,
        repository: str,
        target: str,
        arguments: t.Tuple[t.Any, ...],
        execution_id: str,
        cache_key: str | None,
        retries: tuple[int, int, int],
    ) -> str:
        serialised_arguments = [await self._serialise_value(a) for a in arguments]
        retry_count, retry_delay_min, retry_delay_max = retries
        return await self._channel.request(
            "schedule",
            repository,
            target,
            serialised_arguments,
            execution_id,
            cache_key,
            retry_count,
            retry_delay_min,
            retry_delay_max,
        )

    async def log_message(
        self, execution_id: str, level: LogLevel, message: str
    ) -> None:
        await self._channel.notify("log_message", execution_id, level, message)

    def _set_execution_status(self, execution_id: str, status: ExecutionStatus) -> None:
        thread, start_time, _status = self._executions[execution_id]
        self._executions[execution_id] = (thread, start_time, status)

    async def get_result(self, execution_id: str, from_execution_id: str) -> t.Any:
        if execution_id not in self._results:
            self._semaphore.release()
            self._set_execution_status(from_execution_id, ExecutionStatus.WAITING)
            self._results[execution_id] = await self._channel.request(
                "get_result", execution_id, from_execution_id
            )
            self._set_execution_status(from_execution_id, ExecutionStatus.STARTING)
            self._semaphore.acquire()
            self._set_execution_status(from_execution_id, ExecutionStatus.EXECUTING)
        match self._results[execution_id]:
            case ["raw", "json", value]:
                return json.loads(value)
            case ["blob", "json", key]:
                content = await self._get_blob(key)
                return json.loads(content)
            case ["blob", "pickle", key]:
                content = await self._get_blob(key)
                return pickle.loads(content)
            case ["error", error]:
                # TODO: reconstruct exception state
                raise Exception(error)
            case ["abandoned"]:
                raise Exception("abandoned")
            case ["aborted"]:
                raise Exception("aborted")
            case result:
                raise Exception(f"unexeptected result ({result})")
