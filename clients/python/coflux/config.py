import yaml
import functools
import pathlib
import typing as t

path = pathlib.Path("coflux.yaml")


@functools.cache
def load() -> dict[str, t.Any]:
    return _read()


def _read() -> dict[str, t.Any]:
    if not path.exists():
        return {}
    with open(path, "r") as f:
        return yaml.safe_load(f)


def write(updates: dict[str, t.Any]) -> None:
    config = _read()
    for key, value in updates.items():
        if value is not None:
            config[key] = value
        elif key in config:
            del config[key]
    with open(path, "w") as f:
        yaml.safe_dump(config, f)
    load.cache_clear()
