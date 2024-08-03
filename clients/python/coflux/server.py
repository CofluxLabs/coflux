import collections
import asyncio
import json
import typing as t


class Callbacks(t.NamedTuple):
    on_success: t.Callable
    on_error: t.Callable


class Connection:
    def __init__(
        self,
        handlers: dict[str, t.Callable[..., t.Awaitable[None]]],
    ):
        self._handlers = handlers
        self._last_id = 0
        self._requests: dict[int, Callbacks] = {}
        self._session_id = None
        self._queue = collections.deque()
        self._cond = asyncio.Condition()

    @property
    def session_id(self):
        return self._session_id

    async def notify(self, request: str, params: tuple) -> None:
        await self._enqueue(request, params)

    async def request(self, request: str, params: tuple, callbacks: Callbacks) -> None:
        id = self._next_id()
        self._requests[id] = callbacks
        await self._enqueue(request, params, id)

    async def run(self, websocket) -> None:
        coros = [
            asyncio.create_task(self._receive(websocket)),
            asyncio.create_task(self._send(websocket)),
        ]
        done, pending = await asyncio.wait(coros, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        for task in done:
            task.result()

    def reset(self):
        self._session_id = None
        self._last_id = 0
        self._requests = {}

    async def _enqueue(
        self, request: str, params: tuple, id: int | None = None
    ) -> None:
        data: dict[str, t.Any] = {"request": request}
        if params:
            data["params"] = params
        if id is not None:
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
                case [2, request_id, result]:
                    self._requests[request_id].on_success(result)
                    del self._requests[request_id]
                case [3, request_id, error]:
                    self._requests[request_id].on_error(error)
                    del self._requests[request_id]

    async def _send(self, websocket) -> t.NoReturn:
        while True:
            async with self._cond:
                await self._cond.wait_for(lambda: self._queue)
                while self._queue:
                    data = self._queue.popleft()
                    try:
                        await websocket.send(json.dumps(data))
                    except Exception:
                        self._queue.appendleft(data)
                        raise
