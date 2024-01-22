import typing as t


T = t.TypeVar("T")


class Future(t.Generic[T]):
    def __init__(
        self,
        resolve_fn: t.Callable[[], T],
        execution_id: str | None,
    ):
        self._resolve_fn = resolve_fn
        self._execution_id = execution_id

    @property
    def execution_id(self) -> str | None:
        return self._execution_id

    def result(self) -> T:
        return self._resolve_fn()
