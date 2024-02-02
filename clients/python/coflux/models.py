import typing as t

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
