# Initiating runs

We've defined our workflow, started the Coflux server, and started an agent. The final step is to trigger a run of our workflow.

## Using the web UI

We can do this in the web UI:

1. Select the `print_greeting` workflow in the sidebar.
2. Click the 'Run...' button.
3. Enter your **JSON-encoded** name (e.g., `"Joe"`, in quotes).
4. Click 'Run'.

In the web UI, you'll see the run graph.

### Exploring the run

From the graph you can see the relationship between steps. You can also switch to _timeline_ and _logs_ views. And select steps to see details related to the specific step.


## Using the CLI

Alternatively you can trigger runs using the CLI:

```bash
coflux workflow.run hello.py print_greeting '"Joe"'
```

(Note the need to tripple-quote the argument.)

