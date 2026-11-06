#!/usr/bin/env python3
"""Read or advance the version shared by Parc bundles and stable releases."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(repo: Path = ROOT) -> dict:
    try:
        value = json.loads((repo / "app-version.json").read_text())
    except (OSError, ValueError) as error:
        raise ValueError("Cannot read app-version.json: " + str(error)) from error
    if (not isinstance(value, dict) or set(value) != {"version", "build"}
            or not isinstance(value["version"], str)
            or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value["version"])
            or type(value["build"]) is not int or not 1 <= value["build"] <= 9999):
        raise ValueError("app-version.json requires a three-part version and a build number from 1 to 9999")
    return value


def advance(version: str, repo: Path = ROOT) -> dict:
    current = read(repo)
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("Use a three-part release version, for example 1.0.1")
    if tuple(map(int, version.split("."))) <= tuple(map(int, current["version"].split("."))):
        raise ValueError("The next release version must be greater than " + current["version"])
    if current["build"] == 9999:
        raise ValueError("The Apple bundle build number is exhausted; choose a new build-number scheme first")
    value = {"version": version, "build": current["build"] + 1}
    (repo / "app-version.json").write_text(json.dumps(value, indent=2) + "\n")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("show", help="print the current release version")
    commands.add_parser("bump", help="advance the release version and bundle build").add_argument("version")
    args = parser.parse_args()
    try:
        value = advance(args.version) if args.command == "bump" else read()
    except ValueError as error:
        parser.exit(1, "error: " + str(error) + "\n")
    print(value["version"])


if __name__ == "__main__":
    main()
