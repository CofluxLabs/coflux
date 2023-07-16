import aiohttp
import asyncio
import hashlib
import json
import time
import threading
import os
import inspect
import urllib.parse
import enum
import types
import typing as t

from . import annotations, channel, future, context

BLOB_THRESHOLD = 100


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


def _json_dumps(obj: t.Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


def _load_module(module: types.ModuleType) -> dict:
    attrs = (getattr(module, k) for k in dir(module))
    return dict(a._coflux_target for a in attrs if hasattr(a, annotations.TARGET_KEY))


def _manifest_parameter(parameter: inspect.Parameter) -> dict:
    result = {"name": parameter.name}
    if parameter.annotation != inspect.Parameter.empty:
        result["annotation"] = str(
            parameter.annotation
        )  # TODO: better way to serialise?
    if parameter.default != inspect.Parameter.empty:
        result["default"] = _json_dumps(parameter.default)
    return result


def _generate_manifest(targets: dict) -> dict:
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
    client: "Client",
    loop: asyncio.AbstractEventLoop,
    from_execution_id: str,
) -> t.Any:
    match argument:
        case ["raw", "json", value]:
            return json.loads(value)
        case ["blob", "json", key]:
            task = client._get_blob(key)
            return asyncio.run_coroutine_threadsafe(task, loop).result()
        case ["reference", execution_id]:
            return future.Future(
                lambda: client.get_result(execution_id, from_execution_id),
                argument,
                loop,
            )
        case _:
            raise Exception(f"unrecognised argument ({argument})")


