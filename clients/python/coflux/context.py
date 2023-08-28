import asyncio
import contextvars
import typing as t

from . import future, client

execution_var = contextvars.ContextVar("execution")


class NotInContextException(Exception):
    pass


def set_execution(
    execution_id: str, client: client.Client, loop: asyncio.AbstractEventLoop
) -> contextvars.Token:
    return execution_var.set((execution_id, client, loop))


def reset_execution(token: contextvars.Token) -> None:
    execution_var.reset(token)


def _get() -> t.Tuple[str, client.Client, asyncio.AbstractEventLoop]:
    execution = execution_var.get(None)
    if execution is None:
        raise NotInContextException("Not running in execution context")
    return execution


def schedule(
    repository: str,
    target: str,
    args: t.Tuple[t.Any, ...],
    *,
    cache_key: str | None = None,
    retries: tuple[int, int, int],
) -> str:
    execution_id, client, loop = _get()
    task = client.schedule(repository, target, args, execution_id, cache_key, retries)
    return asyncio.run_coroutine_threadsafe(task, loop).result()


def get_result(target_execution_id: str) -> future.Future[t.Any]:
    execution_id, client, loop = _get()
    return future.Future(
        lambda: client.get_result(target_execution_id, execution_id),
        ["reference", target_execution_id],
        loop,
    )


def log_debug(message: str) -> None:
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 0, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()


def log_info(message: str) -> None:
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 1, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()


def log_warning(message: str) -> None:
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 2, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()


def log_error(message: str) -> None:
    execution_id, client, loop = _get()
    task = client.log_message(execution_id, 3, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()
