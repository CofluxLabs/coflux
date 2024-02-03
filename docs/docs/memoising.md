# Memoising

Memoising is similar to caching, however it only applies to steps within a run, and serves a subtly different purpose. With caching, a cache hit still results in a new step entity, but the result will be shared. Memoising is more lightweight because the existing execution is referenced, rather than creating a new step which references the existing result.

It serves two purposes:

1. Making debugging easier
2. Optimising runs

Enable memoising of a task with the `memo` option:

```python
@task(memo=True)
def fetch_user(user_id):
    ...
```

Memoised steps are indicated in the web UI with a pin icon.

As with caching, explicitly clicking the 're-run' button for a step will force the step to be re-run, even if it's memoised. Then subsequent memoising will use the new step execution.

## For debugging

Memoising provides several benefits for debugging:

1. Memoising a task with side effects (e.g., sending a notification e-mail) means you can re-run the run without that side-effect happening.

    :::warning
    This technique requires care. Consider the implications of unintentionally re-running the task. It may be better to run in an environment that doesn't have access to credentials.
    :::

2. Memoising slow tasks allows you to fix bugs that are occuring elsewhere in the workflow.

## For optimisation

Memoising can also be used as an optimisation for workflows. For example, if a resource needs to be used in multiple parts of a run, rather than passing around that resource, the task to fetch it can be memoised:

```python
@task(memo=True)
def fetch_user(user_id):
    ...

@task()
def send_email(user_id):
    user = fetch_user(user_id)
    ...

@task()
def send_notification(user_id):
    user = fetch_user(user_id)
    ...
```

## Memo keys

By default the memo key is composed of all arguments. It can be overridden by specifying a function (or lambda) that takes the task's arguments and returns a string:

```python
@task(memo=lambda machine_id, config: str(machine_id))
def apply_configuration(machine_id, config)
    ...
```

In this case, the function to apply configuration to a machine is only run once for the specified machine, regardless of whether the configuration itself changes. This can allow you to make changes to a workflow and re-run it with (some) confidence that a new configuration won't be applied.
