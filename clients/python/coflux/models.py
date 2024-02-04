import typing as t

T = t.TypeVar("T")

# TODO: use named tuples

Metadata = dict[str, t.Any]

Placeholders = dict[int, tuple[int, None] | tuple[None, int]]

Value = t.Union[
    tuple[t.Literal["raw"], bytes, str, Placeholders],
    tuple[t.Literal["blob"], str, Metadata, str, Placeholders],
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
        id: int | None,
    ):
        self._resolve_fn = resolve_fn
        self._id = id

    @property
    def id(self) -> int | None:
        return self._id

    def result(self) -> T:
        return self._resolve_fn()


class Asset(t.NamedTuple):
    id: int
