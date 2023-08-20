import click
import watchfiles

from . import client


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


@click.command()
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
def cli(
    project: str,
    environment: str,
    version: str,
    host: str,
    concurrency: int,
    reload: bool,
    module_name: tuple[str],
) -> None:
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
