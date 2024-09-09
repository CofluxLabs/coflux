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
    type: t.Literal["workflow", "task"],
    repository: str,
    target: str,
    arguments: tuple[t.Any, ...],
    *,
    wait: set[int] | bool = False,
    cache: bool | int | float | dt.timedelta = False,
    cache_params: list[int] | None = None,
    cache_namespace: str | None = None,
    cache_version: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool = False,
    defer_params: list[int] | None = None,
    execute_after: dt.datetime | None = None,
    delay: int | float | dt.timedelta = 0,
    memo: list[int] | bool = False,
    requires: models.Requires | None = None,
) -> models.Execution[t.Any]:
    return _get_channel().schedule_execution(
        type,
        repository,
        target,
        arguments,
        wait=(
            set(range(len(arguments)))
            if wait is True
            else (None if wait is False else wait)
        ),
        cache_params=(
            None
            if cache is False
            else (list(range(len(arguments))) if cache_params is None else cache_params)
        ),
        cache_max_age=(None if isinstance(cache, bool) else cache),
        cache_namespace=cache_namespace,
        cache_version=cache_version,
        retries=retries,
        defer_params=(
            None
            if defer is False
            else (list(range(len(arguments))) if defer_params is None else defer_params)
        ),
        execute_after=execute_after,
        delay=delay,
        memo_params=(
            None
            if memo is False
            else (list(range(len(arguments))) if memo is True else memo)
        ),
        requires=requires,
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
