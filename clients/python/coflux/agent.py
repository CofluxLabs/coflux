import asyncio
import inspect
import json
import random
import types
import typing as t
import urllib.parse
import websockets
import traceback

from . import server, execution, annotations, models


def _load_module(module: types.ModuleType) -> dict:
    attrs = (getattr(module, k) for k in dir(module))
    return dict(
        getattr(a, annotations.TARGET_KEY)
        for a in attrs
        if hasattr(a, annotations.TARGET_KEY)
    )


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


def _parse_placeholder(placeholder: list) -> tuple[int, None] | tuple[None, int]:
    match placeholder:
        case [execution_id, None]:
            return (execution_id, None)
        case [None, asset_id]:
            return (None, asset_id)
        case other:
            raise Exception(f"unhandle placeholder value: {other}")


def _parse_placeholders(placeholders: dict[int, list]) -> models.Placeholders:
    return {key: _parse_placeholder(value) for key, value in placeholders.items()}


def _parse_value(value: list) -> models.Value:
    match value:
        case ["raw", content, format, placeholders]:
            return ("raw", content.encode(), format, _parse_placeholders(placeholders))
        case ["blob", key, metadata, format, placeholders]:
            return ("blob", key, metadata, format, _parse_placeholders(placeholders))
    raise Exception(f"unexpected value: {value}")


class Agent:
    def __init__(
        self,
        project_id: str,
        environment_name: str,
        version: str | None,
        server_host: str,
        concurrency: int,
    ):
        self._project_id = project_id
        self._environment_name = environment_name
        self._version = version
        self._server_host = server_host
        self._concurrency = concurrency
        self._modules = {}
        self._connection = server.Connection(
            {"execute": self._handle_execute, "abort": self._handle_abort}
        )
        blob_url_format = f"http://{server_host}/blobs/{{key}}"
        self._execution_manager = execution.Manager(self._connection, blob_url_format)

    async def _handle_execute(self, *args) -> None:
        (execution_id, repository, target_name, arguments) = args
        print(f"Handling execute '{target_name}' ({execution_id})...")
        target = self._modules[repository][target_name][1]
        arguments = [_parse_value(a) for a in arguments]
        loop = asyncio.get_running_loop()
        self._execution_manager.execute(execution_id, target, arguments, loop)

    async def _handle_abort(self, *args) -> None:
        (execution_id,) = args
        print(f"Aborting execution ({execution_id})...")
        if not self._execution_manager.abort(execution_id):
            print(f"Ignored abort for unrecognised execution ({execution_id}).")

    def _url(self, scheme: str, path: str, **kwargs) -> str:
        params = {k: v for k, v in kwargs.items() if v is not None} if kwargs else None
        query_string = f"?{urllib.parse.urlencode(params)}" if params else ""
        return f"{scheme}://{self._server_host}/{path}{query_string}"

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
                session=self._connection.session_id,
                concurrency=self._concurrency,
            )
            try:
                async with websockets.connect(url) as websocket:
                    print("Connected.")
                    coros = [
                        asyncio.create_task(self._connection.run(websocket)),
                        asyncio.create_task(self._execution_manager.run()),
                    ]
                    done, pending = await asyncio.wait(
                        coros, return_when=asyncio.FIRST_COMPLETED
                    )
                    for task in pending:
                        task.cancel()
                    for task in done:
                        task.result()
            except websockets.ConnectionClosedError as e:
                reason = e.rcvd.reason if e.rcvd else None
                if reason == "project_not_found":
                    print("Project not found")
                    return
                elif reason == "environment_not_found":
                    print("Environment not found")
                    return
                elif reason == "session_invalid":
                    print("Session expired. Resetting and reconnecting...")
                    self._connection.reset()
                    self._execution_manager.abort_all()
                    for module_name, targets in self._modules.items():
                        await self._register_module(module_name, targets)
                else:
                    delay = 1 + 3 * random.random()  # TODO: exponential backoff
                    print(f"Disconnected (reconnecting in {delay:.1f} seconds).")
                    await asyncio.sleep(delay)
            except OSError:
                traceback.print_exc()
                delay = 1 + 3 * random.random()  # TODO: exponential backoff
                print(f"Can't connect (retrying in {delay:.1f} seconds).")
                await asyncio.sleep(delay)

    async def register_module(
        self, module: types.ModuleType, *, name: str | None = None
    ) -> None:
        module_name = name or module.__name__
        targets = _load_module(module)
        self._modules[module_name] = targets
        await self._register_module(module_name, targets)

    async def _register_module(self, module_name: str, targets: dict):
        await self._connection.notify(
            "register", (module_name, self._version, _build_manifest(targets))
        )
