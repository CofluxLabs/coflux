import asyncio
import click
import os
import types
import typing as t
import watchfiles
import httpx
import yaml

from . import Agent, config, loader

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


async def _run(agent: Agent, modules: list[types.ModuleType | str]) -> None:
    for module in modules:
        if isinstance(module, str):
            module = loader.load_module(module)
        await agent.register_module(module)
    await agent.run()


def _init(
    *modules: types.ModuleType | str,
    project: str,
    environment: str,
    pool: str | None,
    host: str,
    concurrency: int,
) -> None:
    try:
        with Agent(project, environment, pool, host, concurrency) as agent:
            asyncio.run(_run(agent, list(modules)))
    except KeyboardInterrupt:
        pass


@click.group()
def cli():
    pass


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
    Populate the configuration file with default values.
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


@cli.command("environment.create")
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
def environment_create(
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


@cli.command("environment.update")
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
def environment_update(
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


@cli.command("environment.archive")
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
def environment_archive(
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


@cli.command("agent.run")
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
    "--pool",
    help="Pool name",
)
@click.option(
    "--concurrency",
    type=int,
    help="Limit on number of executions to process at once",
)
@click.option(
    "--reload",  # TODO: rename 'watch'?
    is_flag=True,
    default=False,
    help="Enable auto-reload when code changes",
)
@click.argument("module_name", nargs=-1)
def agent_run(
    project: str | None,
    environment: str | None,
    pool: str | None,
    host: str | None,
    concurrency: int | None,
    reload: bool,
    module_name: tuple[str],
) -> None:
    """
    Run the agent, loading the specified modules as repositories.

    Paths to scripts can be passed instead of module names.

    Options will be loaded from the configuration file, unless overridden as arguments (or environment variables).
    """
    if not module_name:
        raise click.ClickException("No module(s) specified.")
    project_ = _get_project(project)
    environment_ = _get_environment(environment)
    host_ = _get_host(host)
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
        "pool": pool,
        "host": host_,
        "concurrency": concurrency_,
    }
    if reload:
        watchfiles.run_process(
            ".",
            target=_init,
            args=args,
            kwargs=kwargs,
            callback=_callback,
        )
    else:
        _init(*args, **kwargs)


@cli.command("workflow.schedule")
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
def workflow_schedule(
    project: str,
    environment: str,
    host: str,
    repository: str,
    target: str,
    argument: tuple[str],
) -> None:
    """
    Schedule a workflow run.
    """
    project_ = _get_project(project)
    environment_ = _get_environment(environment)
    host_ = _get_host(host)
    # TODO: handle response
    _api_request(
        "POST",
        host_,
        "schedule",
        json={
            "projectId": project_,
            "environment": environment_,
            "repository": repository,
            "target": target,
            "arguments": [["json", a] for a in argument],
        },
    )
    # TODO: follow logs?
    # TODO: wait for result?


if __name__ == "__main__":
    cli()
