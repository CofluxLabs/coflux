# Asynchronous execution

:::note
This isn't related to `async`/`await` in Python.
:::

By default, when you call a task from another task (or workflow), execution will be paused while waiting for the called task to complete. This is more intuitive, and makes adoption a bit easier.

Often, however, you'll want to be able to execute tasks in parallel, and collect the results later on. Or trigger a task without waiting for the result. This can be done by 'submitting' the task instead of calling it. You can then wait for the result when it's needed:

```python
@task()
def load_user(user_id):
    ...

@task()
def load_product(product_id):
    ...

@workflow()
def process_order(user_id, product_id):
    user_future = load_user.submit(user_id)
    product_future = load_product.submit(product_id)

    user = user_future.result()
    product = product_future.result()

    ...
```

In this case, a task to load the user and a task to load the product will run in parallel, reducing the total time for the workflow to run. This is clear by looking at the timeline:

<img src="/img/asynchronous.png" alt="Asynchronous execution" width="500" />

And comparing to a synchronous equivalent:

<img src="/img/synchronous.png" alt="Synchronous execution" width="500" />

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

## Passing/returning futures

Futures can be passed to other tasks, or returned from a task/workflow to avoid unnecessarily waiting for a result. Demonstrating both:

```python
@workflow()
def process_order(user_id, product_id):
    user_future = load_user.submit(user_id)
    product_future = load_product.submit(product_id)
    return create_order.submit(user_future, product_future)
```

In this case, the workflow is simply responsible for submitting three tasks, after which it can return:

<img src="/img/futures_timeline.png" alt="Futures timeline" width="500" />

The relationships between the tasks is indicated in the graph view. The dashed line indicates that there is a parent-child relationship, bit without a strict dependency. This can help to indicate the direction that data is flowing:

<img src="/img/futures_graph.png" alt="Futures graph" width="500" />

## Fire-and-forget

You can submit a task without ever waiting for the result. In this case the caller doesn't have a way to know that the task was successful, but it may be acceptable to rely on the retry mechanism or separate monitoring. An example use case might be sending a notification to a user.

