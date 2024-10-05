import asyncio
import click
import os
import types
import typing as t
import watchfiles
import httpx
import yaml
import subprocess
import sys
from pathlib import Path

from . import Agent, config, loader, decorators, models

T = t.TypeVar("T")


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


def _get_environ(name: str, parser: t.Callable[[str], T] = lambda x: x) -> T | None:
    value = os.environ.get(name)
    return parser(value) if value else None


def _api_request(method: str, host: str, action: str, **kwargs) -> t.Any:
    with httpx.Client() as client:
        response = client.request(method, f"http://{host}/api/{action}", **kwargs)
        # TODO: return errors
        response.raise_for_status()
        is_json = response.headers.get("Content-Type") == "application/json"
        return response.json() if is_json else None


def _load_pools_config(file: t.TextIO):
    # TODO: validate
    return yaml.safe_load(file)


@t.overload
def _get_option(
    argument: T | None,
    env_name: tuple[str, t.Callable[[str], T]],
    config_name: str | None,
) -> T | None: ...


@t.overload
def _get_option(
    argument: T | None,
    env_name: tuple[str, t.Callable[[str], T]],
    config_name: str | None = None,
    default: T = None,
) -> T: ...


def _get_option(
    argument: T | None,
    env_name: tuple[str, t.Callable[[str], T]],
    config_name: str | None = None,
    default: T = None,
) -> T | None:
    if argument is not None:
        return argument
    env_value = _get_environ(*env_name)
    if env_value is not None:
        return env_value
    if config_name is not None:
        config_value = config.load().get(config_name)
        if config_value is not None:
            return config_value
    return default


def _get_project(argument: str | None) -> str:
    project = _get_option(argument, ("COFLUX_PROJECT", str), "project")
    if not project:
        raise click.ClickException("No project ID specified.")
    return project


def _get_environment(argument: str | None) -> str:
    return _get_option(
        argument, ("COFLUX_ENVIRONMENT", str), "environment", "development"
    )


def _get_host(argument: str | None) -> str:
    return _get_option(argument, ("COFLUX_HOST", str), "host", "localhost:7777")


def _get_provides(argument: tuple[str] | None) -> dict[str, list[str]]:
    value = _get_option(argument, ("COFLUX_PROVIDES", lambda x: [x]))
    result: dict[str, list[str]] = {}
    if value:
        for part in (p for a in value for p in a.split(" ") if p):
            key, value = part.split(":", 1)
            result.setdefault(key, []).append(value)
        return result
    return {
        key: [
            (str(v).lower() if isinstance(v, bool) else v)
            for v in (value if isinstance(value, list) else [value])
        ]
        for key, value in config.load().get("provides", {}).items()
    }


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
    provides: dict[str, list[str]],
    host: str,
    concurrency: int,
    launch_id: str | None,
    register: bool,
) -> None:
    try:
        targets = _load_repositories(list(modules))
        if register:
            _register_manifests(project, environment, host, targets)

        with Agent(
            project, environment, provides, host, targets, concurrency, launch_id
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


@cli.command("configure")
@click.option(
    "-h",
    "--host",
    prompt=True,
    default=lambda: config.load().get("host") or "localhost:7777",
    help="Host to connect to",
)
@click.option(
    "-p",
    "--project",
    prompt=True,
    default=lambda: config.load().get("project"),
    help="Project ID",
)
@click.option(
    "environment",
    "-e",
    "--environment",
    prompt=True,
    default=lambda: config.load().get("environment") or "",
    help="Environment name",
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

    config.write(
        {
            "project": project,
            "host": host,
            "environment": environment or None,
        }
    )
    click.secho(f"Configuration written to '{config.path}'.", fg="green")


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
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
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
    project: str | None,
    host: str | None,
    base: str | None,
    pools_config: t.TextIO,
    name: str,
):
    """
    Creates an environment within the project.
    """
    project_ = _get_project(project)
    host_ = _get_host(host)

    base_id = None
    if base:
        environments = _api_request(
            "GET", host_, "get_environments", params={"project": project_}
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
        host_,
        "create_environment",
        json={
            "projectId": project_,
            "name": name,
            "baseId": base_id,
            "pools": pools,
        },
    )
    click.secho(f"Created environment '{name}'.", fg="green")


@env.command("update")
@click.option(
    "-p",
    "--project",
    help="Project ID",
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
)
@click.option(
    "-e",
    "--environment",
    help="The (current) name of the environment",
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
    project: str | None,
    host: str | None,
    environment: str | None,
    name: str | None,
    base: str | None,
    no_base: bool,
    pools_config: t.TextIO,
    no_pools: bool,
):
    """
    Creates an environment within the project.
    """
    project_ = _get_project(project)
    host_ = _get_host(host)
    environment_ = _get_environment(environment)

    environments = _api_request(
        "GET", host_, "get_environments", params={"project": project_}
    )
    environment_ids_by_name = {e["name"]: id for id, e in environments.items()}
    environment_id = environment_ids_by_name.get(environment_)
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
        "projectId": project_,
        "environmentId": environment_id,
    }
    if name is not None:
        payload["name"] = name

    if base is not None:
        payload["baseId"] = base_id
    elif no_base is True:
        payload["baseId"] = None

    if pools is not None:
        payload["pools"] = pools
    elif no_pools is True:
        payload["pools"] = None

    # TODO: handle response
    _api_request("POST", host_, "update_environment", json=payload)

    click.secho(f"Updated environment '{name or environment_}'.", fg="green")


