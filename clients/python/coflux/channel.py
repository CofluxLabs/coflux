import asyncio
import functools
import json

class Request:
    def __init__(self):
        self._event = asyncio.Event()

    def put_result(self, result):
        self._result = result
        self._event.set()

    def put_error(self, error):
        self._error = error
        self._event.set()

    async def get(self):
        await self._event.wait()
        if hasattr(self, '_error'):
            raise Exception(self._error)
        else:
            return self._result


class Channel:
    def __init__(self, handlers):
        self._handlers = handlers
        self._last_id = 0
        self._requests = {}

    async def notify(self, method, *params):
        await self._send(method, params)

    async def request(self, method, *params):
        id = self._next_id()
        self._requests[id] = Request()
        await self._send(method, params, id)
        return await self._requests[id].get()

    async def run(self, websocket):
        coros = [self._consume(websocket), self._produce(websocket)]
        done, pending = await asyncio.wait(coros, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()

    async def _send(self, method, params, id=None):
        data = {'method': method}
        if params:
            data['params'] = params
        if id:
            data['id'] = id
        await (self._queue.put(data))

    @functools.cached_property
    def _queue(self):
        return asyncio.Queue()

    def _next_id(self):
        self._last_id += 1
        return self._last_id

    async def _consume(self, websocket):
        async for message in websocket:
            data = json.loads(message.data)
            if 'method' in data:
                handler = self._handlers[data['method']]
                params = data.get('params', [])
                await handler(*params)
            else:
                request = self._requests[data['id']]
                if 'result' in data:
                    request.put_result(data['result'])
                elif 'error' in data:
                    request.put_error(data['error'])

    async def _produce(self, websocket):
        while True:
            data = await (self._queue.get())
            await websocket.send_str(json.dumps(data))
