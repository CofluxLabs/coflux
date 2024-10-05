# 2. Starting the server

Use the CLI to **start the server** locally:

```bash
coflux server
```

:::note
The command is just a wrapper around `docker run`, so you'll need to have Docker installed and running.

Alternatively you can start the server with Docker directly:

```bash
docker run \
  --pull always \
  -p 7777:7777 \
  -v $(pwd):/data \
  ghcr.io/cofluxlabs/coflux
```
:::

**Open up the web UI** at http://localhost:7777.

## Setting up a project

Before we can connect an agent, we need to create a Coflux project and an environment.

In the web UI, **click 'New project...', enter a project name, and click 'Create'**.

Now that you have an empty project, you'll be prompted to add an environment. **Enter a name (or use the suggested one), and click 'Create'**.

Take note of the project ID and environment name in the instructions.

Next, we can define a workflow...
