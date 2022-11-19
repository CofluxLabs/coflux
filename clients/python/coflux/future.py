import asyncio

class Future:
    def __init__(self, resolve_fn, serialised=None, loop=None):
        self._resolve_fn = resolve_fn
        self._serialised = serialised
        self._loop = loop

    def serialise(self):
        return self._serialised

    def result(self):
        if self._loop:
            return asyncio.run_coroutine_threadsafe(self._resolve_fn(), self._loop).result()
        else:
            return self._resolve_fn()
