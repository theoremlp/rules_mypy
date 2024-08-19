import cachetools
import numpy as np

cache: cachetools.Cache[str, str] = cachetools.LRUCache(maxsize=100)


def demo() -> str | None:
    value: str | None = cache.get("test")
    return value


def foo() -> None:
    print(np.__version__)
