load("@rules_python//python:py_info.bzl", "PyInfo")

def _impl(ctx):
    return [
        DefaultInfo(
            files = depset(ctx.files.srcs),
        ),
        PyInfo(
            transitive_sources = depset(ctx.files.srcs),
        ),
    ]

foo = rule(
    implementation = _impl,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
    },
)
