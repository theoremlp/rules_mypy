"Repository rule to generate `py_type_library` from input typings/stubs requirements."

def _render_types_bzl(rctx, types):
    content = ""
    content += """load("{pip_requirements}", "requirement")\n""".format(
        pip_requirements = rctx.attr.pip_requirements,
    )
    content += "types = {\n"
    for requirement in types:
        content += """    requirement("{raw}"): requirement("{requirement}"),\n""".format(
            raw = requirement.removeprefix("types-").removesuffix("-stubs"),
            name = str(rctx.attr.name),
            requirement = requirement,
        )
    content += "}\n"
    return content

def _generate_impl(rctx):
    contents = rctx.read(rctx.attr.requirements_txt)

    types = []

    # this is a very, very naive parser
    for line in contents.splitlines():
        if line.startswith("#") or line == "":
            continue

        if ";" in line:
            line, _ = line.split(";")

        if "~=" in line:
            req, _ = line.split("~=")
        elif "==" in line:
            req, _ = line.split("==")
        elif "<=" in line:
            req, _ = line.split("<=")
        else:
            continue

        req = req.strip()
        if req in rctx.attr.exclude_requirements:
            continue

        if req.endswith("-stubs") or req.startswith("types-"):
            types.append(req)

    rctx.file("BUILD.bazel", content = "")
    rctx.file("types.bzl", content = _render_types_bzl(rctx, types))

generate = repository_rule(
    implementation = _generate_impl,
    attrs = {
        "pip_requirements": attr.label(),
        "requirements_txt": attr.label(allow_single_file = True),
        "exclude_requirements": attr.string_list(default = []),
    },
)
