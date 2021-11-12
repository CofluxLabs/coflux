import time
import random
import requests

from coflux import step, task


@step()
def count(xs):
    return len(xs.result())


@step()
def inc(x):
    return x.result() + 1


@step()
def add(x, y):
    return x.result() + y.result()


@step()
def foo(xs):
    return inc(count(xs))


@step()
def maximum(xs):
    return max(xs.result())


@task()
def my_task(xs=None):
    xs = xs or [5, 2, 6]
    return add(foo(xs), maximum(xs))


@task()
def fib(n):
    n = n.result()
    if n == 0 or n == 1:
        return n
    else:
        return fib(n - 1).result() + fib(n - 2).result()


@step()
def do_raise():
    raise Exception("some error")


@step()
def maybe_raise():
    if random.random() > 0.5:
        raise Exception("some error")
    else:
        return 123


@task()
def raise_error():
    do_raise()
    return maybe_raise().result()


@step()
def sleep(seconds):
    time.sleep(seconds.result())


@task()
def slow_task():
    sleep(0.5)
    sleep(1.5)
    sleep(2).result()


@task()
def random_task():
    for i in range(random.randint(3, 5)):
        fn, *args = random.choice(
            [
                (raise_error,),
                (maximum, list(range(i))),
                (fib, 3),
                (inc, i),
                (sleep, i),
                (my_task,),
                (blob_task,),
                (github_task,),
                (random_task,),
            ]
        )
        fn(*args)


@step()
def build_content():
    return '1234567890' * 10


@task()
def blob_task():
    return len(build_content().result())


@step()
def github_events():
    r = requests.get('https://api.github.com/events')
    return r.json()


@task()
def github_task():
    events = github_events().result()
    return len(events)


if __name__ == '__main__':
    print(my_task([1, 2, 3, 4]).result())
