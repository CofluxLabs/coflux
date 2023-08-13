import asyncio
import typing as t
import websockets
import collections
import json


class Request:
    def __init__(self):
        self._event = asyncio.Event()

    def put_result(self, result: t.Any) -> None:
        self._result = result
        self._event.set()

    def put_error(self, error: t.Any) -> None:
        self._error = error
        self._event.set()

    async def get(self) -> t.Any:
        await self._event.wait()
        if hasattr(self, "_error"):
            raise Exception(self._error)
        else:
            return self._result


class Channel:
    def __init__(self, handlers: dict[str, t.Callable[..., None]]):
        self._handlers = handlers
        self._last_id = 0
        self._requests = {}
        self._session_id = None
        self._queue = collections.deque()
        self._cond = asyncio.Condition()

    async def notify(self, request: str, *params) -> None:
        await self._enqueue(request, params)

    async def request(self, request: str, *params) -> t.Any:
        id = self._next_id()
        self._requests[id] = Request()
        await self._enqueue(request, params, id)
        return await self._requests[id].get()

    async def run(self, websocket) -> None:
        coros = [self._receive(websocket), self._send(websocket)]
        _, pending = await asyncio.wait(coros, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()

    @property
    def session_id(self) -> str | None:
        return self._session_id

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
                        request.put_result(data["result"])
                    elif "error" in data:
                        request.put_error(data["error"])

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
