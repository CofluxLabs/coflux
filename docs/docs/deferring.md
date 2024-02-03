# Deferring

## Delaying tasks

Execution of tasks can be delayed by a fixed duration, by configuring the `delay`. This can be specified as a `datetime.timedelta`, or as a numeric value, in seconds:

```python
import datetime as dt

@task(delay=dt.timedelta(minutes=10))
def send_reminder(user_id):
    ...
```

## De-duplicating tasks

Delaying tasks is useful in combination with 'deferring' as a way to de-duplicate some operation. This concept is sometimes referred to (particularly in UI development) as 'debouncing'.

For example, you might want to be able to send a notification to a user to notify of them of updates to a document. If there are lots of updates to the document within a short period of time, you wouldn't want to send notifications for every change. Instead, you can configure a delay, as above, and enable deferring. This is done by specifying the `defer` option on the task:

```python
@task(delay=60, defer=True):
def send_notification(user_id, document_id):
    ...
```

With this configuration, the initial task call will be delayed by 60 seconds, and, in the meantime, if the task is called again with the same arguments, the new task will replace the original one. Any tasks waiting on the initial task will wait for the new task instead. This deferring process will continue until there's a break of 60 seconds between calls, at which point the latest task will execute.

Deferring can also be useful without specifying an explicit delay in the case where there's a backlog of tasks waiting to be executed.

## Defer keys

Passing `True` for the `defer` option indicates that all the arguments should be considered. Alternatively, a function (or lambda) can be passed, which takes the task arguments (e.g., `user_id` and `document_id` in the example above). This function should return an alternative key, which will be used to consider uniqueness (for the task). For example, if might be necessary for the function to know the specific update that is triggering the notification, but this wouldn't be relevant for deduplication:

```python
@task(delay=60, defer=lambda u, d, _: f"#{u}:#{d}")
def send_notification(user_id, document_id, update):
    ...
```

In this case, subsequent calls for the same user and document would be de-duplicated, even though the update is different each time.
