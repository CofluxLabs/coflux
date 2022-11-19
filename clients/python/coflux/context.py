import asyncio
import contextvars

from . import future

execution_var = contextvars.ContextVar('execution')

class NotInContextException(Exception):
    pass

def set_execution(execution_id, client, loop):
    return execution_var.set((execution_id, client, loop))

def reset_execution(token):
    execution_var.reset(token)

def _get():
    execution = execution_var.get(None)
    if execution is None:
        raise NotInContextException("Not running in execution context")
    return execution

def schedule_task(target, args, repository=None):
    execution_id, client, loop = _get()
    task = client.schedule_task(execution_id, target, args, repository)
    asyncio.run_coroutine_threadsafe(task, loop).result()

def schedule_step(target, args, repository=None, cache_key=None):
    execution_id, client, loop = _get()
    task = client.schedule_step(execution_id, target, args, repository, cache_key)
    return asyncio.run_coroutine_threadsafe(task, loop).result()

def get_result(target_execution_id):
    execution_id, client, loop = _get()
    return future.Future(
        lambda: client.get_result(target_execution_id, execution_id),
        ['result', target_execution_id],
        loop,
    )

def log_debug(message):
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 0, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()

def log_info(message):
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 1, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()

def log_warning(message):
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 2, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()

def log_error(message):
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 3, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()

