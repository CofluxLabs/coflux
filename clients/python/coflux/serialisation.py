import typing as t
import json
import pickle
import abc
import io
from pathlib import Path
import pydantic
import importlib

try:
    import pandas
except ImportError:
    pandas = None

from . import blobs, models, config

T = t.TypeVar("T")


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


class PydanticSerialiser(Serialiser):
    @property
    def type(self) -> str:
        return "pydantic"

    def serialise(self, value: t.Any) -> tuple[io.BytesIO, dict[str, t.Any]] | None:
        if not isinstance(value, pydantic.BaseModel):
            return None
        buffer = io.BytesIO()
        json_data = value.model_dump_json().encode()
        buffer.write(json_data)
        model_class = value.__class__
        return buffer, {
            "content_type": "application/json",
            "model": f"{model_class.__module__}.{model_class.__name__}",
        }

    def deserialise(self, buffer: io.BytesIO, metadata: dict[str, t.Any]) -> t.Any:
        json_data = buffer.read().decode()
        model = metadata["model"]
        module_name, class_name = model.rsplit(".", 1)
        # TODO: support configuring which modules can be loaded?
        module = importlib.import_module(module_name)
        model_class = getattr(module, class_name)
        if not model_class:
            raise ValueError(f"Model '{model}' not found")
        if not issubclass(model_class, pydantic.BaseModel):
            raise ValueError(f"Model '{model}' isn't a subclass of BaseModel")
        return model_class.model_validate_json(json_data)


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


def _create(config_: config.SerialiserConfig):
    if config_.type == "pickle":
        return PickleSerialiser()
    elif config_.type == "pydantic":
        return PydanticSerialiser()
    elif config_.type == "pandas":
        return PandasSerialiser()
    else:
        raise ValueError("unrecognised serialiser config")


class Manager:
    def __init__(
        self,
        serialiser_configs: list[config.SerialiserConfig],
        blob_threshold: int,
        blob_manager: blobs.Manager,
    ):
        self._serialisers = [_create(c) for c in serialiser_configs]
        self._blob_threshold = blob_threshold
        self._blob_manager = blob_manager

    def serialise(self, value: t.Any) -> models.Value:
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
                for serialiser in self._serialisers:
                    result = serialiser.serialise(value)
                    if result is not None:
                        buffer, metadata = result
                        blob_key = self._blob_manager.put(buffer)
                        size = buffer.getbuffer().nbytes
                        references.append(
                            ("fragment", serialiser.type, blob_key, size, metadata)
                        )
                        return {"type": "ref", "index": len(references) - 1}
                raise Exception(f"no serialiser for type '{type(value)}'")

        data = _serialise(value)
        encoded_data = _json_dumps(data).encode()
        size = len(encoded_data)
        if size > self._blob_threshold:
            buffer = io.BytesIO(encoded_data)
            blob_key = self._blob_manager.put(buffer)
            return ("blob", blob_key, size, references)
        else:
            return ("raw", data, references)

    def _find_serialiser(self, type: str) -> Serialiser:
        serialiser = next((s for s in self._serialisers if s.type == type), None)
        if not serialiser:
            raise Exception(f"unrecognised serialiser ({type})")
        return serialiser

    def _get_value_data(
        self, value: models.Value
    ) -> tuple[t.Any, list[models.Reference]]:
        match value:
            case ("blob", key, _, references):
                result = self._blob_manager.get(key)
                return json.load(result), references
            case ("raw", data, references):
                return data, references

    def deserialise(
        self,
        value: models.Value,
        resolve_fn: t.Callable[[int], t.Any],
        restore_fn: t.Callable[[int, Path | str | None], Path],
    ) -> t.Any:
        data, references = self._get_value_data(value)

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
                            case ("fragment", serialiser, blob_key, _size, metadata):
                                serialiser_ = self._find_serialiser(serialiser)
                                data = self._blob_manager.get(blob_key)
                                return serialiser_.deserialise(data, metadata)
                    case other:
                        raise Exception(f"unhandled data type ({other})")
            else:
                raise Exception(f"unhandled data type ({type(data)})")

        return _deserialise(data)
