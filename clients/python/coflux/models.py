import typing as t

# TODO: use named tuples

Value = t.Union[
    tuple[t.Literal["raw"], str, bytes, dict[int, str], dict[str, t.Any]],
    tuple[t.Literal["blob"], str, str, dict[int, str], dict[str, t.Any]],
]

Result = t.Union[
    tuple[t.Literal["value"], Value],
    tuple[t.Literal["error"], str, str],
    tuple[t.Literal["abandoned"]],
    tuple[t.Literal["cancelled"]],
]
