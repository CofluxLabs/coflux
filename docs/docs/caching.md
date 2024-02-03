# Caching results

Some use cases for caching include:

- Avoiding re-computing something (expensive) that we can assume hasn't changed.
- Avoiding making an external request too frequently (e.g., to an API that implements rate limiting).

:::note
Caching can also be used to avoid executing some side-effect too frequently, although [deferring](/deferring) may be a more effective approach.
:::

The simplest way to enable caching is by setting the `cache` option to `True`:

```python
@task(cache=True)
def add_numbers(a, b):
    return a + b
```

If this step has previously run with the same arguments, the step won't be re-executed - instead, the result will be taken from that previous execution.

## Maximum age

Alternatively, instead of `True`, a _maximum age_ can be specified, either with a numeric value, corresponding to seconds; or as a `datetime.timedelta`. In this case, a previous result (for the same arguments) will only be used if it's within this age:

```python
import datetime as dt

@task(cache=dt.timedelta(minutes=10))
def fetch_latest_posts(user_id):
    ...
```

This will re-use a (successful) request (for a user) as long as it's within the last ten minutes. Alternatively this could have been specified in seconds as `cache=600`.

## Expiration

Unlike a typical cache, results themselves don't expire. This gives more flexibility, as the age can be changed retrospectively. However, you can achieve an expiration-like mechanism by adding time-based task arguments. For example, adding a date parameter (and having the caller determine the current date) means you automatically stop caching at the end of the day:

```python
@task(cache=True)
def get_headlines(date):
    ...

@workflow()
def my_workflow():
    headlines = get_headlines()
    ...
```

## Pending executions

In the case of tasks being delayed (either intentionally, or a result of overloading), pending executions with caching enabled will become linked together _before_ execution has completed (or started). For example, with a recursive Fibonacci task, multiple tasks for the same _n_ value that are queued at the same time will be linked together:

```python
@task(cache=True)
def fib(n: int) -> int:
    if n == 0 or n == 1:
        return n
    else:
        return fib(n - 1) + fib(n - 2)
```

This property is generally desirable, but it means that if the first request fails, they both fail.

## Cache keys

Caching is implemented by having the caller evaluate a 'cache key', which is then used as a lookup for existing steps. The default implementation considers all (serialised) arguments for the task, but this can be overridden if needed. For example:

```python
@task(cache=True, cache_key=lambda product_id, _url: str(product_id))
def fetch_product(product_id, url):
    ...
```

Here we have a function to fetch a specified product from the provided URL. If the URL changes, we might not want that to invalidate the cache, so we set the cache key function to only consider the product ID.

## Cache namespaces

Each cache key is considered within a namespace. By default this namespace consists of the repository name and the task name. In some cases it might be necessary to override this namespace. For example, if you need to rename a function (or repository), but you want to retain the cache:

```python
@task(cache=True, cache_namespace="example1.repo:old_task_name")
def new_task_name():
    ...
```

You could also have two tasks share the same namespace:

```python
@task(cache=True, cache_namespace="my_namespace")
def task_a(a):
    ...

@task(cache=True, cache_namespace="my_namespace")
def task_b(b):
    ...
```

## Caching workflows

:::warning
The cache settings can be set on `@workflow`s as well as `@task`s, but they might not operate as expected. This is a little unintuitive, so it's subject to change.
:::

The cache settings are evaluated by the caller of the task/workflow. If the workflow is triggered manually, there isn't an opportunity to evaluate the settings, so a cache key isn't assigned. However, the settings are still applied when a workflow is called by another workflow (or by a [sensor](/sensors)). For example:

```python
@workflow(cache=True)
def child_workflow():
    ...

@workflow()
def parent_workflow():
    child_workflow()
```

In this case, both workflows will be available for scheduling - e.g., from the web UI. If you schedule `parent_workflow`, when it runs it will identify that `child_workflow` supports caching, and evaluate its cache key. However, if you schedule `child_workflow` directly from the UI, there isn't be an opportunity for the cache key to be evaluated, so caching wouldn't happen.

The workaround to this is to have the workflow wrap a child task:

```python
@task(cache=True)
def child_task():
    ...

@workflow()
def child_workflow():
    return child_task()
```

## Forcing execution

If you need to re-evaluate a task that's cached, you can do so by 're-running' the cached step. The cache settings will be ignored. Any subsequent cache hits for that task will use the result from this re-run.

## Cache hit requirements

To summarise, the requirements for a cache hit (i.e., for a previous result to be reused, instead of executing a step) are that:

1. The result must be in the same environment, within the same project.
2. The result must also have had caching enabled.
3. The cache key and namespace (as described above) must match.
4. The result must not have failed (i.e., either it was successful, it's scheduled, or it's in progress).
5. The time of the result must be within the maximum age, if specified.

