import typing as t
import datetime as dt
from pathlib import Path

from . import execution, models


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
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[[t.Tuple[t.Any, ...]], str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
    execute_after: dt.datetime | None = None,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[[t.Tuple[t.Any, ...]], str] = False,
) -> str:
    return _get_channel().schedule_execution(
        repository,
        target,
        arguments,
        cache=cache,
        cache_key=cache_key,
        cache_namespace=cache_namespace,
        retries=retries,
        defer=defer,
        execute_after=execute_after,
        delay=delay,
        memo=memo,
    )


def resolve(target_execution_id: int) -> models.Execution[t.Any]:
    channel = _get_channel()
    return models.Execution(
        lambda: channel.resolve_reference(target_execution_id),
        target_execution_id,
    )


def persist_asset(
    path: Path | str | None = None, *, match: str | None = None
) -> models.Asset:
    return _get_channel().persist_asset(path, match=match)


def restore_asset(asset: models.Asset, *, to: Path | str | None = None) -> Path:
    return _get_channel().restore_asset(asset, to=to)


def checkpoint(*arguments: t.Any) -> None:
    return _get_channel().record_checkpoint(arguments)


def log_debug(template: str, **kwargs) -> None:
    _get_channel().log_message(0, template, **kwargs)


def log_info(template: str, **kwargs) -> None:
    _get_channel().log_message(2, template, **kwargs)


def log_warning(template: str, **kwargs) -> None:
    _get_channel().log_message(4, template, **kwargs)


def log_error(template: str, **kwargs) -> None:
    _get_channel().log_message(5, template, **kwargs)
