import a
from python.runfiles import Runfiles

r = Runfiles.Create()


def bar() -> None:
    a.foo(1)
