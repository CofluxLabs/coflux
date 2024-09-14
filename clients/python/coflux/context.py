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
    cache: models.Cache | None = None,
    retries: models.Retries | None = None,
    defer: models.Defer | None = None,
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
        wait=wait,
        cache=cache,
        retries=retries,
        defer=defer,
        execute_after=execute_after,
        delay=delay,
        memo=memo,
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
