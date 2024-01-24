import typing as t
import json
import re
import pickle

from . import future

_BLOB_THRESHOLD = 100


def _json_dumps(obj: t.Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


def _find_numbers(data: t.Any) -> set[int]:
    numbers = set()
    if isinstance(data, str):
        match = re.match(r"\{(\d+)\}", data)
        if match:
            numbers.add(int(match.group(1)))
    elif isinstance(data, (list, tuple)):
        for item in data:
            numbers.update(_find_numbers(item))
    elif isinstance(data, dict):
        for v in data.values():
            numbers.update(_find_numbers(v))
    return numbers


def _choose_number(existing: set[int], placeholders: dict[int, str], counter=0) -> int:
    if counter not in existing and counter not in placeholders:
        return counter
    return _choose_number(existing, placeholders, counter + 1)


def _substitute_placeholders(
    data: t.Any, existing: set[int], substitutions: dict[int, str]
) -> t.Any:
    if isinstance(data, future.Future) and data.execution_id:
        number = next(
            (key for key, value in substitutions.items() if value == data.execution_id),
            None,
        )
        if not number:
            number = _choose_number(existing, substitutions)
            substitutions[number] = data.execution_id
        return f"{{{number}}}"
    elif isinstance(data, list):
        return [
            _substitute_placeholders(item, existing, substitutions) for item in data
        ]
    elif isinstance(data, dict):
        return {
            k: _substitute_placeholders(v, existing, substitutions)
            for k, v in data.items()
        }
    else:
        return data


def _replace_placeholders(
    data: t.Any, placeholders: dict[str, str], resolve_fn: t.Callable[[str], t.Any]
):
    if isinstance(data, str) and data in placeholders:
        execution_id = placeholders[data]
        return future.Future(lambda: resolve_fn(execution_id), execution_id)
    elif isinstance(data, list):
        return [_replace_placeholders(item, placeholders, resolve_fn) for item in data]
    elif isinstance(data, dict):
        return {
            k: _replace_placeholders(v, placeholders, resolve_fn)
            for k, v in data.items()
        }
    return data


def serialise(data: t.Any) -> tuple[str, bytes, dict[int, str], dict[str, t.Any]]:
    placeholders = {}
    avoid_numbers = _find_numbers(data)
    value = _substitute_placeholders(data, avoid_numbers, placeholders)
    try:
        json_value = _json_dumps(value).encode()
        return "json", json_value, placeholders, {"size": len(json_value)}
    except TypeError:
        pickle_value = pickle.dumps(value)
        return "pickle", pickle_value, placeholders, {"size": len(pickle_value)}


def _deserialise(format: str, content: bytes):
    match format:
        case "json":
            return json.loads(content.decode())
        case "pickle":
            return pickle.loads(content)
        case format:
            raise Exception(f"unsupported format ({format})")


def deserialise(
    format: str,
    content: bytes,
    references: dict[int, str],
    resolve_fn: t.Callable[[str], t.Any],
) -> t.Any:
    data = _deserialise(format, content)
    placeholders = {f"{{{k}}}": v for k, v in references.items()}
    return _replace_placeholders(data, placeholders, resolve_fn)
