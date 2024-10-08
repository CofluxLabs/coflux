# Suspense

Suspense is a way of putting the step to sleep - the current execution will be stopped and a new execution will be started, executing _from the beginning of the task_.

The suspense can be either _explicit_ or _implicit_. In either case, it's important that it's safe for the code up to the point of suspense can be re-executed - i.e., any side-effects need to be idempotent. (An easy way to achieve this is to ensure that any tasks called by the execution are [memoised](/memoising).)

Suspense is useful as a way of freeing up resources used by a waiting execution.

## Explicit suspense

To explicitly suspend an execution, simply call the `suspend` function, passing either a delay (as a number of seconds, or as a `datetime.timedelta`), or a future timestamp (as a `datetime.datetime`):

```python
@cf.workflow()
def my_workflow():
    # (some code that is safe to be re-run)
    if not some_condition():
        cf.suspend(60) # restart the task in one minute
    # (do something)
```

It's important to suspend based on some condition, otherwise the task will be repeatedly suspended and re-run.

## Implicit suspense

Implicit suspense is implemented by entering a 'suspense' context, specifying a timeout. If the timeout is reached while waiting for the result of another execution, the execution will be suspended and automatically re-started (from the beginning) after the required result becomes available:

```python
@cf.task()
def create_order(user_execution, product_execution):
    with cf.suspense(timeout=1):
        # if the result isn't available within one second, the `create_order` execution will suspend
        user = user_execution.result()
    # this is outside the suspense context, so there's no timeout
    product = product_execution.result()
    # ...
```
