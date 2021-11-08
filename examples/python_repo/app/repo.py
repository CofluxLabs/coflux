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


@step()
def fib(n):
    n = n.result()
    if n == 0 or n == 1:
        return n
    else:
        return fib(n - 1).result() + fib(n - 2).result()


if __name__ == '__main__':
    print(my_task([1, 2, 3, 4]).result())
