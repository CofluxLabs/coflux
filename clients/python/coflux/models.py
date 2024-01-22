import typing as t

Value = t.Union[
    tuple[t.Literal["raw"], str, str],
    tuple[t.Literal["blob"], str, str, dict[str, t.Any]],
    tuple[t.Literal["reference"], str],
]

Error = t.Union[
    tuple[t.Literal["error"], str],
    tuple[t.Literal["abandoned"]],
    tuple[t.Literal["cancelled"]],
]

Result = Value | Error
