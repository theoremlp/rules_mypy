"""
mypy build rule.

The mypy build rule runs mypy, succeeding if mypy is error free and failing if mypy produces errors. The
result of the build is a mypy cache directory, located at [name].mypy_cache. When provided input cache
directories (the results of other mypy builds), the build rule first attempts to merge the cache directories.
"""

load("@rules_mypy_pip//:requirements.bzl", "requirement")
load("@rules_python//python:py_binary.bzl", "py_binary")
load("//mypy/private:py_type_library.bzl", "PyTypeLibraryInfo")

MypyCacheInfo = provider(
    doc = "Output details of the mypy build rule.",
    fields = {
        "cache_directory": "Location of the mypy cache produced by this target.",
    },
)

def _mypy_impl(ctx):
    # we need to help mypy map the location of external deps by setting
    # MYPYPATH to include the site-packages directories.
    external_deps = []

    types = []

    for dep in ctx.attr.deps:
        if PyTypeLibraryInfo in dep:
            types.append(dep[PyTypeLibraryInfo].directory + "/site-packages")
        elif dep.label.workspace_root.startswith("external/"):
            external_deps.append(dep.label.workspace_root + "/site-packages")

    # types need to appear first in the mypy path since the module directories
    # are the same and mypy resolves the first ones, first.
    mypy_path = ":".join(types + external_deps)

    cache_directory = ctx.actions.declare_directory(ctx.attr.name + ".mypy_cache")

    args = ctx.actions.args()
    args.add("--cache-dir", cache_directory.path)

    args.add_all([
        cache[MypyCacheInfo].cache_directory.path
        for cache in ctx.attr.caches
    ], before_each = "--upstream-cache")
    args.add_all(ctx.files.srcs)

    config_files = [ctx.file.mypy_ini] if ctx.file.mypy_ini else []

    ctx.actions.run(
        mnemonic = "mypy",
        inputs = depset(direct = ctx.files.srcs +
                                 ctx.files.deps +
                                 ctx.files.caches +
                                 config_files),
        outputs = [cache_directory],
        executable = ctx.executable.mypy_cli,
        arguments = [args],
        env = {
            "MYPYPATH": mypy_path,
            # force color on
            "MYPY_FORCE_COLOR": "1",
            # force color on only works if TERM is set to something that supports color
            "TERM": "xterm-256color",
        } | ctx.configuration.default_shell_env,
    )

    return [
        DefaultInfo(
            files = depset([cache_directory]),
            runfiles = ctx.runfiles(files = [cache_directory]),
        ),
        MypyCacheInfo(cache_directory = cache_directory),
    ]

_mypy = rule(
    implementation = _mypy_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "mypy_ini": attr.label(allow_single_file = True),
        "mypy_cli": attr.label(cfg = "exec", default = "//mypy/private:mypy", executable = True),
        "caches": attr.label_list(),
    },
)

def mypy(
        name,
        srcs = None,
        deps = None,
        mypy_ini = None,
        mypy_cli = None,
        visibility = None,
        testonly = None,
        tags = None):
    """
    Create a mypy target inferring upstream caches from deps.

    Args:
        name:       name of the target to produce
        srcs:       (optional) srcs to type-check
        deps:       (optional) deps used as input to type-checking
        mypy_ini:   (optional) mypy_ini file to use
        mypy_cli:   (optional) a replacement mypy_cli to use (recommended to produce
                    with mypy_cli macro)
        visibility: (optional) visibility of this target (recommended to set to same
                    as the py_* target it inherits)
        testonly:   (optional) if this is a testonly target
        tags:       (optional) a list of tags to apply
    """

    upstream_caches = []
    if deps:
        for dep in deps:
            lab = native.package_relative_label(dep)
            if lab.workspace_root == "":
                upstream_caches.append(str(lab) + ".mypy")

    _mypy(
        name = name,
        srcs = srcs,
        deps = deps,
        mypy_ini = mypy_ini,
        mypy_cli = mypy_cli,
        visibility = visibility,
        testonly = testonly,
        tags = tags,
    )

def mypy_cli(name, deps = None, mypy_requirement = None):
    """
    Produce a custom mypy executable for use with the mypy build rule.

    Args:
        name: name of the binary target this macro produces
        deps: (optional) additional dependencies to include (e.g. mypy plugins)
        mypy_requirement: (optional) a replacement mypy requirement
    """

    deps = deps or []
    mypy_requirement = mypy_requirement or requirement("mypy")

    py_binary(
        name = name,
        srcs = ["@rules_mypy//mypy/private:mypy.py"],
        main = "@rules_mypy//mypy/private:mypy.py",
        visibility = ["//visibility:public"],
        deps = [
            mypy_requirement,
            requirement("click"),
        ] + deps,
    )
