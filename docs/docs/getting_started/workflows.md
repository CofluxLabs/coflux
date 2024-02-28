# 1. Defining workflows

Workflows are defined in code, using Python functions, which are annotated to indicate their operation type and configuration. A _workflow_ is the entry point for a workflow, and a _task_ is an operation to be executed within the run. Workflows can call tasks, tasks can call other tasks, and tasks can also call workflows (which initiates a separate run).

The annotations are designed to be unimposing so that functions can be executed independently, without connecting to the Coflux server.

## An example

Let's start with a simple example:

```python
import coflux as cf

@cf.task()
def build_greeting(name: str):
    return f"Hello, {name}"

@cf.workflow()
def print_greeting(name: str):
    print(build_greeting(name))
```

This defines a `print_greeting` workflow, which takes a `name` as an argument. When run, it calls the `build_greeting` task, passing through the name argument. Once it has the result from the task, the result gets printed.

Workflows are defined in _repositories_, which are typically Python modules, but can also be loaded from a Python script, which we'll do momentarily.

**Put the workflow above into `hello.py`.** (We'll install the `coflux` library in a moment.)

Before coming back to more advanced features, let's see how to get this workflow running...
