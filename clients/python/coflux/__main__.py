import asyncio
import click
import types
import typing as t
import watchfiles
import httpx
import subprocess
import sys
import time
import functools
import tomlkit
from pathlib import Path

from . import Agent, config, loader, decorators, models

T = t.TypeVar("T")


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


def _api_request(method: str, host: str, action: str, **kwargs) -> t.Any:
    with httpx.Client() as client:
        response = client.request(method, f"http://{host}/api/{action}", **kwargs)
        # TODO: return errors
        response.raise_for_status()
        is_json = response.headers.get("Content-Type") == "application/json"
        return response.json() if is_json else None


def _encode_provides(
    provides: dict[str, list[str] | str | bool] | None
) -> tuple[str, ...] | None:
    if not provides:
        return None
    return tuple(
        f"{k}:{str(v).lower() if isinstance(v, bool) else v}"
        for k, vs in provides.items()
        for v in (vs if isinstance(vs, list) else [vs])
    )


def _parse_provides(argument: tuple[str] | None) -> dict[str, list[str]]:
    if not argument:
        return {}
    result: dict[str, list[str]] = {}
    for part in (p for a in argument for p in a.split(" ") if p):
        key, value = part.split(":", 1)
        result.setdefault(key, []).append(value)
    return result


def _load_repository(
    module: types.ModuleType,
) -> dict[str, tuple[models.Target, t.Callable]]:
    attrs = (getattr(module, k) for k in dir(module))
    return {
        a.name: (a.definition, a.fn)
        for a in attrs
        if isinstance(a, decorators.Target) and not a.definition.is_stub
    }


def _load_repositories(
    modules: list[types.ModuleType | str],
) -> dict[str, dict[str, tuple[models.Target, t.Callable]]]:
    targets = {}
    for module in list(modules):
        if isinstance(module, str):
            module = loader.load_module(module)
        targets[module.__name__] = _load_repository(module)
    return targets


def _register_manifests(
    project_id: str,
    environment_name: str,
    host: str,
    targets: dict[str, dict[str, tuple[models.Target, t.Callable]]],
) -> None:
    manifests = {
        repository: {
            "workflows": {
                workflow_name: {
                    "parameters": [
                        {
                            "name": p.name,
                            "annotation": p.annotation,
                            "default": p.default,
                        }
                        for p in definition.parameters
                    ],
                    "waitFor": list(definition.wait_for),
                    "cache": (
                        definition.cache
                        and {
                            "params": definition.cache.params,
                            "maxAge": definition.cache.max_age,
                            "namespace": definition.cache.namespace,
                            "version": definition.cache.version,
                        }
                    ),
                    "defer": (
                        definition.defer
                        and {
                            "params": definition.defer.params,
                        }
                    ),
                    "delay": definition.delay,
                    "retries": (
                        definition.retries
                        and {
                            "limit": definition.retries.limit,
                            "delayMin": definition.retries.delay_min,
                            "delayMax": definition.retries.delay_max,
                        }
                    ),
                    "requires": definition.requires,
                }
                for workflow_name, (definition, _) in target.items()
                if definition.type == "workflow"
            },
            "sensors": {
                sensor_name: {
                    "parameters": [
                        {
                            "name": p.name,
                            "annotation": p.annotation,
                            "default": p.default,
                        }
                        for p in definition.parameters
                    ],
                    "requires": definition.requires,
                }
                for sensor_name, (definition, _) in target.items()
                if definition.type == "sensor"
            },
        }
        for repository, target in targets.items()
    }
    # TODO: handle response?
    _api_request(
        "POST",
        host,
        "register_manifests",
        json={
            "projectId": project_id,
            "environmentName": environment_name,
            "manifests": manifests,
        },
    )


