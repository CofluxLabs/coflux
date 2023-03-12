import click
import watchfiles
import importlib

from . import client


def _callback(_changes: set[tuple[watchfiles.Change, str]]) -> None:
    print("Change detected. Reloading...")


@click.command()
@click.option("-p", "--project", required=True, help="Project ID")
@click.option(
    "environment_name", "-e", "--environment", required=True, help="Environment name"
)
@click.option(
    "module_name", "-m", "--module", required=True, help="Python module to use"
)
@click.option(
    "-v", "--version", required=True, help="Version identifier to report to the server"
)
@click.option("-h", "--host", required=True, help="Host to connect to")
@click.option(
    "--concurrency", type=int, help="Limit on number of executions to process at once"
)
@click.option(
    "--reload", is_flag=True, default=False, help="Enable auto-reload when code changes"
)
def cli(
    project: str,
    environment_name: str,
    module_name: str,
    version: str,
    host: str,
    concurrency: int,
    reload: bool,
) -> None:
    module = importlib.import_module(module_name)
    args = (project, environment_name, module, version, host, concurrency)
    if reload:
        watchfiles.run_process(".", target=client.run, args=args, callback=_callback)
    else:
        client.run(*args)


cli()
