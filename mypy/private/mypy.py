import pathlib
import shutil
import sys

import click

import mypy.api
import mypy.util


def _merge_upstream_caches(cache_dir: str, upstream_caches: list[str]) -> None:
    current = pathlib.Path(cache_dir)
    current.mkdir(parents=True, exist_ok=True)

    for upstream_dir in upstream_caches:
        upstream = pathlib.Path(upstream_dir)

        # TODO(mark): maybe there's a more efficient way to synchronize the cache dirs?
        for dirpath, _, filenames in upstream.walk():
            relative_dir = dirpath.relative_to(upstream)
            for file in filenames:
                upstream_path = dirpath / file
                target_path = current / relative_dir / file
                if not target_path.parent.exists():
                    target_path.parent.mkdir(parents=True)
                if not target_path.exists():
                    shutil.copy(upstream_path, target_path)

    # missing_stubs is mutable, so remove it
    missing_stubs = current / "missing_stubs"
    if missing_stubs.exists():
        missing_stubs.unlink()


@click.command()
@click.option("--output", required=False, type=click.Path())
@click.option("--cache-dir", required=False, type=click.Path())
@click.option(
    "--upstream-cache",
    "upstream_caches",
    multiple=True,
    required=False,
    type=click.Path(exists=True),
)
@click.option("--mypy-ini", required=False, type=click.Path(exists=True))
@click.argument("srcs", nargs=-1, type=click.Path(exists=True))
def main(
    output: str | None,
    cache_dir: str | None,
    upstream_caches: tuple[str, ...],
    mypy_ini: str | None,
    srcs: tuple[str, ...],
) -> None:
    cache_dir = cache_dir or ".mypy_cache"
    _merge_upstream_caches(cache_dir, list(upstream_caches))

    if len(srcs) > 0:
        maybe_config = ["--config-file", mypy_ini] if mypy_ini else []
        report, errors, status = mypy.api.run(
            maybe_config
            + [
                # do not check mtime in cache
                "--skip-cache-mtime-checks",
                # mypy defaults to incremental, but force it on anyway
                "--incremental",
                # use a known cache-dir
                f"--cache-dir={cache_dir}",
                # use current dir + MYPYPATH to resolve deps
                "--explicit-package-bases",
                # speedup
                "--fast-module-lookup",
            ]
            + list(srcs)
        )
        if status:
            sys.stderr.write(errors)
            sys.stderr.write(report)
    else:
        report = ""
        errors = ""
        status = 0

    if output:
        with open(output, "w+") as file:
            file.write(errors)
            file.write(report)

    # use mypy's hard_exit to exit without freeing objects, it can be meaningfully
    # faster than an orderly shutdown
    mypy.util.hard_exit(status)


if __name__ == "__main__":
    main()
