import functools
import typing as t
import datetime as dt
import inspect
import re
import json

from . import context, models

TARGET_KEY = "_coflux_target"

T = t.TypeVar("T")
P = t.ParamSpec("P")


TargetType = t.Literal["workflow", "task", "sensor"]


class Parameter(t.NamedTuple):
    name: str
    annotation: str | None
    default_: str | None


class TargetDefinition(t.NamedTuple):
    type: TargetType
    parameters: list[Parameter]


def _json_dumps(obj: t.Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


def _build_parameter(parameter: inspect.Parameter) -> Parameter:
    return Parameter(
        parameter.name,
        # TODO: better serialisation?
        (
            str(parameter.annotation)
            if parameter.annotation != inspect.Parameter.empty
            else None
        ),
        (
            _json_dumps(parameter.default)
            if parameter.default != inspect.Parameter.empty
            else None
        ),
    )


def _build_target_definition(type: TargetType, fn: t.Callable):
    parameters = [
        _build_parameter(p) for p in inspect.signature(fn).parameters.values()
    ]
    return TargetDefinition(type, parameters)


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
        requires: dict[str, str | bool | list[str]] | None = None,
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
        self._requires = _parse_requires(requires)
        self._definition = (
            None if is_stub else _build_target_definition(self._type, self._fn)
        )
        functools.update_wrapper(self, fn)

    @property
    def name(self) -> str:
        return self._name

    @property
    def definition(self) -> TargetDefinition | None:
        return self._definition

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
                delay=self._delay,
                memo=self._memo,
                requires=self._requires,
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


def _parse_require(value: str | bool | list[str]):
    if isinstance(value, bool):
        return ["true"] if value else ["false"]
    elif isinstance(value, str):
        return [value]
    else:
        return value


def _parse_requires(
    requires: dict[str, str | bool | list[str]] | None
) -> models.Requires | None:
    return {k: _parse_require(v) for k, v in requires.items()} if requires else None


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
    requires: dict[str, str | bool | list[str]] | None = None,
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
            requires=requires,
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
    requires: dict[str, str | bool | list[str]] | None = None,
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
            requires=requires,
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


def sensor(
    *,
    name=None,
    requires: dict[str, str | bool | list[str]] | None = None,
) -> t.Callable[[t.Callable[P, None]], t.Callable[P, None]]:
    def decorator(fn: t.Callable[P, None]) -> Target[P, None]:
        return Target(
            fn,
            "sensor",
            name=name,
            requires=requires,
        )

    return decorator