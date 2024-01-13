import typing as t

from .types import Value

T = t.TypeVar("T")


class Future(t.Generic[T]):
    def __init__(
        self,
        resolve_fn: t.Callable[[], T],
        serialised: Value | None = None,
    ):
        self._resolve_fn = resolve_fn
        self._serialised = serialised

    def serialise(self) -> Value:
        assert self._serialised is not None
        return self._serialised

    def result(self) -> T:
        return self._resolve_fn()
