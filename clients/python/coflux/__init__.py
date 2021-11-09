import contextvars
import functools
import importlib
import json
import httpx
import traceback
import concurrent.futures as cf

TARGET_KEY = '_coflux_target'

execution_var = contextvars.ContextVar('execution')


class Future:
    def __init__(self, resolve_fn, serialised=None):
        self._resolve_fn = resolve_fn
        self._serialised = serialised

    def serialise(self):
        return self._serialised

    def result(self):
        return self._resolve_fn()


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
    def __init__(self, project_id, module_name, server_host):
        self._project_id = project_id
        self._targets = _load_module(module_name)
        self._server_host = server_host
        self._executor = cf.ThreadPoolExecutor()
        self._results = {}

    def _url(self, path):
        return f'http://{self._server_host}/projects/{self._project_id}{path}'

    def _future_argument(self, argument):
        tag, value = argument
        if tag == 'raw':
            return Future(lambda: value, argument)
        elif tag == 'res':
            return Future(lambda: self.get_result(value), argument)
        else:
            raise Exception(f"unrecognised tag ({tag})")

    def _handle_execute(self, execution_id, target_name, arguments):
        print(f"Executing '{target_name}' ({execution_id})...")
        future_arguments = [self._future_argument(argument) for argument in arguments]
        execution_var.set((execution_id, self))
        try:
            value = self._targets[target_name]['function'](*future_arguments)
        except BaseException as e:
            traceback.print_exc()
            result = {'status': 'failed', 'message': str(e)}
        else:
            result = {'status': 'completed', 'value': _serialise_argument(value)}
        response = httpx.put(self._url(f'/executions/{execution_id}/result'), json=result, verify=False)
        response.raise_for_status()

    def _handle(self, command, arguments):
        if command == 'execute':
            self._handle_execute(arguments["executionId"], arguments["target"], arguments["arguments"])
        else:
            raise Exception(f"Received unrecognised command: {command}")

    def run(self):
        print(f"Agent running ({self._project_id}, {self._server_host})...")
        targets = {name: {'type': target['type']} for name, target in self._targets.items()}
        while True:
            with httpx.stream('POST', self._url('/agents'), json={'targets': targets}, verify=False) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if line.strip():
                        command, arguments = json.loads(line)
                        self._executor.submit(self._handle, command, arguments)

    def schedule(self, target, arguments, execution_id=None):
        serialised_arguments = [_serialise_argument(a) for a in arguments]
        execution = {'target': target, 'arguments': serialised_arguments}
        response = httpx.post(self._url(f'/executions/{execution_id}/children'), json=execution, verify=False)
        response.raise_for_status()
        return response.json()["executionId"]

    def get_result(self, execution_id):
        if execution_id not in self._results:
            response = httpx.get(self._url(f'/executions/{execution_id}/result'), verify=False)
            response.raise_for_status()
            self._results[execution_id] = response.json()
        result = self._results[execution_id]
        if result["status"] == "completed":
            tag, value = result["value"]
            if tag == "raw":
                return value
            else:
                raise Exception(f"unexpected tag ({tag})")
        elif result["status"] == "failed":
            # TODO: somehow reconstruct exception?
            raise Exception(result["message"])


def _decorate(name=None, type='step'):
    def decorate(fn):
        target = name or fn.__name__
        setattr(fn, TARGET_KEY, (target, {'type': type, 'module': fn.__module__, 'function': fn}))

        @functools.wraps(fn)
        def wrapper(*args):  # TODO: support kwargs?
            execution = execution_var.get(None)
            if execution is not None:
                execution_id, client = execution
                new_execution_id = client.schedule(target, args, execution_id)
                return Future(lambda: client.get_result(new_execution_id), ['res', new_execution_id])
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
