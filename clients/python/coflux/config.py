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


def write(config) -> None:
    new_config = {**_read(), **config}
    with open(path, "w") as f:
        yaml.safe_dump(new_config, f)
    load.cache_clear()
