import asyncio
import click
import importlib
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


def _get_environ(name: str, parser: t.Callable[[str], T]) -> T | None:
    value = os.environ.get(name)
    return parser(value) if value else None


def _get_option(
    argument: T | None,
    env_name: str,
    config_name: str | None = None,
    default: T | None = None,
    parser: t.Callable[[str], T] = lambda x: x,
) -> T | None:
    return (
        argument
        or _get_environ(env_name, parser)
        or (config_name and config.load().get(config_name))
        or default
    )


async def _run(agent: Agent, modules: list[types.ModuleType | str]) -> None:
    for module in modules:
        if isinstance(module, str):
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
    help="Name of the Python repo to setup (if it doesn't already exist; e.g., 'my_package.repo')",
)
def init(
    project: str,
    environment: str,
    host: str | None,
    concurrency: int | None,
    repo: str | None,
):
    """
    Initialise a project.
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
    Run the agent.
    """
    if not module_name:
        # TODO: click error
        raise Exception("No module(s) specified.")
    project_ = _get_option(project, "COFLUX_PROJECT", "project")
    if not project_:
        # TODO: click error
        raise Exception("No project ID specified.")
    environment_ = _get_option(
        environment, "COFLUX_ENVIRONMENT", "environment", "development"
    )
    version_ = _get_option(version, "COFLUX_VERSION")
    host_ = _get_option(host, "COFLUX_HOST", "host", "localhost:7777")
    concurrency_ = _get_option(
        concurrency,
        "COFLUX_CONCURRENCY",
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


@cli.command("task.run")
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
def task_run(
    project: str,
    environment: str,
    host: str,
    repository: str,
    target: str,
    argument: tuple[str],
) -> None:
    """
    Schedule a task run.
    """
    project_ = _get_option(project, "COFLUX_PROJECT", "project")
    if not project_:
        # TODO: click error
        raise Exception("No project ID specified.")
    environment_ = _get_option(
        environment, "COFLUX_ENVIRONMENT", "environment", "development"
    )
    host_ = _get_option(host, "COFLUX_HOST", "host", "localhost:7777")
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
