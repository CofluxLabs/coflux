import asyncio
import click
import importlib
import importlib.util
import os
import types
import typing as t
import watchfiles
import httpx
from pathlib import Path

from . import Agent, config

T = t.TypeVar("T")


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


def _get_environ(name: str, parser: t.Callable[[str], T] = lambda x: x) -> T | None:
    value = os.environ.get(name)
    return parser(value) if value else None


@t.overload
def _get_option(
    argument: T | None,
    env_name: tuple[str, t.Callable[[str], T]],
    config_name: str | None,
) -> T | None:
    ...


@t.overload
def _get_option(
    argument: T | None,
    env_name: tuple[str, t.Callable[[str], T]],
    config_name: str | None = None,
    default: T = None,
) -> T:
    ...


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
            path = Path(module)
            if path.is_file():
                spec = importlib.util.spec_from_file_location(module, path)
                assert spec
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            else:
                module = importlib.import_module(module)
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
        agent = Agent(project, environment, version, host, concurrency)
        asyncio.run(_run(agent, list(modules)))
    except KeyboardInterrupt:
        pass


@click.group()
def cli():
    pass


@cli.command()
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
    default=lambda: config.load().get("environment") or "development",
    help="Environment name",
)
@click.option(
    "-h",
    "--host",
    default=lambda: config.load().get("host"),
    help="Host to connect to",
)
@click.option(
    "--concurrency",
    type=int,
    default=lambda: config.load().get("concurrency"),
    help="Limit on number of executions to process at once",
)
@click.option(
    "--repo",
    help="Name of the Python module to setup (if it doesn't already exist; e.g., 'my_package.repo')",
)
def init(
    project: str,
    environment: str,
    host: str | None,
    concurrency: int | None,
    repo: str | None,
):
    """
    Initialise a project by populating the configuration file.

    Will also setup files for a Python module for the repository, if needed.
    """

    # TODO: connect to server to check details?

    click.secho("Writing configuration...", fg="black")
    config.write(
        {
            "project": project,
            "environment": environment,
            "host": host,
            "concurrency": concurrency,
        }
    )
    click.secho(f"Configuration written to '{config.path}'.", fg="green")

    if repo:
        click.secho("Creating repo...", fg="black")
        package, *namespaces, module = repo.split(".")
        path = Path(package)
        path.mkdir(exist_ok=True)
        path.joinpath("__init__.py").touch(exist_ok=True)

        for namespace in namespaces:
            path = path.joinpath(namespace)
            path.mkdir(exist_ok=True)
            path.joinpath("__init__.py").touch(exist_ok=True)

        path = path.joinpath(f"{module}.py")
        if path.exists():
            click.secho(f"Module ({path}) already exists.", fg="yellow")
        else:
            path.touch()
            click.secho("Created package.", fg="green")


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
    with httpx.Client() as client:
        response = client.post(
            f"http://{host_}/api/schedule",
            json={
                "projectId": project_,
                "environment": environment_,
                "repository": repository,
                "target": target,
                "arguments": [["json", a] for a in argument],
            },
        )
        response.raise_for_status()
    # TODO: follow logs?
    # TODO: wait for result?


if __name__ == "__main__":
    cli()
