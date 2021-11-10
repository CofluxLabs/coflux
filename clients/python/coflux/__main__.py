import click
import asyncio

from . import Client


@click.command()
@click.option('-p', '--project', required=True)
@click.option('-m', '--module', required=True)
@click.option('-v', '--version', required=True)
@click.option('-h', '--host', required=True)
def cli(project, module, version, host):
    client = Client(project, module, version, host)
    asyncio.run(client.run())


cli()