@env.command("archive")
@click.option(
    "-p",
    "--project",
    help="Project ID",
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
)
def env_archive(
    project: str | None,
    environment: str | None,
    host: str | None,
):
    """
    Archive an environment on the server (but retain the configuration file locally).
    """
    project_ = _get_project(project)
    environment_ = _get_environment(environment)
    host_ = _get_host(host)

    environments = _api_request(
        "GET", host_, "get_environments", params={"project": project_}
    )
    environment_ids_by_name = {e["name"]: id for id, e in environments.items()}
    environment_id = environment_ids_by_name.get(environment_)
    if not environment_id:
        raise click.BadOptionUsage("environment", "Not recognised")

    _api_request(
        "POST",
        host_,
        "archive_environment",
        json={
            "projectId": project_,
            "environmentId": environment_id,
        },
    )
    click.secho(f"Archived environment '{environment_}'.", fg="green")


@cli.command("register")
@click.option(
    "-p",
    "--project",
    help="Project ID",
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
)
@click.argument("module_name", nargs=-1)
def register(
    project: str | None,
    environment: str | None,
    host: str | None,
    module_name: tuple[str],
) -> None:
    """
    Register repositories with the server.

    Paths to scripts can be passed instead of module names.

    Options will be loaded from the configuration file, unless overridden as arguments (or environment variables).
    """
    if not module_name:
        raise click.ClickException("No module(s) specified.")
    project_ = _get_project(project)
    environment_ = _get_environment(environment)
    host_ = _get_host(host)
    targets = _load_repositories(list(module_name))
    _register_manifests(project_, environment_, host_, targets)
    click.secho("Repository manifests registered.", fg="green")


@cli.command("agent")
@click.option(
    "-p",
    "--project",
    help="Project ID",
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
)
@click.option(
    "--provides",
    help="Features that this agent provides (to be matched with features that tasks require)",
    multiple=True,
)
@click.option(
    "--launch",
    help="The launch ID",
)
@click.option(
    "--concurrency",
    type=int,
    help="Limit on number of executions to process at once",
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
    project: str | None,
    environment: str | None,
    provides: tuple[str],
    host: str | None,
    launch: str | None,
    concurrency: int | None,
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
    project_ = _get_project(project)
    environment_ = _get_environment(environment)
    host_ = _get_host(host)
    provides_ = _get_provides(provides or None)
    launch_ = _get_option(launch, ("COFLUX_LAUNCH", str))
    concurrency_ = _get_option(
        concurrency,
        ("COFLUX_CONCURRENCY", int),
        "concurrency",
        min(32, (os.cpu_count() or 4) + 4),
    )
    args = (*module_name,)
    kwargs = {
        "project": project_,
        "environment": environment_,
        "provides": provides_,
        "host": host_,
        "concurrency": concurrency_,
        "launch_id": launch_,
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
)
@click.option(
    "-e",
    "--environment",
    help="Environment name",
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
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
    project_ = _get_project(project)
    environment_ = _get_environment(environment)
    host_ = _get_host(host)
    # TODO: support specifying options (or get config from manifest?)
    # TODO: handle response
    _api_request(
        "POST",
        host_,
        "submit_workflow",
        json={
            "projectId": project_,
            "environmentName": environment_,
            "repository": repository,
            "target": target,
            "arguments": [["json", a] for a in argument],
        },
    )
    click.secho("Workflow submitted.", fg="green")
    # TODO: follow logs?
    # TODO: wait for result?


if __name__ == "__main__":
    cli()
