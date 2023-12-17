import click
import watchfiles
from pathlib import Path

from . import client, config


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


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
            click.secho(f"Created package.", fg="green")


@cli.command("agent.run")
@click.option(
    "-p",
    "--project",
    help="Project ID",
)
@click.option(
    "environment",
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
def run(
    project: str,
    environment: str,
    version: str,
    host: str,
    concurrency: int,
    reload: bool,
    module_name: tuple[str],
) -> None:
    """
    Run the agent.
    """
    args = (*module_name,)
    kwargs = {
        "project": project,
        "environment": environment,
        "version": version,
        "host": host,
        "concurrency": concurrency,
    }
    if reload:
        watchfiles.run_process(
            ".",
            target=client.init,
            args=args,
            kwargs=kwargs,
            callback=_callback,
        )
    else:
        client.init(*args, **kwargs)


cli()
