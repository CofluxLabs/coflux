# 3. Starting agents

Repositories are hosted by _agents_ - each agent can have its own package dependencies, and be deployed within your infrastructure as needed - for example one agent could be deployed on an on-premise bare-metal server with a GPU, and another agent could be deployed as a Docker image on an auto-scaling cloud cluster.

Primarily, an agent is a process that's responsible for executing the code required by your workflow. Additionally, it will:

1. Register a _manifest_ describing the _targets_ (workflows/tasks/etc) that it supports, to the orchestrator.
2. Listen for commands from the orchestrator.
3. Invoke and monitor executions of operations (in forked sub-processes).
4. Report the status (including results, errors, etc.) of executions back to the orchestrator.

## Install

The agent, library and CLI can be installed from PyPI - e.g., with `pip`:

```bash
pip install coflux
```

**Run the command above**, or install the package as you prefer.

## Initialise

First, use the `configure` command to populate a configuration. This isn't necessary, but avoids having to specify configuration manually in the following commands. **Run the following command**:

```bash
coflux configure
```

You will be prompted to enter the host (`localhost:7777`), the project ID, and the environment name.

## Run

Now the agent can be started. **Run the following command**:

```bash
coflux agent.run hello.py
```

In the web UI you will be able to see your workflow.

Next, let's initiate a run...
