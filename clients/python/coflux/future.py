import asyncio
import typing as t

T = t.TypeVar("T")


class Future(t.Generic[T]):
    def __init__(self, resolve_fn: t.Callable[[], T], serialised=None, loop=None):
        self._resolve_fn = resolve_fn
        self._serialised = serialised
        self._loop = loop

    def serialise(self):
        return self._serialised

    def result(self) -> T:
        if self._loop:
            return asyncio.run_coroutine_threadsafe(
                self._resolve_fn(), self._loop
            ).result()
        else:
            return self._resolve_fn()
