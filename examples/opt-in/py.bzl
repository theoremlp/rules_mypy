"Custom py_library rule that also runs mypy."

load("@pip_types//:types.bzl", "types")
load("@rules_mypy//mypy:mypy.bzl", "mypy")

mypy_aspect = mypy(
    # only run mypy on targets with the typecheck tag
    opt_in_tags = ["typecheck"],
    types = types,
)
