import aiohttp
import asyncio
import contextvars
import functools
import hashlib
import importlib
import json
import time
import typing as t
import inspect

TARGET_KEY = '_coflux_target'
BLOB_THRESHOLD = 100

execution_var = contextvars.ContextVar('execution')


def _json_dumps(obj):
    return json.dumps(obj, separators=(',', ':'))


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
            await websocket.send_str(_json_dumps(data))


def _load_module(name):
    module = importlib.import_module(name)
    attrs = (getattr(module, k) for k in dir(module))
    return dict(a._coflux_target for a in attrs if hasattr(a, TARGET_KEY))


def _serialise_argument(argument):
    if isinstance(argument, Future):
        return argument.serialise()
    else:
        return ['json', _json_dumps(argument)]


def _manifest_parameter(parameter):
    result = {'name': parameter.name}
    if parameter.annotation != inspect.Parameter.empty:
        result['annotation'] = str(parameter.annotation)  # TODO: better way to serialise?
    if parameter.default != inspect.Parameter.empty:
        result['default'] = _json_dumps(parameter.default)
    return result


def _generate_manifest(targets):
    return {
        name: {
            'type': type,
            'parameters': [_manifest_parameter(p) for p in inspect.signature(fn).parameters.values()],
        }
        for name, (type, fn) in targets.items()
    }


class Execution(t.NamedTuple):
    task: t.Coroutine
    start_time: float
    status: int


class Client:
    def __init__(self, project_id, module_name, version, server_host):
        self._project_id = project_id
        self._module_name = module_name
        self._version = version
        self._server_host = server_host
        self._targets = _load_module(module_name)
        self._channel = Channel({'execute': self._handle_execute})
        self._results = {}
        self._executions = {}

    def _url(self, scheme, path):
        return f'{scheme}://{self._server_host}/projects/{self._project_id}{path}'

    def _future_argument(self, argument, loop, execution_id):
        tag, value = argument
        if tag == 'json':
            return Future(lambda: json.loads(value), argument)
        elif tag == 'blob':
            return Future(lambda: self._get_blob(value), argument, loop)
        elif tag == 'result':
            return Future(lambda: self.get_result(value, execution_id), argument, loop)
        else:
            raise Exception(f"unrecognised tag ({tag})")

    async def _get_blob(self, key):
        # TODO: make blob url configurable
        async with self._session.get(self._url('http', f'/blobs/{key}')) as resp:
            resp.raise_for_status()
            return await resp.json()

    async def _put_blob(self, content):
        key = hashlib.sha256(content.encode()).hexdigest()
        # TODO: make blob url configurable
        # TODO: check whether already uploaded (using head request)?
        async with self._session.put(self._url('http', f'/blobs/{key}'), data=content) as resp:
            resp.raise_for_status()
        return key

    async def _put_result(self, task, execution_id):
        try:
            value = await task
        except Exception as e:
            # TODO: include exception state
            await self._channel.notify('put_error', execution_id, str(e), {})
        else:
            if isinstance(value, Future):
                type, value = value.serialise()
            else:
                json_value = _json_dumps(value)
                if len(json_value) >= BLOB_THRESHOLD:
                    key = await self._put_blob(json_value)
                    type, value = "blob", key
                else:
                    type, value = "json", json_value
            await self._channel.notify('put_result', execution_id, type, value)
        del self._executions[execution_id]

    async def _handle_execute(self, execution_id, target_name, arguments):
        print(f"Executing '{target_name}' ({execution_id})...")
        target = self._targets[target_name][1]
        loop = asyncio.get_running_loop()
        future_arguments = [self._future_argument(argument, loop, execution_id) for argument in arguments]
        execution_var.set((execution_id, self, loop))
        task = asyncio.to_thread(target, *future_arguments)
        # TODO: check execution isn't already running?
        self._executions[execution_id] = Execution(task, time.time(), 0)
        asyncio.create_task(self._put_result(task, execution_id))

    async def _send_heartbeats(self, threshold_s=1):
        while True:
            now = time.time()
            executions = {id: e.status for id, e in self._executions.items() if now - e.start_time > threshold_s}
            if executions:
                await self._channel.notify('record_heartbeats', executions)
            await asyncio.sleep(1)

    async def run(self):
        print(f"Agent starting ({self._module_name}@{self._version})...")
        async with aiohttp.ClientSession() as self._session:
            # TODO: heartbeat (and timeout) value?
            async with self._session.ws_connect(self._url('ws', '/agent'), heartbeat=5) as websocket:
                print(f"Connected ({self._server_host}, {self._project_id}).")
                # TODO: reset channel?
                manifest = _generate_manifest(self._targets)
                await self._channel.notify('register', self._module_name, self._version, manifest)
                coros = [self._channel.run(websocket), self._send_heartbeats()]
                done, pending = await asyncio.wait(coros, return_when=asyncio.FIRST_COMPLETED)
                print("Disconnected.")
                for task in pending:
                    task.cancel()

    async def schedule_child(self, execution_id, target, arguments, repository=None, cache_key=None):
        repository = repository or self._module_name
        serialised_arguments = [_serialise_argument(a) for a in arguments]
        return await self._channel.request(
            'schedule_child', execution_id, repository, target, serialised_arguments, cache_key
        )

    def _set_execution_status(self, execution_id, status):
        self._executions[execution_id] = self._executions[execution_id]._replace(status=status)

    async def get_result(self, execution_id, from_execution_id):
        if execution_id not in self._results:
            self._set_execution_status(from_execution_id, 1)
            self._results[execution_id] = await self._channel.request('get_result', execution_id, from_execution_id)
            self._set_execution_status(from_execution_id, 0)
        result = self._results[execution_id]
        if result[0] == "json":
            return json.loads(result[1])
        elif result[0] == "blob":
            return await self._get_blob(result[1])
        elif result[0] == "failed":
            # TODO: reconstruct exception state
            raise Exception(result[1])
        else:
            raise Exception(f"unexeptected result tag ({result[0]})")


def _decorate(name, type, cache_key_fn=None):
    def decorate(fn):
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, (type, fn)))

        @functools.wraps(fn)
        def wrapper(*args):  # TODO: support kwargs?
            execution = execution_var.get(None)
            if execution is not None:
                execution_id, client, loop = execution
                # TODO: pass more context? (repository, name, ?)
                # TODO: handle args being futures?
                cache_key = cache_key_fn(*args) if cache_key_fn else None
                schedule = client.schedule_child(execution_id, target, args, cache_key=cache_key)
                new_execution_id = asyncio.run_coroutine_threadsafe(schedule, loop).result()
                return Future(
                    lambda: client.get_result(new_execution_id, execution_id), ['result', new_execution_id], loop
                )
            else:
                # TODO: execute in threadpool
                result = fn(*[(Future(lambda: a) if not isinstance(a, Future) else a) for a in args])
                return Future(lambda: result) if not isinstance(result, Future) else result

        return wrapper

    return decorate


def task(name=None):
    return _decorate(name, 'task')


def step(name=None, cache_key_fn=None):
    return _decorate(name, 'step', cache_key_fn)