def _init(
    *modules: types.ModuleType | str,
    project: str,
    environment: str,
    host: str,
    provides: dict[str, list[str]],
    serialiser_configs: list[config.SerialiserConfig],
    blob_threshold: int,
    blob_store_configs: list[config.BlobStoreConfig],
    concurrency: int,
    launch_id: str | None,
    register: bool,
) -> None:
    try:
        targets = _load_repositories(list(modules))
        if register:
            _register_manifests(project, environment, host, targets)

        with Agent(
            project,
            environment,
            host,
            provides,
            serialiser_configs,
            blob_threshold,
            blob_store_configs,
            concurrency,
            launch_id,
            targets,
        ) as agent:
            asyncio.run(agent.run())
    except KeyboardInterrupt:
        pass


@click.group()
def cli():
    pass


@cli.command("server")
@click.option(
    "-p",
    "--port",
    type=int,
    default=7777,
    help="Port to run server on",
)
@click.option(
    "-d",
    "--data-dir",
    type=click.Path(file_okay=False, path_type=Path, resolve_path=True),
    default="./data/",
    help="The directory to store data",
)
@click.option(
    "--image",
    default="ghcr.io/cofluxlabs/coflux",
    help="The Docker image to run",
)
def server(port: int, data_dir: Path, image: str):
    """
    Start a local server.

    This is just a wrapper around Docker (which must be installed and running), useful for running the server in a development environment.
    """
    command = [
        "docker",
        "run",
        "--pull",
        ("missing" if image.startswith("sha256:") else "always"),
        "--publish",
        f"{port}:7777",
        "--volume",
        f"{data_dir}:/data",
        image,
    ]
    process = subprocess.run(command)
    sys.exit(process.returncode)


def _config_path():
    return Path.cwd().joinpath("coflux.toml")


def _read_config(path: Path) -> tomlkit.TOMLDocument:
    if path.exists():
        with path.open("r") as f:
            return tomlkit.load(f)
    else:
        # TODO: add instructions?
        return tomlkit.document()


def _write_config(path: Path, data: tomlkit.TOMLDocument):
    with path.open("w") as f:
        tomlkit.dump(data, f)


@functools.cache
def _load_config() -> config.Config:
    path = _config_path()
    return config.Config.model_validate(_read_config(path).unwrap())


def _load_pools_config(file: t.TextIO) -> config.PoolsConfig:
    return config.PoolsConfig.model_validate(tomlkit.load(file).unwrap())


@cli.command("configure")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    default=_load_config().project,
    show_default=True,
    prompt=True,
)
@click.option(
    "environment",
    "-e",
    "--environment",
    help="Environment name",
    default=_load_config().environment,
    show_default=True,
    prompt=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    default=_load_config().server.host,
    show_default=True,
    prompt=True,
)
def configure(
    host: str | None,
    project: str | None,
    environment: str | None,
):
    """
    Populate/update the configuration file.
    """
    # TODO: connect to server to check details?
    click.secho("Writing configuration...", fg="black")

    path = _config_path()
    data = _read_config(path)
    data["project"] = project
    data["environment"] = environment
    data.setdefault("server", {})["host"] = host
    _write_config(path, data)

    click.secho(
        f"Configuration written to '{path.relative_to(Path.cwd())}'.", fg="green"
    )


@cli.group()
def env():
    """
    Manage environments.
    """
    pass


@env.command("create")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    envvar="COFLUX_PROJECT",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    envvar="COFLUX_HOST",
    default=_load_config().server.host,
    show_default=True,
    required=True,
)
@click.option(
    "--base",
    help="The base environment to inherit from",
)
@click.option(
    "--pools-config",
    help="Path to pools configuration file",
    type=click.File(),
)
@click.argument("name")
def env_create(
    project: str,
    host: str,
    base: str | None,
    pools_config: t.TextIO,
    name: str,
):
    """
    Creates an environment within the project.
    """
    base_id = None
    if base:
        environments = _api_request(
            "GET", host, "get_environments", params={"project": project}
        )
        environment_ids_by_name = {e["name"]: id for id, e in environments.items()}
        base_id = environment_ids_by_name.get(base)
        if not base_id:
            click.BadOptionUsage("base", "Not recognised")

    pools = None
    if pools_config:
        pools = _load_pools_config(pools_config)

    # TODO: handle response
    _api_request(
        "POST",
        host,
        "create_environment",
        json={
            "projectId": project,
            "name": name,
            "baseId": base_id,
            "pools": pools.model_dump() if pools else None,
        },
    )
    click.secho(f"Created environment '{name}'.", fg="green")


