import typing as t
import json
import re
import pickle
from pathlib import Path

from . import blobs, models

T = t.TypeVar("T")

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


def _choose_number(
    existing: set[int], placeholders: dict[int, t.Any], counter=0
) -> int:
    if counter not in existing and counter not in placeholders:
        return counter
    return _choose_number(existing, placeholders, counter + 1)


def _do_substitution(substitutions: dict[int, T], value: T, existing: set[int]):
    number = next(
        (k for k, v in substitutions.items() if v == value),
        None,
    )
    if not number:
        number = _choose_number(existing, substitutions)
        substitutions[number] = value
    return f"{{{number}}}"


def _substitute_placeholders(
    data: t.Any,
    existing: set[int],
    references: models.References,
    assets: models.Assets,
) -> t.Any:
    if isinstance(data, models.Execution) and data.id:
        return _do_substitution(references, data.id, existing | assets.keys())
    elif isinstance(data, models.Asset):
        return _do_substitution(assets, data.id, existing | references.keys())
    elif isinstance(data, list):
        return [
            _substitute_placeholders(item, existing, references, assets)
            for item in data
        ]
    elif isinstance(data, dict):
        return {
            k: _substitute_placeholders(v, existing, references, assets)
            for k, v in data.items()
        }
    else:
        return data


def _replace_placeholders(
    data: t.Any,
    placeholders: dict[str, models.Execution | models.Asset],
):
    if isinstance(data, str):
        return placeholders.get(data) or data
    elif isinstance(data, list):
        return [_replace_placeholders(item, placeholders) for item in data]
    elif isinstance(data, dict):
        return {k: _replace_placeholders(v, placeholders) for k, v in data.items()}
    return data


def _serialise(
    data: t.Any, blob_store: blobs.Store, execution_dir: Path
) -> tuple[str, bytes, models.References, models.Assets, models.Metadata]:
    references = {}
    assets = {}
    avoid_numbers = _find_numbers(data)
    value = _substitute_placeholders(data, avoid_numbers, references, assets)
    try:
        json_value = _json_dumps(value).encode()
        return "json", json_value, references, assets, {"size": len(json_value)}
    except TypeError:
        pickle_value = pickle.dumps(value)
        return "pickle", pickle_value, references, assets, {"size": len(pickle_value)}


def serialise(
    value: t.Any, blob_store: blobs.Store, execution_dir: Path
) -> models.Value:
    format, serialised, references, assets, metadata = _serialise(
        value, blob_store, execution_dir
    )
    if format != "json" or len(serialised) > _BLOB_THRESHOLD:
        key = blob_store.put(serialised)
        return ("blob", key, metadata, format, references, assets)
    return ("raw", serialised, format, references, assets)


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
    references: models.References,
    assets: models.Assets,
    resolve_fn: t.Callable[[int], t.Any],
) -> t.Any:
    data = _deserialise(format, content)
    placeholders = {
        f"{{{k}}}": models.Execution(lambda: resolve_fn(v), v)
        for k, v in references.items()
    } | {f"{{{k}}}": models.Asset(v) for k, v in assets.items()}
    return _replace_placeholders(data, placeholders)
