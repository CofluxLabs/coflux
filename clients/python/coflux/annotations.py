import functools

from . import context, future

TARGET_KEY = '_coflux_target'

def _run_local(fn, args):
    return fn(*[(future.Future(lambda: a) if not isinstance(a, future.Future) else a) for a in args])

def step(*, name=None, cache_key_fn=None):
    def decorate(fn):
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, ('step', fn)))

        @functools.wraps(fn)
        def wrapper(*args):  # TODO: support kwargs?
            try:
                # TODO: handle args being futures?
                cache_key = cache_key_fn(*args) if cache_key_fn else None
                execution_id = context.schedule_step(target, args, cache_key=cache_key)
                return context.get_result(execution_id)
            except context.NotInContextException:
                result = _run_local(fn, args)
                return future.Future(lambda: result) if not isinstance(result, future.Future) else result

        return wrapper

    return decorate


def task(*, name=None):
    def decorate(fn):
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, ('task', fn)))

        @functools.wraps(fn)
        def wrapper(*args):  # TODO: support kwargs?
            try:
                context.schedule_task(target, args)
            except context.NotInContextException:
                # TODO: execute in threadpool
                _run_local(fn, args)

        return wrapper

    return decorate


def sensor(*, name=None):
    def decorate(fn):
        setattr(fn, TARGET_KEY, (name or fn.__name__, ('sensor', fn)))
        return fn

    return decorate