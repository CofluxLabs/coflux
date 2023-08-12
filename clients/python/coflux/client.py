import asyncio
import os
import types
import typing as t
import importlib
import random

from . import session, annotations


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

    async def schedule_step(
        self,
        repository: str,
        target: str,
        arguments: t.Tuple[t.Any, ...],
        execution_id: str,
        cache_key: str | None = None,
    ) -> str:
        return self._session.schedule_step(
            execution_id, repository, target, arguments, cache_key
        )

    async def schedule_task(
        self,
        repository: str,
        target: str,
        arguments: t.Tuple[t.Any, ...],
        execution_id: str,
    ) -> str:
        return self._session.schedule_task(execution_id, repository, target, arguments)

    async def log_message(
        self, execution_id: str, level: session.LogLevel, message: str
    ) -> None:
        await self._session.log_message(execution_id, level, message)

    async def get_result(self, execution_id: str, from_execution_id: str) -> t.Any:
        return self._session.get_result(execution_id, from_execution_id)


async def _run(client: Client, modules: list[types.ModuleType | str]) -> None:
    for module in modules:
        if isinstance(module, str):
            module = importlib.import_module(module)
        await client.register_module(module)
    await client.run()


def init(
    modules: list[types.ModuleType | str],
    *,
    project: str | None = None,
    environment: str | None = None,
    version: str | None = None,
    host: str | None = None,
    concurrency: int | None = None,
) -> None:
    project = project or os.environ.get("COFLUX_PROJECT")
    environment = environment or os.environ.get("COFLUX_ENVIRONMENT") or "development"
    version = version or os.environ.get("COFLUX_VERSION")
    host = host or os.environ.get("COFLUX_HOST") or "localhost:7070"
    concurrency = concurrency or os.environ.get("COFLUX_CONCURRENCY")
    try:
        client = Client(project, environment, version, host, concurrency)
        asyncio.run(_run(client, modules))
    except KeyboardInterrupt:
        pass
