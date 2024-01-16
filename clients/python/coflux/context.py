import typing as t
import datetime as dt

from . import execution, future


class NotInContextException(Exception):
    pass


def _get_channel() -> execution.Channel:
    channel = execution.get_channel()
    if channel is None:
        raise NotInContextException("Not running in execution context")
    return channel


def schedule(
    repository: str,
    target: str,
    arguments: tuple[t.Any, ...],
    *,
    cache: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    deduplicate: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
    execute_after: dt.datetime | None = None,
    delay: int | float | dt.timedelta = 0,
) -> str:
    return _get_channel().schedule_execution(
        repository,
        target,
        arguments,
        cache=cache,
        cache_namespace=cache_namespace,
        retries=retries,
        deduplicate=deduplicate,
        execute_after=execute_after,
        delay=delay,
    )


def get_result(target_execution_id: str) -> future.Future[t.Any]:
    channel = _get_channel()
    return future.Future(
        lambda: channel.resolve_reference(target_execution_id),
        ("reference", target_execution_id),
    )


def checkpoint(*arguments: t.Any) -> None:
    return _get_channel().record_checkpoint(arguments)


def log_debug(message: str) -> None:
    _get_channel().log_message(0, message)


def log_info(message: str) -> None:
    _get_channel().log_message(2, message)


def log_warning(message: str) -> None:
    _get_channel().log_message(4, message)


def log_error(message: str) -> None:
    _get_channel().log_message(5, message)
