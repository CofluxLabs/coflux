import random
import coflux


@coflux.task()
def random_task():
    return random_int(100)


@coflux.step()
def random_int(max: int):
    return random.randint(1, max)
