<p align="center">
  <img src="logo.svg" width="350" alt="Coflux" />
</p>

Coflux is an open-source workflow engine. Use it to orchestrate and observe computational workflows, defined in plain Python. Suitable for data pipelines, background tasks, chat bots.

```python
from coflux import workflow, task
import requests

@task(retries=2)
def fetch_splines(url):
    return requests.get(url).json()

@task()
def reticulate(splines):
    return list(reversed(splines))

@workflow()
def my_workflow(url):
    reticulate(fetch_splines(url))
```

Refer to the [docs](https://docs.coflux.com) for more details.
