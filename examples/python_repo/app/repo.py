import time
import random
import requests
import typing as t

from coflux import step, task, sensor, context


@step()
def count(xs):
    return len(xs.result())


@step()
def inc(x):
    return x.result() + 1


@step()
def add(x: int, y: int) -> int:
    context.log_debug("This is a debug message")
    return x.result() + y.result()


@step()
def foo(xs: t.List[int]):
    context.log_warning("This is a warning message")
    return inc(count(xs))


@step()
def maximum(xs: t.List[int]):
    context.log_error("This is an error message")
    return max(xs.result())


@task()
def my_task(xs: t.Optional[t.List[int]] = None):
    xs = xs or [5, 2, 6]
    context.log_info("Task has started")
    return add(foo(xs), maximum(xs))


@step(cache_key_fn=lambda n: f"app.repo:fib:{n}")
def fib(n: int):
    n = n.result()
    if n == 0 or n == 1:
        return n
    else:
        return fib(n - 1).result() + fib(n - 2).result()


@task()
def fib_task(n: int):
    return fib(n.result())


@step()
def do_raise():
    context.log_warning("Raising...")
    raise Exception("some error")


@step()
def maybe_raise():
    if random.random() > 0.5:
        context.log_error("Raising exception...")
        raise Exception("some error")
    else:
        context.log_debug("Not going to raise.")
        return 123


@task()
def raise_task():
    do_raise()
    return maybe_raise().result()


@step()
def sleep(seconds):
    time.sleep(seconds.result())


@task()
def slow_task():
    sleep(0.5)
    sleep(1)
    sleep(5)
    sleep(2).result()
    sleep(10)


@step()
def choose_random(i: int):
    choice = random.randint(0, 12)
    context.log_info(f"Choice: {choice}")
    if choice == 0:
        random_task(random.randint(1, 4))
    elif choice == 1:
        maybe_raise()
    elif choice <= 4:
        for j in range(choice):
            choose_random(j)
    elif choice <= 6:
        sleep(choice)
    elif choice == 7:
        maximum(list(range(min(2, i.result()))))
    elif choice == 8:
        build_content()
    elif choice == 9:
        github_events()
    else:
        fib(choice)


@task()
def random_task(n: int = 5):
    n = n.result()
    for i in range(n):
        choose_random(i)


@step()
def build_content():
    return '1234567890' * 10


@task()
def blob_task():
    return count(build_content())


@step()
def github_events():
    context.log_debug("Requesting events...")
    r = requests.get('https://api.github.com/events')
    r.raise_for_status()
    context.log_debug(f"Elapsed: {r.elapsed}")
    return r.json()


@task()
def github_task():
    events = github_events().result()
    return len(events)


@sensor()
def demo_sensor(cursor: t.Optional[int]):
    interval = 10
    cursor = (cursor.result() if cursor else None)
    cursor = cursor or time.time()
    while True:
        remaining = max(0, cursor - time.time())
        time.sleep(remaining)
        yield
        my_task()
        cursor += interval
        yield cursor


if __name__ == '__main__':
    print(my_task([1, 2, 3, 4]).result())
