# Starting agents

Workflows are hosted by _agents_ - each agent can have its own dependencies, and be deployed within your infrastructure as you like - for example a single agent may be deployed on an on-premise bare-metal server with a GPU, and another agent could be deployed as a Docker image on an auto-scaling cloud cluster.

Primarily, an agent is a process that's able to execute the code required by your workflow. Additionally, it will:

1. Report a _manifest_ describing the _targets_ (workflows/tasks/etc) that it supports, to the orchestrator.
2. Listen for commands from the orchestrator.
3. Invoke and monitor executions of operations (in forked sub-processes).
4. Report status/results/errors back to the orchestrator.

## Installing

These are taken care of by the Coflux Python library, which can be installed from PyPI - e.g., with `pip`:

```bash
pip install coflux
```

This will also install the `coflux` CLI, which we can use to run our agent.

## Configuring

First, we can use the `init` command to populate a configuration file (which will avoid needing to specify options when we run the agent):

```bash
coflux init
```

Enter the ID of the project that you created.

## Running

Now we can run the agent:

```bash
coflux agent.run hello.py
```

In the web UI you will now be able to see your workflow.

Next, let's initiate a run...