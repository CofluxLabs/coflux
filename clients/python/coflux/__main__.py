import click

from . import Client


@click.command()
@click.option('-p', '--project', required=True)
@click.option('-m', '--module', required=True)
@click.option('-h', '--host', required=True)
def cli(project, module, host):
    Client(project, module, host).run()


cli()
