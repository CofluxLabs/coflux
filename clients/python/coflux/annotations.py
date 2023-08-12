import functools
import typing as t

from . import context, future

TARGET_KEY = "_coflux_target"

T = t.TypeVar("T")
P = t.ParamSpec("P")


def step(
    *, name: str | None = None, cache_key_fn: t.Callable[P, str] | None = None
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, future.Future[T]]]:
    def decorate(fn: t.Callable[P, T]) -> t.Callable[P, future.Future[T]]:
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, ("step", fn)))

        @functools.wraps(fn)
        def wrapper(*args) -> future.Future[T]:  # TODO: support kwargs?
            try:
                repository = fn.__module__
                cache_key = cache_key_fn(*args) if cache_key_fn else None
                # TODO: handle args being futures?
                execution_id = context.schedule_step(
                    repository, target, args, cache_key=cache_key
                )
                return context.get_result(execution_id)
            except context.NotInContextException:
                result = fn(*args)
                return (
                    future.Future(lambda: result)
                    if not isinstance(result, future.Future)
                    else result
                )

        return wrapper

    return decorate


def task(
    *, name: str | None = None
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, None]]:
    def decorate(fn: t.Callable[P, T]) -> t.Callable[P, None]:
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, ("task", fn)))

        @functools.wraps(fn)
        def wrapper(*args) -> None:  # TODO: support kwargs?
            # TODO: return future?
            try:
                repository = fn.__module__
                context.schedule_task(repository, target, args)
            except context.NotInContextException:
                # TODO: execute in threadpool
                fn(*args)

        return wrapper

    return decorate


# TODO: cache_key (etc?)
# TODO: support stubbing tasks?
def stub(
    repository: str, *, target: str | None = None
) -> t.Callable[[t.Callable[P, T]], t.Callable[P, future.Future[T]]]:
    def decorate(fn: t.Callable[P, T]) -> t.Callable[P, future.Future[T]]:
        @functools.wraps(fn)
        def wrapper(*args) -> future.Future[T]:  # TODO: support kwargs?
            try:
                execution_id = context.schedule_step(
                    repository, target or fn.__name__, args
                )
                return context.get_result(execution_id)
            except context.NotInContextException:
                result = fn(*args)
                return (
                    future.Future(lambda: result)
                    if not isinstance(result, future.Future)
                    else result
                )

        return wrapper

    return decorate


def sensor(
    *, name=None
) -> t.Callable[[t.Callable[[T | None], None]], t.Callable[[T | None], None]]:
    def decorate(fn: t.Callable[[T | None], None]) -> t.Iterator[T]:
        setattr(fn, TARGET_KEY, (name or fn.__name__, ("sensor", fn)))
        return fn

    return decorate
