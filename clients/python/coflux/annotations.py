import functools
import typing as t

from . import context, future

TARGET_KEY = "_coflux_target"

T = t.TypeVar("T")
P = t.ParamSpec("P")


def _decorate(
    type: t.Literal["workflow", "task", None] = None,
    *,
    repository: str | None = None,
    name: str | None = None,
    cache: bool | t.Callable[P, str] = False,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    deduplicate: bool | t.Callable[P, str] = False,
    delay: int = 0,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, future.Future[T]]]:
    def decorator(fn: t.Callable[P, T]) -> t.Callable[P, future.Future[T]]:
        name_ = name or fn.__name__
        repository_ = repository or fn.__module__

        # TODO: better name?
        # TODO: type?
        def submit(*args):
            try:
                # TODO: handle args being futures?
                execution_id = context.schedule(
                    repository_,
                    name_,
                    args,
                    cache=cache,
                    cache_namespace=cache_namespace,
                    retries=retries,
                    deduplicate=deduplicate,
                    delay=delay,
                )
                return context.get_result(execution_id)
            except context.NotInContextException:
                result = fn(*args)
                return (
                    future.Future(lambda: result)
                    if not isinstance(result, future.Future)
                    else result
                )

        if type:
            setattr(fn, TARGET_KEY, (name_, (type, fn)))

        setattr(fn, "submit", submit)

        @functools.wraps(fn)
        def wrapper(*args) -> future.Future[T]:  # TODO: support kwargs?
            return submit(*args).result()

        return wrapper

    return decorator


def task(
    *,
    name: str | None = None,
    cache: bool | t.Callable[P, str] = False,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    deduplicate: bool | t.Callable[P, str] = False,
    delay: int = 0,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, future.Future[T]]]:
    return _decorate(
        "task",
        name=name,
        cache=cache,
        cache_namespace=cache_namespace,
        retries=retries,
        deduplicate=deduplicate,
        delay=delay,
    )


def workflow(
    *,
    name: str | None = None,
    cache: bool | t.Callable[P, str] = False,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    deduplicate: bool | t.Callable[P, str] = False,
    delay: int = 0,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, future.Future[T]]]:
    return _decorate(
        "workflow",
        name=name,
        cache=cache,
        cache_namespace=cache_namespace,
        retries=retries,
        deduplicate=deduplicate,
        delay=delay,
    )


def stub(
    repository: str,
    *,
    name: str | None = None,
    cache: bool | t.Callable[P, str] = False,
    cache_namespace: str | None = None,
    retries: int | tuple[int, int] | tuple[int, int, int] = 0,
    deduplicate: bool | t.Callable[P, str] = False,
    delay: int = 0,
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, future.Future[T]]]:
    return _decorate(
        repository=repository,
        name=name,
        cache=cache,
        cache_namespace=cache_namespace,
        retries=retries,
        deduplicate=deduplicate,
        delay=delay,
    )


def sensor(
    *, name=None
) -> t.Callable[[t.Callable[[T | None], None]], t.Callable[[T | None], None]]:
    def decorate(fn: t.Callable[[T | None], None]) -> t.Iterator[T]:
        setattr(fn, TARGET_KEY, (name or fn.__name__, ("sensor", fn)))
        return fn

    return decorate
