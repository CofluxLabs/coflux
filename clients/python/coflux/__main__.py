import click
import asyncio
import watchgod

from . import Client


def _callback(changes):
    print("Change detected. Restarting...")


def _run(project, environment, module, version, host, concurrency):
    try:
        client = Client(project, environment, module, version, host, concurrency)
        asyncio.run(client.run())
    except KeyboardInterrupt:
        pass


@click.command()
@click.option('-p', '--project', required=True, help="Project ID")
@click.option('-e', '--environment', required=True, help="Environment name")
@click.option('-m', '--module', required=True, help="Python module to use")
@click.option('-v', '--version', required=True, help="Version identifier to report to the server")
@click.option('-h', '--host', required=True, help="Host to connect to")
@click.option('--concurrency', type=int, help="Limit on number of executions to process at once")
@click.option('--reload', is_flag=True, default=False, help="Enable auto-reload when code changes")
def cli(project, environment, module, version, host, concurrency, reload):
    args = (project, environment, module, version, host, concurrency)
    if reload:
        watchgod.run_process('.', _run, args=args, callback=_callback)
    else:
        _run(*args)


cli()
