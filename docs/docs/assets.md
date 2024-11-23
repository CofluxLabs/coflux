# Assets

Coflux supports sharing assets between tasks. An asset can be a file or a directory.

:::note
Each task is started in a dedicated temporary directory. Assets must be persisted from, and restored to, this execution directory.
:::

## Persisting assets

'Persist' an assets by passing a path (either a `pathlib.Path`, or a string) to `cf.persist_asset(...)`. This function returns a `cf.Asset`, which can then be shared between tasks (i.e., as an argument or a result).

```python
import coflux as cf
from pathlib import Path

@cf.task()
def my_task():
    path = Path.cwd().joinpath("foo.txt")
    path.write_text("hello")
    asset = cf.persist_asset(path)
    return asset
```

## Restoring assets

An asset persisted by one task can be 'restored' by another, using `asset.restore(...)`. This returns the path where the asset has been restored:

```python
@cf.workflow()
def my_workflow():
    asset = my_task()
    path = asset.restore()
    print(path.read_text())
```

By default an asset is restored to the same path that it was persisted from. To change this, the `to` argument can be specified (as a `pathlib.Path`, or string):

```python
asset.restore(to="other/dir")
```

## Directories

Directories can be persisted/restored likewise.

The whole execution directory can be persisted by calling `persist_asset` without specifying a path:

```python
@cf.task()
def persist_all():
    Path.cwd().joinpath("foo.txt").write_text("one")
    dir = Path.cwd().joinpath("bees")
    dir.mkdir()
    dir.joinpath("bar.txt").write_text("two")
    dir.joinpath("baz.html").write_text("<b>three</b>")
    return cf.persist_asset()
```

When persisting directories, a `match` option can be passed to filter paths:

```python
cf.persist_asset(dir, match="*.txt")
```

