from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import threading

SWIFT_TARGET = "arm64-apple-macos13.0"
APP_PRODUCT = "Parc"
APP_SWIFT_DIRECTORIES = ("Sources/ParcCore", "Sources/ParcApp")
WARNING = re.compile(r"^(?:\S[^:]*:\d+(?::\d+)?: |<unknown>:0: "
                     r"|(?:\S[^:]*: [\w.+-]+: )?(?:clang(?:\+\+)?|cc|c\+\+|swiftc?|swift-frontend|swift-driver|ld|ld64\.lld|libtool): )?warning: ")


class Warnings(ValueError):
    pass


def package_environment(engine_frameworks: Path | None, sparkle_release: Path) -> dict[str, str]:
    return {**os.environ, "PARC_ENGINE_FRAMEWORKS": "" if engine_frameworks is None else str(engine_frameworks),
            "PARC_SPARKLE_FRAMEWORKS": str(sparkle_release)}


def swift_build(repo: Path, configuration: str, *, scratch: Path | None = None, target: str | None = None,
                extra: tuple[str, ...] = ()) -> list[str]:
    command = ["xcrun", "swift", "build", "--package-path", str(repo), "--configuration", configuration]
    if scratch is not None:
        command += ["--scratch-path", str(scratch)]
    if configuration == "release":
        command += ["--arch", "arm64", "-debug-info-format", "none"]
    command += ["--target", target] if target else ["--product", APP_PRODUCT]
    return [*command, "--disable-dead-strip", "--disable-local-rpath", *extra]


def package_objects(scratch: Path, configuration: str) -> list[Path]:
    lists = sorted(scratch.glob(f"out/Intermediates.noindex/*.build/{configuration.capitalize()}"
                                f"/{APP_PRODUCT}-p.build/Objects-normal/arm64/{APP_PRODUCT}.LinkFileList"))
    if len(lists) != 1:
        raise ValueError(f"Expected one {APP_PRODUCT} link file list under {scratch}, found {len(lists)}")
    objects = [Path(item) for item in shlex.split(lists[0].read_text())]
    if not objects or any(path.suffix != ".o" or not path.is_file() for path in objects):
        raise ValueError(f"Unexpected {APP_PRODUCT} link inputs in {lists[0]}")
    return objects


def warnings(output: str) -> list[str]:
    return [line.rstrip() for line in output.splitlines() if WARNING.match(line)]


def message(command: list[str], found: list[str]) -> str:
    return (f"{' '.join(command[:2])} reported {len(found)} warning(s); "
            "Parc treats every compiler and linker warning as an error:\n" + "\n".join(found))


def require_no_warnings(command: list[str], found: list[str]) -> None:
    if found:
        raise Warnings(message(command, found))


def forward(command: list[str], *, cwd: Path | None = None,
            env: dict[str, str] | None = None) -> tuple[int, list[str]]:
    found = []

    def pump(source, sink) -> None:
        writable = True
        for line in source:
            if WARNING.match(line):
                found.append(line.rstrip())
            if writable:
                try:
                    sink.write(line)
                    sink.flush()
                except OSError:
                    writable = False

    with subprocess.Popen(command, cwd=cwd, env=env, text=True, errors="replace",
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        pumps = [threading.Thread(target=pump, args=(process.stdout, sys.stdout)),
                 threading.Thread(target=pump, args=(process.stderr, sys.stderr))]
        for thread in pumps:
            thread.start()
        for thread in pumps:
            thread.join()
    return process.returncode, found


def run(command: list[str], *, capture: bool = True, cwd: Path | None = None,
        env: dict[str, str] | None = None) -> str:
    if capture:
        result = subprocess.run(command, cwd=cwd, env=env, text=True, errors="replace", capture_output=True)
        if result.returncode:
            raise subprocess.CalledProcessError(result.returncode, command, result.stdout, result.stderr)
        require_no_warnings(command, warnings(result.stdout) + warnings(result.stderr))
        return result.stdout
    code, found = forward(command, cwd=cwd, env=env)
    if code:
        raise subprocess.CalledProcessError(code, command)
    require_no_warnings(command, found)
    return ""
