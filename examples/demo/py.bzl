"Custom py_library rule that also runs mypy."

load("@pip_types//:types.bzl", "types")
load("@rules_mypy//mypy:mypy.bzl", "decorate")
load("@rules_python//python:py_library.bzl", rules_python_py_library = "py_library")

py_library = decorate(
    py_target = rules_python_py_library,
    types = types,
)
