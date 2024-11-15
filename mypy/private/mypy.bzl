"""
mypy aspect.

The mypy aspect runs mypy, succeeding if mypy is error free and failing if mypy produces errors. The
result of the aspect is a mypy cache directory, located at [name].mypy_cache. When provided input cache
directories (the results of other mypy builds), the underlying action first attempts to merge the cache
directories.
"""

load("@python_versions//3.12:defs.bzl", "py_binary")
load("@rules_mypy_pip//:requirements.bzl", "requirement")
load(":py_type_library.bzl", "PyTypeLibraryInfo")

MypyCacheInfo = provider(
    doc = "Output details of the mypy build rule.",
    fields = {
        "directory": "Location of the mypy cache produced by this target.",
    },
)

def _mypy_impl(target, ctx):
    # skip non-root targets
    if target.label.workspace_root != "":
        return []

    # only instrument py_* targets
    if ctx.rule.kind not in ["py_binary", "py_library", "py_test"]:
        return []

    # disable if a target is tagged with at least one suppression tag
    for tag in ctx.attr._suppression_tags:
        if tag in ctx.rule.attr.tags:
            return []

    # we need to help mypy map the location of external deps by setting
    # MYPYPATH to include the site-packages directories.
    external_deps = []

    # we need to help mypy map the location of first party deps with custom
    # 'imports' by setting MYPYPATH.
    custom_imports = []

    # generated dirs
    generated_dirs = {}

    upstream_caches = []

    types = []

    depsets = []

    type_mapping = dict(zip([k.label for k in ctx.attr._types_keys], ctx.attr._types_values))
    additional_types = [
        type_mapping[dep.label]
        for dep in ctx.rule.attr.deps
        if dep.label in type_mapping
    ]

    if PyInfo in target:
        custom_imports.extend([x.split("/", 1)[-1] for x in target[PyInfo].imports.to_list()])

    for dep in (ctx.rule.attr.deps + additional_types):
        depsets.append(dep.default_runfiles.files)

        if PyTypeLibraryInfo in dep:
            types.append(dep[PyTypeLibraryInfo].directory.path + "/site-packages")
        elif dep.label.workspace_root.startswith("external/"):
            external_deps.append(dep.label.workspace_root + "/site-packages")
            external_deps.extend(["external/{}".format(x) for x in dep[PyInfo].imports.to_list()])
        elif PyInfo in dep and dep.label.workspace_name == "":
            # _main/path/to/package -> path/to/package
            custom_imports.extend([x.split("/", 1)[-1] for x in dep[PyInfo].imports.to_list()])

        if MypyCacheInfo in dep:
            upstream_caches.append(dep[MypyCacheInfo].directory)

        for file in dep.default_runfiles.files.to_list():
            if file.root.path:
                generated_dirs[file.root.path] = 1

        # TODO: can we use `ctx.bin_dir.path` here to cover generated files
        # and as a way to skip iterating over depset contents to find generated
        # file roots?

    unique_generated_dirs = generated_dirs.keys()

    # types need to appear first in the mypy path since the module directories
    # are the same and mypy resolves the first ones, first.
    mypy_path = ":".join(types + external_deps + custom_imports + unique_generated_dirs)

    output_file = ctx.actions.declare_file(ctx.rule.attr.name + ".mypy_stdout")

    args = ctx.actions.args()
    args.add("--output", output_file)

    if ctx.attr.cache:
        cache_directory = ctx.actions.declare_directory(ctx.rule.attr.name + ".mypy_cache")
        args.add("--cache-dir", cache_directory.path)

        outputs = [output_file, cache_directory]
        result_info = [
            MypyCacheInfo(directory = cache_directory),
            OutputGroupInfo(mypy = depset(outputs)),
        ]
    else:
        outputs = [output_file]
        result_info = [OutputGroupInfo(mypy = depset(outputs))]

    args.add_all([c.path for c in upstream_caches], before_each = "--upstream-cache")
    args.add_all(ctx.rule.files.srcs)

    if hasattr(ctx.attr, "_mypy_ini"):
        args.add("--mypy-ini", ctx.file._mypy_ini.path)
        config_files = [ctx.file._mypy_ini]
    else:
        config_files = []

    ctx.actions.run(
        mnemonic = "mypy",
        progress_message = "mypy %{label}",
        inputs = depset(
            direct = ctx.rule.files.srcs + upstream_caches + config_files,
            transitive = depsets,
        ),
        outputs = outputs,
        executable = ctx.executable._mypy_cli,
        arguments = [args],
        env = {
            "MYPYPATH": mypy_path,
            # force color on
            "MYPY_FORCE_COLOR": "1",
            # force color on only works if TERM is set to something that supports color
            "TERM": "xterm-256color",
        } | ctx.configuration.default_shell_env,
    )

    return result_info

def mypy(mypy_cli = None, mypy_ini = None, types = None, cache = True, suppression_tags = None):
    """
    Create a mypy target inferring upstream caches from deps.

    Args:
        mypy_cli:   (optional) a replacement mypy_cli to use (recommended to produce
                    with mypy_cli macro)
        mypy_ini:   (optional) mypy_ini file to use
        types:      (optional) a dict of dependency label to types dependency label
                    example:
                    ```
                    {
                        requirement("cachetools"): requirement("types-cachetools"),
                    }
                    ```
                    Use the types extension to create this map for a requirements.in
                    or requirements.txt file.
        cache:      (optional, default True) propagate the mypy cache
        suppression_tags: (optional, default ["no-mypy"]) tags that suppress running
                    mypy on a particular target.

    Returns:
        a mypy aspect.
    """
    types = types or {}

    additional_attrs = {}

    return aspect(
        implementation = _mypy_impl,
        attr_aspects = ["deps"],
        attrs = {
            "_mypy_cli": attr.label(
                default = mypy_cli or "@rules_mypy//mypy/private:mypy",
                cfg = "exec",
                executable = True,
            ),
            "_mypy_ini": attr.label(
                # we provide a default here because Bazel won't allow Label attrs
                # that are public, or private attrs that have default values of None
                default = mypy_ini or "@rules_mypy//mypy/private:default_mypy.ini",
                allow_single_file = True,
                mandatory = False,
            ),
            # pass the dict[Label, Label] in parts because Bazel doesn't have
            # this kind of attr to pass naturally
            "_types_keys": attr.label_list(default = types.keys()),
            "_types_values": attr.label_list(default = types.values()),
            "_suppression_tags": attr.string_list(default = suppression_tags or ["no-mypy"]),
            "cache": attr.bool(default = cache),
        } | additional_attrs,
    )

def mypy_cli(name, deps = None, mypy_requirement = None, tags = None):
    """
    Produce a custom mypy executable for use with the mypy build rule.

    Args:
        name: name of the binary target this macro produces
        deps: (optional) additional dependencies to include (e.g. mypy plugins)
        mypy_requirement: (optional) a replacement mypy requirement
        tags: (optional) tags to include in the binary target
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
        tags = tags,
    )
