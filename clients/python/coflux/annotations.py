import functools
import typing as t
import datetime as dt

from . import context, models

TARGET_KEY = "_coflux_target"

T = t.TypeVar("T")
P = t.ParamSpec("P")


def _decorate(
    type: t.Literal["workflow", "task", None] = None,
    *,
    repository: str | None = None,
    name: str | None = None,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, models.Execution[T]]]:
    def decorator(fn: t.Callable[P, T]) -> t.Callable[P, models.Execution[T]]:
        name_ = name or fn.__name__
        repository_ = repository or fn.__module__

        # TODO: better name?
        # TODO: type?
        def submit(*args):
            try:
                execution_id = context.schedule(
                    repository_,
                    name_,
                    args,
                    cache=cache,
                    cache_key=cache_key,
                    cache_namespace=cache_namespace,
                    retries=retries,
                    defer=defer,
                    memo=memo,
                    delay=delay,
                )
                return context.resolve(execution_id)
            except context.NotInContextException:
                result = fn(*args)
                return (
                    models.Execution(lambda: result, None)
                    if not isinstance(result, models.Execution)
                    else result
                )

        if type:
            setattr(fn, TARGET_KEY, (name_, (type, fn)))

        setattr(fn, "submit", submit)

        @functools.wraps(fn)
        def wrapper(*args) -> models.Execution[T]:  # TODO: support kwargs?
            return submit(*args).result()

        return wrapper

    return decorator


def task(
    *,
    name: str | None = None,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, models.Execution[T]]]:
    return _decorate(
        "task",
        name=name,
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
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, models.Execution[T]]]:
    return _decorate(
        "workflow",
        name=name,
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
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, models.Execution[T]]]:
    return _decorate(
        repository=repository,
        name=name,
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
) -> t.Callable[[t.Callable[[T | None], None]], t.Callable[[T | None], None]]:
    def decorate(fn: t.Callable[[T | None], None]) -> t.Iterator[T]:
        setattr(fn, TARGET_KEY, (name or fn.__name__, ("sensor", fn)))
        return fn

    return decorate
