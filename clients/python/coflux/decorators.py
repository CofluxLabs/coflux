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
    default: str | None


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
    parameters = inspect.signature(fn).parameters.values()
    for p in parameters:
        if p.kind != inspect.Parameter.POSITIONAL_OR_KEYWORD:
            raise Exception(f"Unsupported parameter type ({p.kind})")
    return TargetDefinition(type, [_build_parameter(p) for p in parameters])


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
        cache_params: t.Iterable[str] | str | None = None,
        retries: int | tuple[int, int] | tuple[int, int, int] = 0,
        defer: bool = False,
        defer_params: t.Iterable[str] | str | None = None,
        delay: int | float | dt.timedelta = 0,
        memo: bool | t.Iterable[str] | str = False,
        requires: dict[str, str | bool | list[str]] | None = None,
        is_stub: bool = False,
    ):
        definition = _build_target_definition(type, fn)
        self._fn = fn
        self._type = type
        self._name = name or fn.__name__
        self._repository = repository or fn.__module__
        self._wait = (
            wait
            if isinstance(wait, bool)
            else set(_get_param_indexes(definition, wait))
        )
        self._cache = cache
        self._cache_params = (
            None
            if cache_params is None
            else _get_param_indexes(definition, cache_params)
        )
        self._retries = retries
        self._defer = defer
        self._defer_params = (
            None
            if defer_params is None
            else _get_param_indexes(definition, defer_params)
        )
        self._delay = delay
        self._memo = (
            memo if isinstance(memo, bool) else _get_param_indexes(definition, memo)
        )
        self._requires = _parse_requires(requires)
        self._definition = None if is_stub else definition
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
                cache_params=self._cache_params,
                retries=self._retries,
                defer=self._defer,
                defer_params=self._defer_params,
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


def _get_param_indexes(
    definition: TargetDefinition,
    names: t.Iterable[str] | str,
) -> list[int]:
    if isinstance(names, str):
        names = re.split(r",\s*", names)
    indexes = []
    parameter_names = [p.name for p in definition.parameters]
    for name in names:
        if name not in parameter_names:
            raise Exception(f"Unrecognised parameter in wait ({name})")
        indexes.append(parameter_names.index(name))
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
    cache_params: t.Iterable[str] | str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool = False,
    defer_params: t.Iterable[str] | str | None = None,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Iterable[str] = False,
    requires: dict[str, str | bool | list[str]] | None = None,
) -> t.Callable[[t.Callable[P, T]], Target[P, T]]:
    def decorator(fn: t.Callable[P, T]) -> Target[P, T]:
        return Target(
            fn,
            "task",
            name=name,
            wait=wait,
            cache=cache,
            cache_params=cache_params,
            retries=retries,
            defer=defer,
            defer_params=defer_params,
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
    cache_params: t.Iterable[str] | str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool = False,
    defer_params: t.Iterable[str] | str | None = None,
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
            cache_params=cache_params,
            retries=retries,
            defer=defer,
            defer_params=defer_params,
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
    cache_params: t.Iterable[str] | str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    defer: bool = False,
    defer_params: t.Iterable[str] | str | None = None,
    delay: int | float | dt.timedelta = 0,
    memo: bool | t.Iterable[str] = False,
) -> t.Callable[[t.Callable[P, T]], Target[P, T]]:
    def decorator(fn: t.Callable[P, T]) -> Target[P, T]:
        return Target(
            fn,
            type,
            repository=repository,
            name=name,
            wait=wait,
            cache=cache,
            cache_params=cache_params,
            retries=retries,
            defer=defer,
            defer_params=defer_params,
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
