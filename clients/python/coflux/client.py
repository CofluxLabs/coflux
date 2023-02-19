import aiohttp
import asyncio
import hashlib
import importlib
import json
import time
import threading
import os
import inspect
import urllib.parse

from . import annotations, channel, future, context

BLOB_THRESHOLD = 100


def _json_dumps(obj):
    return json.dumps(obj, separators=(',', ':'))


def _load_module(name):
    module = importlib.import_module(name)
    attrs = (getattr(module, k) for k in dir(module))
    return dict(a._coflux_target for a in attrs if hasattr(a, annotations.TARGET_KEY))


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



def _future_argument(argument, client, loop, execution_id):
    tag, value = argument
    if tag == 'json':
        return future.Future(lambda: json.loads(value), argument)
    elif tag == 'blob':
        return future.Future(lambda: client._get_blob(value), argument, loop)
    elif tag == 'result':
        return future.Future(lambda: client.get_result(value, execution_id), argument, loop)
    else:
        raise Exception(f"unrecognised tag ({tag})")



class Client:
    def __init__(self, project_id, environment_name, module_name, version, server_host, concurrency=None):
        self._project_id = project_id
        self._environment_name = environment_name
        self._module_name = module_name
        self._version = version
        self._server_host = server_host
        self._targets = _load_module(module_name)
        self._channel = channel.Channel({'execute': self._handle_execute, 'abort': self._handle_abort})
        self._results = {}
        self._executions = {}
        self._semaphore = threading.Semaphore(concurrency or min(32, os.cpu_count() + 4))
        self._last_heartbeat_sent = None

    def _url(self, scheme, path, **kwargs):
        query_string = f'?{urllib.parse.urlencode(kwargs)}' if kwargs else ''
        return f'{scheme}://{self._server_host}/projects/{self._project_id}{path}{query_string}'

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

    async def _prepare_result(self, value):
        if isinstance(value, future.Future):
            return value.serialise()
        json_value = _json_dumps(value)
        if len(json_value) >= BLOB_THRESHOLD:
            key = await self._put_blob(json_value)
            return 'blob', key
        return 'json', json_value

    # TODO: combine with above
    async def _serialise_argument(self, value):
        if isinstance(value, future.Future):
            return value.serialise()
        json_value = _json_dumps(value)
        if len(json_value) >= BLOB_THRESHOLD:
            key = await self._put_blob(json_value)
            return 'blob', key
        return 'json', json_value

    async def _put_result(self, execution_id, value):
        type, value = await self._prepare_result(value)
        await self._channel.notify('put_result', execution_id, type, value)

    async def _put_cursor(self, execution_id, value):
        type, value = await self._prepare_result(value)
        await self._channel.notify('put_cursor', execution_id, type, value)

    async def _put_error(self, execution_id, exception):
        # TODO: include exception state
        await self._channel.notify('put_error', execution_id, str(exception)[:200], {})

    # TODO: consider thread safety
    def _execute_target(self, execution_id, target_name, arguments, loop):
        self._semaphore.acquire()
        self._set_execution_status(execution_id, 1)
        target = self._targets[target_name][1]
        arguments = [_future_argument(a, self, loop, execution_id) for a in arguments]
        token = context.set_execution(execution_id, self, loop)
        try:
            value = target(*arguments)
        except Exception as e:
            task = self._put_error(execution_id, e)
            asyncio.run_coroutine_threadsafe(task, loop).result()
        else:
            if inspect.isgenerator(value):
                for cursor in value:
                    if cursor is not None:
                        task = self._put_cursor(execution_id, cursor)
                        asyncio.run_coroutine_threadsafe(task, loop).result()
                    if self._executions[execution_id][2] == 3:
                        value.close()
            else:
                task = self._put_result(execution_id, value)
                asyncio.run_coroutine_threadsafe(task, loop).result()
        finally:
            del self._executions[execution_id]
            context.reset_execution(token)
            self._semaphore.release()

    async def _handle_execute(self, execution_id, target_name, arguments):
        # TODO: check execution isn't already running?
        print(f"Handling execute '{target_name}' ({execution_id})...")
        loop = asyncio.get_running_loop()
        args = (execution_id, target_name, arguments, loop)
        thread = threading.Thread(target=self._execute_target, args=args, daemon=True)
        self._executions[execution_id] = (thread, time.time(), 0)
        thread.start()

    async def _handle_abort(self, execution_id):
        print(f"Aborting execution ({execution_id})...")
        self._set_execution_status(execution_id, 3)

    def _should_send_heartbeat(self, executions, threshold_s, now):
        return executions or not self._last_heartbeat_sent or (now - self._last_heartbeat_sent) > threshold_s

    async def _send_heartbeats(self, execution_threshold_s=1, agent_threshold_s=5):
        while True:
            now = time.time()
            executions = {id: e[2] for id, e in self._executions.items() if now - e[1] > execution_threshold_s}
            if self._should_send_heartbeat(executions, agent_threshold_s, now):
                await self._channel.notify('record_heartbeats', executions)
                self._last_heartbeat_sent = now
            await asyncio.sleep(1)

    async def run(self):
        print(f"Agent starting ({self._module_name}@{self._version})...")
        async with aiohttp.ClientSession() as self._session:
            # TODO: heartbeat (and timeout) value?
            async with self._session.ws_connect(
                self._url('ws', '/agent', environment=self._environment_name),
                heartbeat=5,
            ) as websocket:
                print(f"Connected ({self._server_host}, {self._project_id}).")
                # TODO: reset channel?
                manifest = _generate_manifest(self._targets)
                await self._channel.notify('register', self._module_name, self._version, manifest)
                coros = [self._channel.run(websocket), self._send_heartbeats()]
                done, pending = await asyncio.wait(coros, return_when=asyncio.FIRST_COMPLETED)
                print("Disconnected.")
                for task in pending:
                    task.cancel()

    async def schedule_step(self, execution_id, target, arguments, repository=None, cache_key=None):
        repository = repository or self._module_name
        serialised_arguments = [await self._serialise_argument(a) for a in arguments]
        return await self._channel.request(
            'schedule_step', repository, target, serialised_arguments, execution_id, cache_key
        )

    async def schedule_task(self, execution_id, target, arguments, repository=None):
        repository = repository or self._module_name
        serialised_arguments = [await self._serialise_argument(a) for a in arguments]
        return await self._channel.request('schedule_task', repository, target, serialised_arguments, execution_id)

    async def log_message(self, execution_id, level, message):
        return await self._channel.notify('log_message', execution_id, level, message)

    def _set_execution_status(self, execution_id, status):
        thread, start_time, _status = self._executions[execution_id]
        self._executions[execution_id] = (thread, start_time, status)

    async def get_result(self, execution_id, from_execution_id):
        if execution_id not in self._results:
            self._semaphore.release()
            self._set_execution_status(from_execution_id, 2)
            self._results[execution_id] = await self._channel.request('get_result', execution_id, from_execution_id)
            self._set_execution_status(from_execution_id, 0)
            self._semaphore.acquire()
            self._set_execution_status(from_execution_id, 1)
        result = self._results[execution_id]
        if result[0] == "json":
            return json.loads(result[1])
        elif result[0] == "blob":
            return await self._get_blob(result[1])
        elif result[0] == "failed":
            # TODO: reconstruct exception state
            raise Exception(result[1])
        elif result[0] == "abandoned":
            raise Exception("abandoned")
        else:
            raise Exception(f"unexeptected result tag ({result[0]})")


def run(project, environment, module, version, host, concurrency):
    try:
        client = Client(project, environment, module, version, host, concurrency)
        asyncio.run(client.run())
    except KeyboardInterrupt:
        pass
