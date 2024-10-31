import typing as t
import json
import pickle
import abc
import io
from pathlib import Path

try:
    import pandas
except ImportError:
    pandas = None

from . import blobs, models

T = t.TypeVar("T")

_BLOB_THRESHOLD = 200


def _json_dumps(obj: t.Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


class Serialiser(abc.ABC):
    @property
    @abc.abstractmethod
    def type(self) -> str:
        raise NotImplementedError

    @abc.abstractmethod
    def serialise(self, value: t.Any) -> tuple[io.BytesIO, dict[str, t.Any]] | None:
        raise NotImplementedError

    @abc.abstractmethod
    def deserialise(self, buffer: io.BytesIO, metadata: dict[str, t.Any]) -> t.Any:
        raise NotImplementedError


class PickleSerialiser(Serialiser):
    @property
    def type(self) -> str:
        return "pickle"

    def serialise(self, value: t.Any) -> tuple[io.BytesIO, dict[str, t.Any]] | None:
        try:
            buffer = io.BytesIO()
            pickle.dump(value, buffer)
            return buffer, {"type": str(type(value))}
        except pickle.PicklingError:
            return None

    def deserialise(self, buffer: io.BytesIO, metadata: dict[str, t.Any]) -> t.Any:
        return pickle.loads(buffer.getbuffer())


class PandasSerialiser(Serialiser):
    @property
    def type(self) -> str:
        return "pandas"

    def serialise(self, value: t.Any) -> tuple[io.BytesIO, dict[str, t.Any]] | None:
        # TODO: support series
        if pandas and isinstance(value, pandas.DataFrame):
            buffer = io.BytesIO()
            value.to_parquet(buffer)
            return buffer, {
                "content_type": "application/vnd.apache.parquet",
                "shape": value.shape,
            }

    def deserialise(self, buffer: io.BytesIO, metadata: dict[str, t.Any]) -> t.Any:
        if not pandas:
            raise Exception("Pandas dependency not available")
        # TODO: check metadata["content_type"]
        return pandas.read_parquet(buffer)


def serialise(
    value: t.Any,
    serialisers: list[Serialiser],
    blob_store: blobs.Store,
) -> models.Value:
    references: list[models.Reference] = []

    def _serialise(value: t.Any) -> t.Any:
        if value is None or isinstance(value, (str, bool, int, float)):
            return value
        elif isinstance(value, list):
            return [_serialise(v) for v in value]
        elif isinstance(value, dict):
            # TODO: sort?
            return {
                "type": "dict",
                "items": [_serialise(x) for kv in value.items() for x in kv],
            }
        elif isinstance(value, set):
            # TODO: sort?
            return {
                "type": "set",
                "items": [_serialise(x) for x in value],
            }
        elif isinstance(value, models.Execution):
            # TODO: better handle id being none
            assert value.id is not None
            references.append(("execution", value.id))
            return {"type": "ref", "index": len(references) - 1}
        elif isinstance(value, models.Asset):
            references.append(("asset", value.id))
            return {"type": "ref", "index": len(references) - 1}
        elif isinstance(value, tuple):
            # TODO: include name
            return {"type": "tuple", "items": [_serialise(x) for x in value]}
        else:
            for serialiser in serialisers:
                result = serialiser.serialise(value)
                if result is not None:
                    buffer, metadata = result
                    blob_key = blob_store.put(buffer)
                    size = buffer.getbuffer().nbytes
                    references.append(
                        ("block", serialiser.type, blob_key, size, metadata)
                    )
                    return {"type": "ref", "index": len(references) - 1}
            raise Exception(f"no serialiser for type '{type(value)}'")

    data = _serialise(value)
    encoded_data = _json_dumps(data).encode()
    size = len(encoded_data)
    if size > _BLOB_THRESHOLD:
        buffer = io.BytesIO(encoded_data)
        blob_key = blob_store.put(buffer)
        return ("blob", blob_key, size, references)
    else:
        return ("raw", data, references)


def _find_serialiser(serialisers: list[Serialiser], type: str) -> Serialiser:
    serialiser = next((s for s in serialisers if s.type == type), None)
    if not serialiser:
        raise Exception(f"unrecognised serialiser ({type})")
    return serialiser


def _get_value_data(
    value: models.Value, blob_store: blobs.Store
) -> tuple[t.Any, list[models.Reference]]:
    match value:
        case ("blob", key, _, references):
            return json.load(blob_store.get(key)), references
        case ("raw", data, references):
            return data, references


def deserialise(
    value: models.Value,
    serialisers: list[Serialiser],
    blob_store: blobs.Store,
    resolve_fn: t.Callable[[int], t.Any],
    restore_fn: t.Callable[[int, Path | str | None], Path],
) -> t.Any:
    data, references = _get_value_data(value, blob_store)

    def _deserialise(data: t.Any):
        if data is None or isinstance(data, (str, bool, int, float)):
            return data
        elif isinstance(data, list):
            return [_deserialise(v) for v in data]
        elif isinstance(data, dict):
            match data["type"]:
                case "dict":
                    pairs = zip(data["items"][::2], data["items"][1::2])
                    return {_deserialise(k): _deserialise(v) for k, v in pairs}
                case "set":
                    return {_deserialise(x) for x in data["items"]}
                case "tuple":
                    return tuple(_deserialise(x) for x in data["items"])
                case "ref":
                    reference = references[data["index"]]
                    match reference:
                        case ("execution", execution_id):
                            return models.Execution(
                                lambda: resolve_fn(execution_id),
                                execution_id,
                            )
                        case ("asset", asset_id):
                            return models.Asset(
                                lambda to: restore_fn(asset_id, to), asset_id
                            )
                        case ("block", serialiser, blob_key, _size, metadata):
                            serialiser_ = _find_serialiser(serialisers, serialiser)
                            data = blob_store.get(blob_key)
                            return serialiser_.deserialise(data, metadata)
                case other:
                    raise Exception(f"unhandled data type ({other})")
        else:
            raise Exception(f"unhandled data type ({type(data)})")

    return _deserialise(data)
