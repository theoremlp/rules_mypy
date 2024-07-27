# rules_mypy

Bazel rules to decorate `py_*` targets with mypy type-checking.

Compared to [bazel-mypy-integration](https://github.com/bazel-contrib/bazel-mypy-integration), this ruleset aims to make a couple of improvements:

- Propagation of the mypy cache between dependencies within a repository to avoid exponential type-checking work
- Robust (and automated) support for including 3rd party types/stubs packages

To propagate the mypy cache between targets, this ruleset uses build actions, which comes with a couple of trade-offs compared to bazel-mypy-integration:

- Compared to running as an aspect, the targets produced by these rules will not run automatically when building the primary target, which may create usability trouble in some developer cycles
- Compared to running as a test, the targets produced by these rules can fail a broad build phase, which may be undesirable in some setups

We should note that the community might prefer to treat mypy semantically as a test rather than a build action, and these rules do not enable that.

Instead, we take the opinion that type-checking is a build-time action, and the actions that are executed here take as input source files and as output produce mypy caches.

> [!WARNING]  
> rules_mypy's build actions produce mypy caches as outputs, and these may contain large file counts and that will only grow as a dependency chain grows. This may have an impact on the size and usage of build and/or remote caches.

## Usage

Whenever you define a `py_binary`, `py_library` or `py_test` using the rules_mypy decorated forms, rules_mypy defines a sibling target `[name].mypy`. Building this target will type-check the sources in `[name]` and leverage the mypy cache from upstream internal dependencies.

Setup is significantly easier with bzlmod, we recommend and predominantly support bzlmod, though these rules should work without issue in non-bzlmod setups, albeit with more work to configure.

### Bzlmod Setup

**Add rules_mypy to your MODULE.bazel:**

```starlark
bazel_dep(name = "rules_mypy", version = "0.0.0")
```

**Optionally, configure a types repository:**

Many Python packages have separately published types/stubs packages. While mypy (and these rules) will work without including these types, this ruleset provides some utilities for leveraging these types to improve mypy's type checking.

```starlark
types = use_extension("@rules_mypy//mypy:types.bzl", "types")
types.requirements(
    name = "pip_types",
    # `@pip` in the next line corresponds to the `hub_name` when using
    # rules_python's `pip.parse(...)`.
    pip_requirements = "@pip//:requirements.bzl",
    # also legal to pass a `requirements.in` here
    requirements_txt = "//:requirements.txt",
)
use_repo(types, "pip_types")
```

**Wrap `py_*` rules/macros.**

If you do not already wrap `py_*` rules with a macro, create a `.bzl` file to wrap these rules:

```starlark
"Custom py_* macros that also run mypy."

load("@pip_types//:types.bzl", "types")
load("@rules_mypy//mypy:mypy.bzl", "decorate")
load("@rules_python//python:py_binary.bzl", rules_python_py_binary = "py_binary")
load("@rules_python//python:py_library.bzl", rules_python_py_library = "py_library")
load("@rules_python//python:py_test.bzl", rules_python_py_test = "py_test")

py_binary = decorate(
    py_target = rules_python_py_binary,
    types = types,
)

py_library = decorate(
    py_target = rules_python_py_library,
    types = types,
)

py_test = decorate(
    py_target = rules_python_py_test,
    types = types,
)
```

Or, if you do already wrap `py_*` rules with a macro, wrap your customized rules/macros or the input `py_*` rules as illustrated above.

If you're using Gazelle, you may need to adjust the imports Gazelle uses for `py_*` targets, refer to the `rules_python` docs for how to do this.

## Customizing mypy

mypy's behavior may be customized using a [mypy config file](https://mypy.readthedocs.io/en/stable/config_file.html) file. To use a mypy config file, pass a label for a valid config file to the `decorate` method:

```starlark
py_library = decorate(
    py_target = rules_python_py_library,
    mypy_ini = "//:mypy.ini",
    types = types,
)
```

To customize the version of mypy, use rules_python's requirements resolution and construct a custom mypy CLI:

```starlark
load("@pip//:requirements.bzl", "requirements") # '@pip' must match configured pip hub_name
load("@rules_mypy//mypy:mypy.bzl", "decorate", "mypy_cli")

mypy_cli(
    name = "mypy_cli",
    mypy_requirement = requirement("mypy"),
)

py_library = decorate(
    py_target = rules_python_py_library,
    mypy_cli = ":mypy_cli",
    types = types,
)
```

Further, to use mypy plugins referenced in any config file, use the `deps` attribute of `mypy_cli`:

```starlark
load("@pip//:requirements.bzl", "requirements") # '@pip' must match configured pip hub_name
load("@rules_mypy//mypy:mypy.bzl", "decorate", "mypy_cli")

mypy_cli(
    name = "mypy_cli",
    mypy_requirement = requirement("mypy"),
    deps = [
        requirement("pydantic"),
    ],
)

py_library = decorate(
    py_target = rules_python_py_library,
    mypy_cli = ":mypy_cli",
    types = types,
)
```
