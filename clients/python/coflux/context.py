import asyncio
import contextvars
import typing as t

from . import future, session

execution_var = contextvars.ContextVar("execution")


class NotInContextException(Exception):
    pass


def set_execution(
    execution_id: str, session: session.Session, loop: asyncio.AbstractEventLoop
) -> contextvars.Token:
    return execution_var.set((execution_id, session, loop))


def reset_execution(token: contextvars.Token) -> None:
    execution_var.reset(token)


def _get() -> t.Tuple[str, session.Session, asyncio.AbstractEventLoop]:
    execution = execution_var.get(None)
    if execution is None:
        raise NotInContextException("Not running in execution context")
    return execution


def schedule(
    repository: str,
    target: str,
    args: t.Tuple[t.Any, ...],
    *,
    cache: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
) -> str:
    execution_id, session, loop = _get()
    task = session.schedule(
        repository, target, args, execution_id, cache, cache_namespace, retries
    )
    return asyncio.run_coroutine_threadsafe(task, loop).result()


def get_result(target_execution_id: str) -> future.Future[t.Any]:
    execution_id, session, loop = _get()
    return future.Future(
        lambda: session.get_result(target_execution_id, execution_id),
        ["reference", target_execution_id],
        loop,
    )


def log_debug(message: str) -> None:
    execution_id, session, loop = _get()
    task = session.log_message(execution_id, 2, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()


def log_info(message: str) -> None:
    execution_id, session, loop = _get()
    task = session.log_message(execution_id, 3, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()


def log_warning(message: str) -> None:
    execution_id, session, loop = _get()
    task = session.log_message(execution_id, 4, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()


def log_error(message: str) -> None:
    execution_id, session, loop = _get()
    task = session.log_message(execution_id, 5, message)
    asyncio.run_coroutine_threadsafe(task, loop).result()
