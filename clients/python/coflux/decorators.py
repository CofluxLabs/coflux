import functools
import typing as t
import datetime as dt
import inspect
import re

from . import context, models

TARGET_KEY = "_coflux_target"

T = t.TypeVar("T")
P = t.ParamSpec("P")


TargetType = t.Literal["workflow", "task", "sensor"]


class Target(t.Generic[P, T]):
    _type: TargetType

    def __init__(
        self,
        fn: t.Callable[P, T],
        type: TargetType,
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
        is_stub: bool = False,
    ):
        self._fn = fn
        self._type = type
        self._name = name or fn.__name__
        self._repository = repository or fn.__module__
        self._wait = _parse_wait(fn, wait)
        self._cache = cache
        self._cache_key = cache_key
        self._cache_namespace = cache_namespace
        self._retries = retries
        self._defer = defer
        self._delay = delay
        self._memo = memo
        self._is_stub = is_stub
        functools.update_wrapper(self, fn)

    @property
    def name(self) -> str:
        return self._name

    @property
    def type(self) -> TargetType:
        return self._type

    @property
    def is_stub(self) -> bool:
        return self._is_stub

    @property
    def fn(self) -> t.Callable[P, T]:
        return self._fn

    def submit(self, *args: P.args, **kwargs: P.kwargs) -> models.Execution[T]:
        assert self._type in ("workflow", "task")
        try:
            return context.schedule(
                self._type,
                self._repository,
                self._name,
                args,
                wait=self._wait,
                cache=self._cache,
                cache_key=self._cache_key,
                cache_namespace=self._cache_namespace,
                retries=self._retries,
                defer=self._defer,
                memo=self._memo,
                delay=self._delay,
            )
        except context.NotInContextException:
            result = self._fn(*args, **kwargs)
            return (
                models.Execution(lambda: result, None)
                if not isinstance(result, models.Execution)
                else result
            )

    def __call__(self, *args: P.args, **kwargs: P.kwargs) -> T:
        return self.submit(*args, **kwargs).result()


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
) -> t.Callable[[t.Callable[P, T]], Target[P, T]]:
    def decorator(fn: t.Callable[P, T]) -> Target[P, T]:
        return Target(
            fn,
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

    return decorator


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
) -> t.Callable[[t.Callable[P, T]], Target[P, T]]:
    def decorator(fn: t.Callable[P, T]) -> Target[P, T]:
        return Target(
            fn,
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

    return decorator


def stub(
    repository: str,
    *,
    name: str | None = None,
    type: t.Literal["workflow", "task"] = "task",
    wait: bool | t.Iterable[str] | str = False,
    cache: bool | int | float | dt.timedelta = False,
    cache_key: t.Callable[P, str] | None = None,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool | t.Callable[P, str] = False,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Callable[P, str] = False,
) -> t.Callable[[t.Callable[P, T]], Target[P, T]]:
    def decorator(fn: t.Callable[P, T]) -> Target[P, T]:
        return Target(
            fn,
            type,
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
            is_stub=True,
        )

    return decorator


def sensor(*, name=None) -> t.Callable[[t.Callable[P, None]], t.Callable[P, None]]:
    def decorator(fn: t.Callable[P, None]) -> t.Callable[P, None]:
        return Target(fn, "sensor", name=name)

    return decorator
