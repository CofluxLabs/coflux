import asyncio
import click
import os
import types
import typing as t
import watchfiles
import httpx
import yaml
import re
from pathlib import Path

from . import Agent, config, loader

T = t.TypeVar("T")


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


def _get_environ(name: str, parser: t.Callable[[str], T] = lambda x: x) -> T | None:
    value = os.environ.get(name)
    return parser(value) if value else None


def _api_request(host: str, action: str, json: t.Any) -> t.Any:
    with httpx.Client() as client:
        response = client.post(f"http://{host}/api/{action}", json=json)
        response.raise_for_status()
        return response.json()


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
    version: str | None,
    host: str,
    concurrency: int,
) -> None:
    try:
        with Agent(project, environment, version, host, concurrency) as agent:
            asyncio.run(_run(agent, list(modules)))
    except KeyboardInterrupt:
        pass


@click.group()
def cli():
    pass


@cli.command("environment.define")
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
@click.argument("environment_name")
def environment_define(
    project: str | None,
    host: str | None,
    environment_name: str,
):
    """
    Register an environment definition with the server.

    A configuration file for the environment will be created, at `environments/my_environment.yaml`, if it doesn't already exist.
    """
    project_ = _get_project(project)
    host_ = _get_host(host)
    if not re.match(r"^[A-Za-z0-9_-]+(\/[A-Za-z0-9_-]+)*$", environment_name):
        raise click.BadArgumentUsage(
            "Environment name must consist of alphanumeric characters, underscores or hyphens, and may contain forward slashes."
        )

    # TODO: support custom environments directory
    environments_dir = Path("environments")
    environment_file = environments_dir.joinpath(f"{environment_name}.yaml")
    if not environment_file.exists():
        click.secho(
            f"Environment file doesn't exist. Creating '{environment_file}'...",
            fg="blue",
        )
        environment_file.parent.mkdir(parents=True, exist_ok=True)
        environment_file.touch()

    with environment_file.open() as file:
        content = yaml.safe_load(file) or {}

    # TODO: handle response
    _api_request(
        host_,
        "define_environment",
        {
            "projectId": project_,
            "name": environment_name,
            "cacheFrom": content.get("cache_from"),
        },
    )
    click.secho("Registered environment.", fg="green")


@cli.command("agent.run")
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
    "-v",
    "--version",
    help="Version identifier to report to the server",
)
@click.option(
    "-h",
    "--host",
    help="Host to connect to",
)
@click.option(
    "--concurrency",
    type=int,
    help="Limit on number of executions to process at once",
)
@click.option(
    "--reload",
    is_flag=True,
    default=False,
    help="Enable auto-reload when code changes",
)
@click.argument("module_name", nargs=-1)
def agent_run(
    project: str | None,
    environment: str | None,
    version: str | None,
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
    version_ = _get_option(version, ("COFLUX_VERSION", str))
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
        "version": version_,
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


@cli.command("workflow.run")
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
def workflow_run(
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
        host_,
        "schedule",
        {
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
