import typing as t

T = t.TypeVar("T")


class Future(t.Generic[T]):
    def __init__(self, resolve_fn: t.Callable[[], T], serialised=None):
        self._resolve_fn = resolve_fn
        self._serialised = serialised

    def serialise(self):
        return self._serialised

    def result(self) -> T:
        return self._resolve_fn()
