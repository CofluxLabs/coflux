import contextvars
import functools
import importlib
import json
import websockets
import asyncio

TARGET_KEY = '_coflux_target'

execution_var = contextvars.ContextVar('execution')


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
    def __init__(self, uri, handlers):
        self._uri = uri
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

    async def connect(self):
        self._websocket = await websockets.connect(self._uri)

    async def run(self):
        coros = [self._consume(), self._produce()]
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

    async def _consume(self):
        async for message in self._websocket:
            message = json.loads(message)
            if 'method' in message:
                handler = self._handlers[message['method']]
                params = message.get('params', [])
                await handler(*params)
            else:
                request = self._requests[message['id']]
                if 'result' in message:
                    request.put_result(message['result'])
                elif 'error' in message:
                    request.put_error(message['error'])

    async def _produce(self):
        while True:
            message = await (self._queue.get())
            await self._websocket.send(json.dumps(message))


def _load_module(name):
    module = importlib.import_module(name)
    attrs = (getattr(module, k) for k in dir(module))
    return dict(a._coflux_target for a in attrs if hasattr(a, TARGET_KEY))


def _serialise_argument(argument):
    if isinstance(argument, Future):
        return argument.serialise()
    else:
        # TODO: check json-serialisable?
        return ['raw', argument]


class Client:
    def __init__(self, project_id, module_name, version, server_host):
        self._project_id = project_id
        self._module_name = module_name
        self._version = version
        self._server_host = server_host
        self._targets = _load_module(module_name)
        uri = f'ws://{self._server_host}/projects/{self._project_id}/agent'
        self._channel = Channel(uri, {'execute': self._handle_execute})
        self._results = {}
        self._executions = {}

    def _url(self, path):
        return f'http://{self._server_host}/projects/{self._project_id}{path}'

    def _future_argument(self, argument):
        tag, value = argument
        if tag == 'raw':
            return Future(lambda: value, argument)
        elif tag == 'result':
            loop = asyncio.get_running_loop()
            return Future(lambda: self.get_result(value), argument, loop)
        else:
            raise Exception(f"unrecognised tag ({tag})")

    async def _put_result(self, task, execution_id):
        try:
            value = await task
        except Exception as e:
            # TODO: include exception state
            await self._channel.notify('put_error', execution_id, str(e), {})
        else:
            type, value = value.serialise() if isinstance(value, Future) else ["raw", value]
            await self._channel.notify('put_result', execution_id, type, value)
        del self._executions[execution_id]

    async def _handle_execute(self, execution_id, target_name, arguments):
        print(f"Executing '{target_name}' ({execution_id})...")
        target = self._targets[target_name]['function']
        future_arguments = [self._future_argument(argument) for argument in arguments]
        loop = asyncio.get_running_loop()
        execution_var.set((execution_id, self, loop))
        task = asyncio.to_thread(target, *future_arguments)
        # TODO: check execution isn't already running?
        self._executions[execution_id] = task
        asyncio.create_task(self._put_result(task, execution_id))

    async def run(self):
        print(f"Agent running ({self._module_name}@{self._version}, {self._server_host}, {self._project_id})...")
        targets = {name: {'type': target['type']} for name, target in self._targets.items()}
        while True:
            await self._channel.connect()
            await self._channel.notify('register', self._module_name, self._version, targets)
            await self._channel.run()
            # TODO: backoff
            await asyncio.sleep(1)
            print(f"Disconnected. Reconnecting...")

    async def schedule_child(self, execution_id, target, arguments, repository=None):
        repository = repository or self._module_name
        serialised_arguments = [_serialise_argument(a) for a in arguments]
        return await self._channel.request('schedule_child', execution_id, repository, target, serialised_arguments)

    async def get_result(self, execution_id):
        if execution_id not in self._results:
            self._results[execution_id] = await self._channel.request('get_result', execution_id)
        result = self._results[execution_id]
        if result[0] == "raw":
            return result[1]
        elif result[0] == "failed":
            # TODO: reconstruct exception state
            raise Exception(result[1])
        else:
            raise Exception(f"unexeptected result tag ({result[0]})")


def _decorate(name=None, type='step'):
    def decorate(fn):
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, {'type': type, 'module': fn.__module__, 'function': fn}))

        @functools.wraps(fn)
        def wrapper(*args):  # TODO: support kwargs?
            execution = execution_var.get(None)
            if execution is not None:
                execution_id, client, loop = execution
                schedule = client.schedule_child(execution_id, target, args)
                new_execution_id = asyncio.run_coroutine_threadsafe(schedule, loop).result()
                return Future(lambda: client.get_result(new_execution_id), ['result', new_execution_id], loop)
            else:
                # TODO: execute in threadpool
                result = fn(*[(Future(lambda: a) if not isinstance(a, Future) else a) for a in args])
                return Future(lambda: result) if not isinstance(result, Future) else result

        return wrapper

    return decorate


def task(name=None):
    return _decorate(name, 'task')


def step(name=None):
    return _decorate(name, 'step')
