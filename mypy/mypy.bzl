"Public API for interacting with the mypy rule."

load("//mypy/private:mypy.bzl", _mypy = "mypy", _mypy_cli = "mypy_cli")

# re-export mypy macro
mypy = _mypy

# export custom mypy_cli producer
mypy_cli = _mypy_cli

def _expand(deps, types):
    deps = deps or []
    types = types or {}

    return deps + [
        types[dep]
        for dep in deps
        if dep in types
    ]

def decorate(py_target, mypy_ini = None, mypy_cli = None, types = None, filter = None):  # buildifier: disable=unnamed-macro
    """
    Decorate a py_binary, py_library or py_test rule/macro by adding an additional mypy target.

    Typical usage:
    ```
    load("@rules_python//python:py_library.bzl", rules_python_py_library = "py_library")
    py_library = decorate(rules_python_py_library)
    ```

    Args:
        py_target: a py_library or py_binary rule/macro to decorate with mypy
        mypy_ini:  (optional) label of a mypy.ini file to use to configure mypy
        mypy_cli:  (optional) a replacement mypy_cli to use (recommended to produce
                    with mypy_cli macro)
        types:     (optional) a dict of dependency label to types dependency label
                    example:
                    ```
                    {
                        requirement("cachetools"): requirement("types-cachetools"),
                    }
                    ```
                    Use the types extension to create this map for a requirements.in
                    or requirements.txt file.
        filter:    (optional) a filter function that accepts a label and returns
                    True if the label should not be used to find upstream caches.

    Returns: a decorated py_target.
    """

    def decorated_py_target(name, srcs = None, deps = None, **kwargs):
        py_target(
            name = name,
            srcs = srcs,
            deps = deps,
            **kwargs
        )

        mypy(
            name = name + ".mypy",
            srcs = srcs,
            deps = _expand(deps, types),
            mypy_ini = mypy_ini,
            mypy_cli = mypy_cli,
            visibility = kwargs.get("visibility"),
            testonly = kwargs.get("testonly"),
            tags = kwargs.get("tags"),
            filter = filter,
        )

    return decorated_py_target
