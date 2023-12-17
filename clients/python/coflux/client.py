import asyncio
import os
import types
import typing as t
import importlib
import random

from . import session, annotations, config

T = t.TypeVar("T")


def _load_module(module: types.ModuleType) -> dict:
    attrs = (getattr(module, k) for k in dir(module))
    return dict(a._coflux_target for a in attrs if hasattr(a, annotations.TARGET_KEY))


class Client:
    def __init__(
        self,
        project_id: str,
        environment_name: str,
        version: str,
        server_host: str,
        concurrency: int | None = None,
    ):
        self._project_id = project_id
        self._environment_name = environment_name
        self._version = version
        self._server_host = server_host
        self._concurrency = concurrency or min(32, os.cpu_count() + 4)
        self._modules = {}
        self._session = None

    async def run(self) -> None:
        while True:
            print("Initialising session...")
            self._session = session.Session(
                self._project_id,
                self._environment_name,
                self._version,
                self._server_host,
                self._concurrency,
            )
            for module_name, targets in self._modules.items():
                await self._session.register_module(module_name, targets)
            try:
                await self._session.run()
                break
            except session.SessionExpired:
                delay = 1 + 3 * random.random()  # TODO: exponential backoff
                print(f"Session expired (re-initialising in {delay:.1f} seconds).")
                await asyncio.sleep(delay)
            self._session = None

    async def register_module(
        self, module: types.ModuleType, *, name: str | None = None
    ) -> None:
        module_name = name or module.__name__
        targets = _load_module(module)
        self._modules[module_name] = targets
        if self._session:
            await self._session.register_module(module_name, targets)


async def _run(client: Client, modules: list[types.ModuleType | str]) -> None:
    for module in modules:
        if isinstance(module, str):
            module = importlib.import_module(module)
        await client.register_module(module)
    await client.run()


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
    concurrency: int | None = None,
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
    concurrency = _get_option(concurrency, "COFLUX_CONCURRENCY", "concurrency")
    try:
        client = Client(project, environment, version, host, concurrency)
        asyncio.run(_run(client, modules))
    except KeyboardInterrupt:
        pass
