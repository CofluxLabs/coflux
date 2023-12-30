import asyncio
import importlib
import inspect
import json
import os
import random
import types
import typing as t
import urllib
import websockets

from . import server, execution, config, annotations


T = t.TypeVar("T")


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


class Agent:
    def __init__(
        self,
        project_id: str,
        environment_name: str,
        version: str,
        server_host: str,
    ):
        self._project_id = project_id
        self._environment_name = environment_name
        self._version = version
        self._server_host = server_host
        self._modules = {}
        self._connection = server.Connection(
            {"execute": self._handle_execute, "abort": self._handle_abort}
        )
        self._execution_manager = execution.Manager(self._connection, server_host)

    async def _handle_execute(
        self,
        execution_id: str,
        repository: str,
        target_name: str,
        arguments: list[list[t.Any]],
    ) -> None:
        print(f"Handling execute '{target_name}' ({execution_id})...")
        target = self._modules[repository][target_name][1]
        loop = asyncio.get_running_loop()
        self._execution_manager.execute(execution_id, target, arguments, loop)

    async def _handle_abort(self, execution_id: str) -> None:
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
            )
            try:
                async with websockets.connect(url) as websocket:
                    print("Connected.")
                    coros = [
                        self._connection.run(websocket),
                        self._execution_manager.run(),
                    ]
                    _, pending = await asyncio.wait(
                        coros, return_when=asyncio.FIRST_COMPLETED
                    )
                    for task in pending:
                        task.cancel()
                    if websocket.close_code == 4001:
                        print("Session expired. Resetting...")
                        self._connection.reset()
                        for module_name, targets in self._modules.items():
                            await self._register_module(module_name, targets)
            except OSError:
                pass
            delay = 1 + 3 * random.random()  # TODO: exponential backoff
            print(f"Disconnected (reconnecting in {delay:.1f} seconds).")
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


async def _run(agent: Agent, modules: list[types.ModuleType | str]) -> None:
    for module in modules:
        if isinstance(module, str):
            module = importlib.import_module(module)
        await agent.register_module(module)
    await agent.run()


def _get_option(
    argument: T | None,
    env_name: str,
    config_name: str | None = None,
    default: T = None,
) -> T:
    return (
        argument
        or os.environ.get(env_name)
        or (config_name and config.load().get(config_name))
        or default
    )


def init(
    *modules: types.ModuleType | str,
    project: str | None = None,
    environment: str | None = None,
    version: str | None = None,
    host: str | None = None,
) -> None:
    if not modules:
        raise Exception("No module(s) specified.")
    project = _get_option(project, "COFLUX_PROJECT", "project")
    if not project:
        raise Exception("No project ID specified.")
    environment = _get_option(
        environment, "COFLUX_ENVIRONMENT", "environment", "development"
    )
    version = _get_option(version, "COFLUX_VERSION")
    host = _get_option(host, "COFLUX_HOST", "host", "localhost:7777")
    try:
        agent = Agent(project, environment, version, host)
        asyncio.run(_run(agent, modules))
    except KeyboardInterrupt:
        pass