class Client:
    def __init__(
        self,
        project_id: str,
        environment_name: str,
        module: types.ModuleType,
        version: str,
        server_host: str,
        concurrency: int | None = None,
    ):
        self._project_id = project_id
        self._environment_name = environment_name
        self._module = module
        self._version = version
        self._server_host = server_host
        self._targets = _load_module(module)
        self._channel = channel.Channel(
            {"execute": self._handle_execute, "abort": self._handle_abort}
        )
        self._results = {}
        self._executions = {}
        self._semaphore = threading.Semaphore(
            concurrency or min(32, os.cpu_count() + 4)
        )
        self._last_heartbeat_sent = None

    def _url(self, scheme: str, path: str, **kwargs) -> str:
        query_string = f"?{urllib.parse.urlencode(kwargs)}" if kwargs else ""
        return f"{scheme}://{self._server_host}/{path}{query_string}"

    async def _get_blob(self, key: str) -> t.Any:
        # TODO: make blob url configurable
        async with self._session.get(self._url("http", f"blobs/{key}")) as resp:
            resp.raise_for_status()
            return await resp.json()

    async def _put_blob(self, content: str) -> str:
        key = hashlib.sha256(content.encode()).hexdigest()
        # TODO: make blob url configurable
        # TODO: check whether already uploaded (using head request)?
        async with self._session.put(
            self._url("http", f"blobs/{key}"), data=content
        ) as resp:
            resp.raise_for_status()
        return key

    async def _prepare_result(self, value: t.Any) -> t.Tuple[str, str, str]:
        if isinstance(value, future.Future):
            return value.serialise()
        json_value = _json_dumps(value)
        if len(json_value) >= BLOB_THRESHOLD:
            key = await self._put_blob(json_value)
            return ["blob", "json", key]
        return ["raw", "json", json_value]

    # TODO: combine with above
    async def _serialise_argument(self, value: t.Any) -> t.Tuple[str, str, str]:
        if isinstance(value, future.Future):
            return value.serialise()
        json_value = _json_dumps(value)
        if len(json_value) >= BLOB_THRESHOLD:
            key = await self._put_blob(json_value)
            return ["blob", "json", key]
        return ["raw", "json", json_value]

    async def _put_result(self, execution_id: str, value: t.Any) -> None:
        result = await self._prepare_result(value)
        await self._channel.notify("put_result", execution_id, result)

    async def _put_cursor(self, execution_id: str, value: t.Any) -> None:
        result = await self._prepare_result(value)
        await self._channel.notify("put_cursor", execution_id, result)

    async def _put_error(self, execution_id: str, exception: Exception) -> None:
        # TODO: include exception state
        await self._channel.notify("put_error", execution_id, str(exception)[:200], {})

    # TODO: consider thread safety
    def _execute_target(
        self,
        execution_id: str,
        target_name: str,
        arguments: list[list[t.Any]],
        loop: asyncio.AbstractEventLoop,
    ) -> None:
        target = self._targets[target_name][1]
        # TODO: fetch blobs in parallel
        arguments = [_resolve_argument(a, self, loop, execution_id) for a in arguments]
        self._semaphore.acquire()
        self._set_execution_status(execution_id, ExecutionStatus.EXECUTING)
        token = context.set_execution(execution_id, self, loop)
        try:
            value = target(*arguments)
        except Exception as e:
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
        # TODO: consider repository
        # TODO: check execution isn't already running?
        print(f"Handling execute '{target_name}' ({execution_id})...")
        loop = asyncio.get_running_loop()
        args = (execution_id, target_name, arguments, loop)
        thread = threading.Thread(target=self._execute_target, args=args, daemon=True)
        self._executions[execution_id] = (thread, time.time(), ExecutionStatus.STARTING)
        thread.start()

    async def _handle_abort(self, execution_id: str) -> None:
        print(f"Aborting execution ({execution_id})...")
        self._set_execution_status(execution_id, ExecutionStatus.ABORTING)

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

    async def run(self) -> None:
        module_name = self._module.__name__
        print(f"Agent starting ({module_name}@{self._version})...")
        async with aiohttp.ClientSession() as self._session:
            # TODO: heartbeat (and timeout) value?
            async with self._session.ws_connect(
                self._url(
                    "ws",
                    "agent",
                    project=self._project_id,
                    environment=self._environment_name,
                ),
                heartbeat=5,
            ) as websocket:
                print(f"Connected ({self._server_host}, {self._project_id}).")
                # TODO: reset channel?
                manifest = _generate_manifest(self._targets)
                await self._channel.notify(
                    "register", module_name, self._version, manifest
                )
                coros = [self._channel.run(websocket), self._send_heartbeats()]
                done, pending = await asyncio.wait(
                    coros, return_when=asyncio.FIRST_COMPLETED
                )
                print("Disconnected.")
                for task in pending:
                    task.cancel()

    async def schedule_step(
        self,
        execution_id: str,
        target: str,
        arguments: t.Tuple[t.Any, ...],
        repository: str | None = None,
        cache_key: str | None = None,
    ) -> str:
        repository = repository or self._module.__name__
        serialised_arguments = [await self._serialise_argument(a) for a in arguments]
        return await self._channel.request(
            "schedule_step",
            repository,
            target,
            serialised_arguments,
            execution_id,
            cache_key,
        )

    async def schedule_task(
        self,
        execution_id: str,
        target: str,
        arguments: t.Tuple[t.Any, ...],
        repository: str | None = None,
    ) -> str:
        repository = repository or self._module.__name__
        serialised_arguments = [await self._serialise_argument(a) for a in arguments]
        return await self._channel.request(
            "schedule_task", repository, target, serialised_arguments, execution_id
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
                return await self._get_blob(key)
            case ["error", error]:
                # TODO: reconstruct exception state
                raise Exception(error)
            case ["abandoned"]:
                raise Exception("abandoned")
            case result:
                raise Exception(f"unexeptected result ({result})")


def init(
    project: str,
    environment: str,
    module: types.ModuleType,
    version: str,
    host: str,
    concurrency: int | None = None,
) -> None:
    try:
        client = Client(project, environment, module, version, host, concurrency)
        asyncio.run(client.run())
    except KeyboardInterrupt:
        pass
