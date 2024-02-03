import typing as t
import json
import re
import pickle
import tempfile
import zipfile
import os
import mimetypes
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
    paths: models.Paths,
    blob_store: blobs.Store,
    execution_dir: Path,
) -> t.Any:
    if isinstance(data, models.Execution) and data.id:
        return _do_substitution(references, data.id, existing | paths.keys())
    elif isinstance(data, Path):
        path = data.resolve()
        if not path.is_relative_to(execution_dir):
            raise Exception(f"path ({path}) not in execution directory")
        if path.is_file():
            path_str = str(path.relative_to(execution_dir))
            blob_key = blob_store.upload(path)
            (type, _) = mimetypes.guess_type(path)
            metadata = {"size": path.stat().st_size, "type": type}
        elif path.is_dir():
            path_str = str(path.relative_to(execution_dir)) + "/"
            with tempfile.NamedTemporaryFile() as temp_file:
                sizes = []
                temp_path = Path(temp_file.name)
                with zipfile.ZipFile(temp_path, "w") as zip:
                    for root, _, files in os.walk(path):
                        root = Path(root)
                        for file in files:
                            file_path = root.joinpath(file)
                            zip.write(file_path, arcname=file_path.relative_to(path))
                            sizes.append(file_path.stat().st_size)
                blob_key = blob_store.upload(temp_path)
                metadata = {"totalSize": sum(sizes), "count": len(sizes)}
        else:
            raise Exception(f"path ({path}) doesn't exist")
        return _do_substitution(
            paths, (path_str, blob_key, metadata), existing | references.keys()
        )
    elif isinstance(data, list):
        return [
            _substitute_placeholders(
                item, existing, references, paths, blob_store, execution_dir
            )
            for item in data
        ]
    elif isinstance(data, dict):
        return {
            k: _substitute_placeholders(
                v, existing, references, paths, blob_store, execution_dir
            )
            for k, v in data.items()
        }
    else:
        return data


def _replace_placeholders(
    data: t.Any,
    execution_placeholders: dict[str, models.Execution],
    path_placeholders: dict[str, Path],
):
    if isinstance(data, str):
        return execution_placeholders.get(data) or path_placeholders.get(data) or data
    elif isinstance(data, list):
        return [
            _replace_placeholders(item, execution_placeholders, path_placeholders)
            for item in data
        ]
    elif isinstance(data, dict):
        return {
            k: _replace_placeholders(v, execution_placeholders, path_placeholders)
            for k, v in data.items()
        }
    return data


def _serialise(
    data: t.Any, blob_store: blobs.Store, execution_dir: Path
) -> tuple[str, bytes, models.References, models.Paths, models.Metadata]:
    references = {}
    paths = {}
    avoid_numbers = _find_numbers(data)
    value = _substitute_placeholders(
        data, avoid_numbers, references, paths, blob_store, execution_dir
    )
    try:
        json_value = _json_dumps(value).encode()
        return "json", json_value, references, paths, {"size": len(json_value)}
    except TypeError:
        pickle_value = pickle.dumps(value)
        return "pickle", pickle_value, references, paths, {"size": len(pickle_value)}


def serialise(
    value: t.Any, blob_store: blobs.Store, execution_dir: Path
) -> models.Value:
    format, serialised, references, paths, metadata = _serialise(
        value, blob_store, execution_dir
    )
    if format != "json" or len(serialised) > _BLOB_THRESHOLD:
        key = blob_store.put(serialised)
        return ("blob", key, metadata, format, references, paths)
    return ("raw", serialised, format, references, paths)


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
    paths: models.Paths,
    resolve_fn: t.Callable[[str], t.Any],
    blob_store: blobs.Store,
    execution_dir: Path,
) -> t.Any:
    data = _deserialise(format, content)
    execution_placeholders = {
        f"{{{k}}}": models.Execution(lambda: resolve_fn(v), v)
        for k, v in references.items()
    }
    path_placeholders = {}
    for placeholder, (path, blob_key, _metadata) in paths.items():
        resolved_path = execution_dir.joinpath(path)
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        if path.endswith("/"):
            resolved_path.mkdir()
            with tempfile.NamedTemporaryFile() as temp_file:
                temp_path = Path(temp_file.name)
                blob_store.download(blob_key, temp_path)
                with zipfile.ZipFile(temp_path, "r") as zip:
                    zip.extractall(resolved_path)
        else:
            blob_store.download(blob_key, resolved_path)
        path_placeholders[f"{{{placeholder}}}"] = resolved_path
    return _replace_placeholders(data, execution_placeholders, path_placeholders)
