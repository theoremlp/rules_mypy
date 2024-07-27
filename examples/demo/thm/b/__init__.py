import cachetools

cache: cachetools.Cache[str, str] = cachetools.LRUCache(maxsize=100)


def demo() -> str | None:
    value: str | None = cache.get("test")
    return value
