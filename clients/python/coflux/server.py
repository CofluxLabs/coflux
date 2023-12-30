import collections
import asyncio
import json
import typing as t


class Connection:
    def __init__(
        self,
        handlers: dict[str, t.Callable[..., None]],
    ):
        self._handlers = handlers
        self._last_id = 0
        self._requests: dict[int, t.Callable] = {}
        self._session_id = None
        self._queue = collections.deque()
        self._cond = asyncio.Condition()

    @property
    def session_id(self):
        return self._session_id

    async def notify(self, request: str, params: tuple) -> None:
        await self._enqueue(request, params)

    async def request(
        self, request: str, params: tuple, callback: t.Callable
    ) -> asyncio.Future:
        id = self._next_id()
        self._requests[id] = callback
        await self._enqueue(request, params, id)

    async def run(self, websocket) -> None:
        coros = [self._receive(websocket), self._send(websocket)]
        _, pending = await asyncio.wait(coros, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()

    def reset(self):
        self._session_id = None
        self._last_id = 0
        for callback in self._requests.values():
            # TODO: more explicit indicator of error?
            callback(Exception("Session reset"))
        self._requests = {}

    async def _enqueue(
        self, request: str, params: tuple, id: str | None = None
    ) -> None:
        data = {"request": request}
        if params:
            data["params"] = params
        if id:
            data["id"] = id
        async with self._cond:
            self._queue.append(data)
            self._cond.notify()

    def _next_id(self) -> int:
        self._last_id += 1
        return self._last_id

    async def _receive(self, websocket) -> None:
        async for message in websocket:
            match json.loads(message):
                case [0, session_id]:
                    self._session_id = session_id
                case [1, data]:
                    handler = self._handlers[data["command"]]
                    params = data.get("params", [])
                    await handler(*params)
                case [2, data]:
                    request = self._requests[data["id"]]
                    if "result" in data:
                        request(data["result"])
                    elif "error" in data:
                        request(Exception(data["error"]))
                    del self._requests[data["id"]]

    async def _send(self, websocket) -> t.NoReturn:
        while True:
            async with self._cond:
                await self._cond.wait_for(lambda: self._queue)
                while self._queue:
                    data = self._queue.popleft()
                    try:
                        await websocket.send(json.dumps(data))
                    except Exception as e:
                        self._queue.appendleft(data)
                        raise
