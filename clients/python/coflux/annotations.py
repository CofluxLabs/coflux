import functools
import typing as t
import datetime as dt
import inspect
import re

from . import context, models

TARGET_KEY = "_coflux_target"

T = t.TypeVar("T")
P = t.ParamSpec("P")


def _parse_wait(fn: t.Callable, wait: bool | t.Iterable[str] | str) -> set[int] | None:
    if not wait:
        return None
    parameters = [
        p.name
        for p in inspect.signature(fn).parameters.values()
        if p.kind == inspect.Parameter.POSITIONAL_OR_KEYWORD
    ]
    if wait is True:
        return set(range(len(parameters)))
    if isinstance(wait, str):
        wait = re.split(r",\s*", wait)
    indexes = set()
    for parameter in wait:
        if parameter not in parameters:
            raise Exception(f"no parameter '{parameter}' for function {fn.__name__}")
        indexes.add(parameters.index(parameter))
    return indexes


def _decorate(
    type: t.Literal["workflow", "task", None] = None,
    *,
    repository: str | None = None,
    name: str | None = None,
    wait: bool | t.Iterable[str] | str = False,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, T]]:
    def decorator(fn: t.Callable[P, T]) -> t.Callable[P, T]:
        name_ = name or fn.__name__
        repository_ = repository or fn.__module__

        wait_ = _parse_wait(fn, wait)

        def submit(*args: P.args, **kwargs: P.kwargs) -> models.Execution[T]:
            try:
                return context.schedule(
                    repository_,
                    name_,
                    args,
                    wait=wait_,
                    cache=cache,
                    cache_key=cache_key,
                    cache_namespace=cache_namespace,
                    retries=retries,
                    defer=defer,
                    memo=memo,
                    delay=delay,
                )
            except context.NotInContextException:
                result = fn(*args, **kwargs)
                return (
                    models.Execution(lambda: result, None)
                    if not isinstance(result, models.Execution)
                    else result
                )

        if type:
            setattr(fn, TARGET_KEY, (name_, (type, fn)))

        setattr(fn, "submit", submit)

        @functools.wraps(fn)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> T:
            return submit(*args, **kwargs).result()

        return wrapper

    return decorator


def task(
    *,
    name: str | None = None,
    wait: bool | t.Iterable[str] | str = False,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, T]]:
    return _decorate(
        "task",
        name=name,
        wait=wait,
        cache=cache,
        cache_key=cache_key,
        cache_namespace=cache_namespace,
        retries=retries,
        defer=defer,
        delay=delay,
        memo=memo,
    )


def workflow(
    *,
    name: str | None = None,
    wait: bool | t.Iterable[str] | str = False,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, T]]:
    return _decorate(
        "workflow",
        name=name,
        wait=wait,
        cache=cache,
        cache_key=cache_key,
        cache_namespace=cache_namespace,
        retries=retries,
        defer=defer,
        delay=delay,
    )


def stub(
    repository: str,
    *,
    name: str | None = None,
    wait: bool | t.Iterable[str] | str = False,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, T]]:
    return _decorate(
        repository=repository,
        name=name,
        wait=wait,
        cache=cache,
        cache_key=cache_key,
        cache_namespace=cache_namespace,
        retries=retries,
        defer=defer,
        delay=delay,
        memo=memo,
    )


def sensor(
    *, name=None
) -> t.Callable[[t.Callable[P, None]], t.Callable[P, None]]:
    def decorate(fn: t.Callable[P, None]) -> t.Callable[P, None]:
        setattr(fn, TARGET_KEY, (name or fn.__name__, ("sensor", fn)))
        return fn

    return decorate
