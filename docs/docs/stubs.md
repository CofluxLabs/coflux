# Stubs

A stub allows you to define a reference to a step that's in another repository (in a separate codebase). It's like 'importing' an external task.

For example, given an `other.repo` repository with a random number generator:

```python
# other/repo.py

@cf.task()
def random_int(max: int) -> int:
    return random.randint(1, max)
```

Another repository could reference this function with a stub, and then call it:

```python
# example/repo.py

@cf.stub("other.repo")
def random_int(max: int) -> int:
    ...

@cf.workflow()
def roll_die():
    if random_int(6).result() == 6:
        print("You won")
    else:
        print("You lost")
```

## Stub implementations

When you call the stub in the context of a workflow, the function itself won't be executed, so the body of the function isn't important. However, being able to implement the function is useful when you want to be able to run your code outside of the context of a workflow. For example, as part of a test, you could return some dummy data.

```python
@cf.stub("other.repo")
def random_int(max: int) -> int:
    return 4  # dummy value for testing
```

