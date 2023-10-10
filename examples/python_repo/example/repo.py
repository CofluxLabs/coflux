import time
import random
import requests
import typing as t

from coflux import step, task, stub, sensor, context, Future


@step()
def count(xs: list[int]) -> int:
    return len(xs)


@step()
def inc(x: Future[int]) -> int:
    return x + 1


@step()
def add(x: Future[int], y: Future[int]) -> int:
    context.log_debug("This is a debug message")
    return x + y


@step()
def foo(xs: t.List[int]) -> Future[int]:
    context.log_warning("This is a warning message")
    return inc(count(xs))


@step()
def maximum(xs: t.List[int]) -> int:
    context.log_error("This is an error message")
    return max(xs)


@task()
def my_task(xs: t.Optional[t.List[int]] = None) -> Future[int]:
    xs = xs or [5, 2, 6]
    context.log_info("Task has started")
    return add(foo(xs), maximum(xs))


@step(cache=True)
def fib(n: int) -> int:
    if n == 0 or n == 1:
        return n
    else:
        return fib(n - 1) + fib(n - 2)


@task()
def fib_task(n: int):
    return fib(n)


@step(retries=(3, 1, 3))
def do_raise():
    context.log_warning("Raising...")
    raise Exception("some error")


@step(retries=(3, 1, 3))
def maybe_raise() -> int:
    if random.random() > 0.5:
        context.log_error("Raising exception...")
        raise Exception("some error")
    else:
        context.log_debug("Not going to raise.")
        return 123


@task()
def raise_task():
    do_raise.submit()
    maybe_raise.submit()


@step()
def sleep(seconds: float) -> None:
    time.sleep(seconds)


@task()
def slow_task():
    sleep.submit(0.5)
    sleep.submit(1)
    sleep.submit(5)
    sleep(2)
    sleep.submit(10)


@step()
def choose_random(i: int) -> None:
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
        sleep.submit(choice)
    elif choice == 7:
        maximum(list(range(min(2, i))))
    elif choice == 8:
        build_content()
    elif choice == 9:
        github_events()
    else:
        fib(choice)


@task()
def random_task(n: int = 5) -> None:
    for i in range(n):
        choose_random(i)


@step()
def build_content() -> str:
    return "1234567890" * 10


@task()
def blob_task():
    return count(build_content())


@step()
def github_events():
    context.log_debug("Requesting events...")
    r = requests.get("https://api.github.com/events")
    r.raise_for_status()
    context.log_debug(f"Elapsed: {r.elapsed}")
    return r.json()


@task()
def github_task():
    events = github_events()
    return len(events)


@sensor()
def demo_sensor(cursor: int | None = None):
    interval = 10
    cursor = cursor or time.time()
    while True:
        remaining = max(0, cursor - time.time())
        time.sleep(remaining)
        yield
        my_task()
        cursor += interval
        yield cursor


@stub("example2.repo2")
def random_int(max: int):
    return 42


@task()
def another_task():
    return random_int(10) + 1


if __name__ == "__main__":
    print(my_task([1, 2, 3, 4]))