@env.command("update")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    envvar="COFLUX_PROJECT",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.option(
    "-e",
    "--environment",
    help="The (current) name of the environment",
    envvar="COFLUX_ENVIRONMENT",
    default=_load_config().environment,
    show_default=True,
    required=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    envvar="COFLUX_HOST",
    default=_load_config().server.host,
    show_default=True,
    required=True,
)
@click.option(
    "--name",
    help="The new name of the environment",
)
@click.option(
    "--base",
    help="The new base environment to inherit from",
)
@click.option(
    "--no-base",
    is_flag=True,
    help="Unset the base environment",
)
@click.option(
    "--pools-config",
    help="Path to pools configuration file",
    type=click.File(),
)
@click.option(
    "--no-pools",
    is_flag=True,
    help="Clear all pools from the environment",
)
def env_update(
    project: str,
    environment: str,
    host: str,
    name: str | None,
    base: str | None,
    no_base: bool,
    pools_config: t.TextIO,
    no_pools: bool,
):
    """
    Creates an environment within the project.
    """
    environments = _api_request(
        "GET", host, "get_environments", params={"project": project}
    )
    environment_ids_by_name = {e["name"]: id for id, e in environments.items()}
    environment_id = environment_ids_by_name.get(environment)
    if not environment_id:
        raise click.BadOptionUsage("environment", "Not recognised")

    base_id = None
    if base:
        base_id = environment_ids_by_name.get(base)
        if not base_id:
            raise click.BadOptionUsage("base", "Not recognised")

    pools = None
    if pools_config:
        pools = _load_pools_config(pools_config)

    payload = {
        "projectId": project,
        "environmentId": environment_id,
    }
    if name is not None:
        payload["name"] = name

    if base is not None:
        payload["baseId"] = base_id
    elif no_base is True:
        payload["baseId"] = None

    if pools is not None:
        payload["pools"] = pools.model_dump()
    elif no_pools is True:
        payload["pools"] = None

    # TODO: handle response
    _api_request("POST", host, "update_environment", json=payload)

    click.secho(f"Updated environment '{name or environment}'.", fg="green")


@env.command("archive")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    envvar="COFLUX_PROJECT",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
    envvar="COFLUX_ENVIRONMENT",
    default=_load_config().environment,
    show_default=True,
    required=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    envvar="COFLUX_HOST",
    default=_load_config().server.host,
    show_default=True,
    required=True,
)
def env_archive(
    project: str,
    environment: str,
    host: str,
):
    """
    Archive an environment on the server (but retain the configuration file locally).
    """
    environments = _api_request(
        "GET", host, "get_environments", params={"project": project}
    )
    environment_ids_by_name = {e["name"]: id for id, e in environments.items()}
    environment_id = environment_ids_by_name.get(environment)
    if not environment_id:
        raise click.BadOptionUsage("environment", "Not recognised")

    _api_request(
        "POST",
        host,
        "archive_environment",
        json={
            "projectId": project,
            "environmentId": environment_id,
        },
    )
    click.secho(f"Archived environment '{environment}'.", fg="green")


@cli.command("register")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    envvar="COFLUX_PROJECT",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
    envvar="COFLUX_ENVIRONMENT",
    default=_load_config().environment,
    show_default=True,
    required=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    envvar="COFLUX_HOST",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.argument("module_name", nargs=-1)
def register(
    project: str,
    environment: str,
    host: str,
    module_name: tuple[str],
) -> None:
    """
    Register repositories with the server.

    Paths to scripts can be passed instead of module names.

    Options will be loaded from the configuration file, unless overridden as arguments (or environment variables).
    """
    if not module_name:
        raise click.ClickException("No module(s) specified.")
    targets = _load_repositories(list(module_name))
    _register_manifests(project, environment, host, targets)
    click.secho("Repository manifests registered.", fg="green")


