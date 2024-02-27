import importlib
import importlib.util
import types
from pathlib import Path


def load_module(module_name: str) -> types.ModuleType:
    path = Path(module_name)
    if path.is_file():
        spec = importlib.util.spec_from_file_location(module_name, path)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    else:
        module = importlib.import_module(module_name)
    return module
