import typing as t

T = t.TypeVar("T")


TargetType = t.Literal["workflow", "task", "sensor"]


class Parameter(t.NamedTuple):
    name: str
    annotation: str | None
    default: str | None


class Cache(t.NamedTuple):
    params: list[int] | t.Literal[True]
    max_age: float | None
    namespace: str | None
    version: str | None


class Defer(t.NamedTuple):
    params: list[int] | t.Literal[True]


class Retries(t.NamedTuple):
    limit: int
    delay_min: int
    delay_max: int


Requires = dict[str, list[str]]


class Target(t.NamedTuple):
    type: TargetType
    parameters: list[Parameter]
    wait_for: set[int]
    cache: Cache | None
    defer: Defer | None
    delay: float
    retries: Retries | None
    memo: list[int] | bool
    requires: Requires | None
    is_stub: bool


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
