import asyncio
import random
import typing as t
import urllib.parse
import websockets
import traceback

from . import server, execution, models, config


def _parse_reference(reference: t.Any) -> models.Reference:
    match reference:
        case ["execution", execution_id]:
            return ("execution", execution_id)
        case ["asset", asset_id]:
            return ("asset", asset_id)
        case ["fragment", serialiser, blob_key, size, metadata]:
            return ("fragment", serialiser, blob_key, size, metadata)
        case other:
            raise Exception(f"unexpected reference: {other}")


def _parse_references(references: list[t.Any]) -> list[models.Reference]:
    return [_parse_reference(r) for r in references]


# TODO: remove duplication in execution.py
def _parse_value(value: list) -> models.Value:
    match value:
        case ["raw", content, references]:
            return ("raw", content, _parse_references(references))
        case ["blob", key, size, references]:
            return ("blob", key, size, _parse_references(references))
    raise Exception(f"unexpected value: {value}")


def _encode_tags(provides: dict[str, list[str]]) -> str:
    return ";".join(f"{k}:{v}" for k, vs in provides.items() for v in vs)


class Agent:
    def __init__(
        self,
        project_id: str,
        environment_name: str,
        server_host: str,
        provides: dict[str, list[str]],
        serialiser_configs: list[config.SerialiserConfig],
        blob_threshold: int,
        blob_store_configs: list[config.BlobStoreConfig],
        concurrency: int,
        launch_id: str | None,
        targets: dict[str, dict[str, tuple[models.Target, t.Callable]]],
    ):
        self._project_id = project_id
        self._environment_name = environment_name
        self._launch_id = launch_id
        self._server_host = server_host
        self._provides = provides
        self._concurrency = concurrency
        self._targets = targets
        self._connection = server.Connection(
            {"execute": self._handle_execute, "abort": self._handle_abort}
        )
        self._execution_manager = execution.Manager(
            self._connection, serialiser_configs, blob_threshold, blob_store_configs
        )

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self._execution_manager.abort_all()

    async def _handle_execute(self, *args) -> None:
        (execution_id, repository, target_name, arguments) = args
        print(f"Handling execute '{target_name}' ({execution_id})...")
        target = self._targets[repository][target_name][1].__name__
        arguments = [_parse_value(a) for a in arguments]
        loop = asyncio.get_running_loop()
        self._execution_manager.execute(
            execution_id, repository, target, arguments, self._server_host, loop
        )

    async def _handle_abort(self, *args) -> None:
        (execution_id,) = args
        print(f"Aborting execution ({execution_id})...")
        if not self._execution_manager.abort(execution_id):
            print(f"Ignored abort for unrecognised execution ({execution_id}).")

    def _url(self, scheme: str, path: str, params: dict[str, str]) -> str:
        params_ = {k: v for k, v in params.items() if v is not None} if params else None
        query_string = f"?{urllib.parse.urlencode(params_)}" if params_ else ""
        return f"{scheme}://{self._server_host}/{path}{query_string}"

    def _params(self):
        params = {
            "project": self._project_id,
            "environment": self._environment_name,
        }
        if self._connection.session_id:
            params["session"] = self._connection.session_id
        elif self._launch_id:
            params["launch"] = self._launch_id
        else:
            if self._provides:
                params["provides"] = _encode_tags(self._provides)
            if self._concurrency:
                params["concurrency"] = str(self._concurrency)
        return params

    async def run(self) -> None:
        while True:
            print(
                f"Connecting ({self._server_host}, {self._project_id}, {self._environment_name})..."
            )
            url = self._url("ws", "agent", self._params())
            try:
                async with websockets.connect(url) as websocket:
                    print("Connected.")
                    targets: dict[str, dict[models.TargetType, list[str]]] = {}
                    for repository, repository_targets in self._targets.items():
                        for target_name, (target, _) in repository_targets.items():
                            targets.setdefault(repository, {}).setdefault(
                                target.type, []
                            ).append(target_name)
                    coros = [
                        asyncio.create_task(self._connection.run(websocket)),
                        asyncio.create_task(self._execution_manager.run(targets)),
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
                else:
                    delay = 1 + 3 * random.random()  # TODO: exponential backoff
                    print(f"Disconnected (reconnecting in {delay:.1f} seconds).")
                    await asyncio.sleep(delay)
            except OSError:
                traceback.print_exc()
                delay = 1 + 3 * random.random()  # TODO: exponential backoff
                print(f"Can't connect (retrying in {delay:.1f} seconds).")
                await asyncio.sleep(delay)
