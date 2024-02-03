import typing as t

T = t.TypeVar("T")

# TODO: use named tuples

Metadata = dict[str, t.Any]

References = dict[int, str]

Paths = dict[int, tuple[str, str, Metadata]]

Value = t.Union[
    tuple[t.Literal["raw"], bytes, str, References, Paths],
    tuple[t.Literal["blob"], str, Metadata, str, References, Paths],
]

Result = t.Union[
    tuple[t.Literal["value"], Value],
    tuple[t.Literal["error"], str, str],
    tuple[t.Literal["abandoned"]],
    tuple[t.Literal["cancelled"]],
]


class Execution(t.Generic[T]):
    def __init__(
        self,
        resolve_fn: t.Callable[[], T],
        id: str | None,
    ):
        self._resolve_fn = resolve_fn
        self._id = id

    @property
    def id(self) -> str | None:
        return self._id

    def result(self) -> T:
        return self._resolve_fn()
