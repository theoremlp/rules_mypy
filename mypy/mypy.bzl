"Public API for interacting with the mypy rule."

load("//mypy/private:mypy.bzl", _mypy = "mypy", _mypy_cli = "mypy_cli")

# re-export mypy aspect factory
mypy = _mypy

# export custom mypy_cli producer
mypy_cli = _mypy_cli
