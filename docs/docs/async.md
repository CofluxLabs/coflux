# Asynchronous execution

:::note
This topic isn't related to `async`/`await` in Python.
:::

By default, when you call a task from another task (or workflow), execution will be paused while waiting for the called task to complete. This is more intuitive for beginners, and also makes code more portable.

Often, however, you'll want to be able to execute tasks in parallel, and collect the results later on. Or trigger a task without waiting for the result. This can be done by 'submitting' the task (using `.submit(...)`) instead of calling it. This returns an `Execution`, which is a 'future'-like object that can be used to wait for the result (using `.result()`), when needed:

```python
@task()
def load_user(user_id):
    # ...

@task()
def load_product(product_id):
    # ...

@workflow()
def process_order(user_id, product_id):
    user_execution = load_user.submit(user_id)
    product_execution = load_product.submit(product_id)

    user = user_execution.result()
    product = product_execution.result()

    # ...
```

In this case, a task to load the user and a task to load the product will run in parallel, reducing the total time for the workflow to run. This is clear by looking at the timeline:

<img src="/img/asynchronous.png" alt="Asynchronous execution" width="500" />

And comparing to a synchronous equivalent:

<img src="/img/synchronous.png" alt="Synchronous execution" width="500" />

Note the longer total execution time.

:::info
Calling a task synchronously is the same as submitting it and then immediately waiting for its result. The following two workflows are equivalent:

```python
@workflow()
def my_workflow(a, b):
    return my_task(a, b)
```

```python
@workflow()
def my_workflow(a, b):
    return my_task.submit(a, b).result()
```
:::

## Passing and returning executions

`Execution` objects can be passed to other tasks, or returned from a task/workflow to avoid unnecessarily waiting for a result. Demonstrating both:

```python
@workflow()
def process_order(user_id, product_id):
    user_execution = load_user.submit(user_id)
    product_execution = load_product.submit(product_id)
    return create_order.submit(user_execution, product_execution)
```

In this case, the workflow function is responsible for submitting three tasks and wiring them together, after which it can return, without waiting for those tasks to complete:

<img src="/img/async_timeline.png" alt="Futures timeline" width="500" />

The relationships between the tasks is indicated in the graph view. The dashed line indicates that there is a parent-child relationship, but without a strict dependency. This can help to indicate the direction that data is flowing:

<img src="/img/async_graph.png" alt="Futures graph" width="500" />

## Explicit waiting

In the timeline above you can see that the `create_order` task is started immediately after being scheduled by the `process_order`. But it actually spends most of its time waiting for the results from the two 'load' tasks. We can avoid this idle time by specifying that execution of `process_order` shouldn't start until its dependencies are ready. To do this, we specify `wait=` on the `@task`, specifying either `True`, to wait for all arguments, or by specifying the names of arguments that should be waited for (either as an iterable, or a comma-separated string):

```python
@task(wait=True)
def create_order(user_execution, product_execution):
    user = user_execution.result()
    product = product_execution.result()
    # ...
```

We can see from the timeline that the `create_order` task waits to be executed until its dependencies have completed:

<img src="/img/wait_for.png" alt="Explicit waiting timeline" width="500" />

## Fire-and-forget

A task can be submitted without ever waiting for the result. In this case the caller doesn't have a way to know that the task was successful, but it may be acceptable to rely on the retry mechanism or separate monitoring.

An example use case might be sending a notification to a user.

