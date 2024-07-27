"""
py_type_library CLI.

Many of the typings/stubs published to pypi for package [x] show up use
[x]-stubs as their base-package. mypy expects the typings/stubs to exist
in the as-used-in-Python package [x] when placed on the path. This CLI
creates a copy of the input directory's site-packages content dropping
`-stubs` from any directory in the site-packages dir while copying.
"""

import pathlib
import shutil
import click


def _clean(package: str) -> str:
    return package.removesuffix("-stubs")


@click.command()
@click.option("--input-dir", required=True, type=click.Path(exists=True))
@click.option("--output-dir", required=True, type=click.Path())
def main(input_dir: str, output_dir: str) -> None:
    input = pathlib.Path(input_dir) / "site-packages"

    output = pathlib.Path(output_dir) / "site-packages"
    output.mkdir(parents=True, exist_ok=True)

    for package in input.iterdir():
        shutil.copytree(input / package.name, output / _clean(package.name))


if __name__ == "__main__":
    main()