@cli.command("agent")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    envvar="COFLUX_PROJECT",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
    envvar="COFLUX_ENVIRONMENT",
    default=_load_config().environment,
    show_default=True,
    required=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    envvar="COFLUX_HOST",
    default=_load_config().server.host,
    show_default=True,
    required=True,
)
@click.option(
    "--provides",
    help="Features that this agent provides (to be matched with features that tasks require)",
    multiple=True,
    envvar="COFLUX_PROVIDES",
    default=_encode_provides(_load_config().provides),
    show_default=True,
)
@click.option(
    "--launch",
    help="The launch ID",
    envvar="COFLUX_LAUNCH",
)
@click.option(
    "--concurrency",
    type=int,
    help="Limit on number of executions to process at once",
    default=_load_config().concurrency,
    show_default=True,
)
@click.option(
    "--watch",
    is_flag=True,
    default=False,
    help="Enable auto-reload when code changes",
)
@click.option(
    "--register",
    is_flag=True,
    default=False,
    help="Automatically register repositories",
)
@click.option(
    "--dev",
    is_flag=True,
    default=False,
    help="Enable development mode (implies `--watch` and `--register`)",
)
@click.argument("module_name", nargs=-1)
def agent(
    project: str,
    environment: str,
    host: str,
    provides: tuple[str] | None,
    launch: str | None,
    concurrency: int,
    watch: bool,
    register: bool,
    dev: bool,
    module_name: tuple[str],
) -> None:
    """
    Start an agent.

    Loads the specified modules as repositories. Paths to scripts can be passed instead of module names.

    Options will be loaded from the configuration file, unless overridden as arguments (or environment variables).
    """
    if not module_name:
        raise click.ClickException("No module(s) specified.")
    provides_ = _parse_provides(provides)
    config = _load_config()
    args = (*module_name,)
    kwargs = {
        "project": project,
        "environment": environment,
        "host": host,
        "provides": provides_,
        "serialiser_configs": config and config.serialisers,
        "blob_threshold": config and config.blobs and config.blobs.threshold,
        "blob_store_configs": config and config.blobs and config.blobs.stores,
        "concurrency": concurrency,
        "launch_id": launch,
        "register": register or dev,
    }
    if watch or dev:
        filter = watchfiles.PythonFilter()
        watchfiles.run_process(
            ".",
            target=_init,
            args=args,
            kwargs=kwargs,
            callback=_callback,
            watch_filter=filter,
        )
    else:
        _init(*args, **kwargs)


@cli.command("submit")
@click.option(
    "-p",
    "--project",
    help="Project ID",
    default=_load_config().project,
    show_default=True,
    required=True,
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
    default=_load_config().environment,
    show_default=True,
    required=True,
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
    default=_load_config().server.host,
    show_default=True,
    required=True,
)
@click.argument("repository")
@click.argument("target")
@click.argument("argument", nargs=-1)
def submit(
    project: str,
    environment: str,
    host: str,
    repository: str,
    target: str,
    argument: tuple[str],
) -> None:
    """
    Submit a workflow to be run.
    """
    # TODO: support overriding options?
    workflow = _api_request(
        "GET",
        host,
        "get_workflow",
        params={
            "project": project,
            "environment": environment,
            "repository": repository,
            "target": target,
        },
    )
    execute_after = (
        int((time.time() + workflow["delay"]) * 1000) if workflow["delay"] else None
    )
    # TODO: handle response
    _api_request(
        "POST",
        host,
        "submit_workflow",
        json={
            "projectId": project,
            "environmentName": environment,
            "repository": repository,
            "target": target,
            "arguments": [["json", a] for a in argument],
            "waitFor": workflow["waitFor"],
            "cache": workflow["cache"],
            "defer": workflow["defer"],
            "executeAfter": execute_after,
            "retries": workflow["retries"],
            "requires": workflow["requires"],
        },
    )
    click.secho("Workflow submitted.", fg="green")
    # TODO: follow logs?
    # TODO: wait for result?


if __name__ == "__main__":
    cli()
