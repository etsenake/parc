#!/usr/bin/env python3
"""Verify a stable Parc release and update its cask in the existing tap clone.

Does not commit or push: inspect/check the resulting diff, then publish it.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "etsenake/parc"
TAP_REPOSITORY = "etsenake/homebrew-tap"
PRODUCTION_TEAM = "94HKA7L2DR"
_github_environment = None
spec = importlib.util.spec_from_file_location("parc_release_dmg", Path(__file__).with_name("package-dmg.py"))
dmg_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg_tool)


def run(*args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


def github(*args):
    global _github_environment
    if _github_environment is None:
        # An inherited token can be stale; retrieve gh's saved login without
        # exposing its value through arguments, diagnostics or cask metadata.
        login_environment = {key: value for key, value in os.environ.items() if key not in ("GH_TOKEN", "GITHUB_TOKEN")}
        token = subprocess.check_output(["gh", "auth", "token"], env=login_environment,
                                        text=True, stderr=subprocess.DEVNULL).strip()
        if not token:
            raise ValueError("Authenticate gh with access to etsenake/parc before publishing")
        _github_environment = {**login_environment, "GH_TOKEN": token, "GITHUB_TOKEN": ""}
    return run("gh", *args, env=_github_environment)


def verify_tag(tag, expected_commit):
    reference = json.loads(github("api", f"repos/{REPOSITORY}/git/ref/tags/{tag}"))["object"]
    for _ in range(5):
        if not re.fullmatch(r"[0-9a-f]{40}", reference.get("sha", "")):
            raise ValueError("GitHub tag has an invalid object identity")
        if reference.get("type") == "commit":
            if reference["sha"] != expected_commit:
                raise ValueError("GitHub tag resolves to a different source commit than the release")
            return
        if reference.get("type") != "tag":
            raise ValueError("GitHub release tag does not reference a commit")
        reference = json.loads(github("api", f'repos/{REPOSITORY}/git/tags/{reference["sha"]}'))["object"]
    raise ValueError("GitHub annotated tag nesting exceeds the supported bound")


def verify_release(release, archive):
    tag = release["tag_name"]
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("Homebrew accepts stable v<major>.<minor>.<patch> releases only")
    version = tag[1:]
    commit = release["target_commitish"]
    if release["draft"] or release["prerelease"] or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("The stable release must be published at an exact source commit")
    assets = [item for item in release["assets"] if item["name"] == f"Parc-{version}-arm64.zip"]
    if len(assets) != 1:
        raise ValueError("The stable release lacks its uniquely named ARM64 archive")
    asset = assets[0]
    digest = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("The release asset lacks GitHub's SHA-256 digest")
    with archive.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if "sha256:" + actual != digest:
        raise ValueError("Downloaded archive differs from GitHub's digest")
    with zipfile.ZipFile(archive) as bundle:
        report = json.loads(bundle.read("development/package-report.json"))
        info = plistlib.loads(bundle.read("development/Parc.app/Contents/Info.plist"))
    app_version = report.get("app_version", {})
    notary = report.get("notarization", {})
    if (app_version.get("version") != version or type(app_version.get("build")) is not int
            or info.get("CFBundleShortVersionString") != version
            or info.get("CFBundleVersion") != str(app_version["build"])
            or info.get("CFBundleIdentifier") != "org.parc.Browser"):
        raise ValueError("Archive bundle/report versions or Parc identity differ from the release")
    if (report.get("purpose") != "distribution" or report.get("configuration") != "release"
            or report.get("layout") != "standalone-app" or report.get("distribution_eligible") is not True
            or report.get("notarized") is not True or notary.get("status") != "Accepted"
            or notary.get("stapled") is not True or notary.get("gatekeeper_verified") is not True
            or report.get("signing_team") != PRODUCTION_TEAM or notary.get("team") != PRODUCTION_TEAM
            or not report.get("signed_images")):
        raise ValueError("Homebrew publication requires a verified notarized standalone distribution package")
    with zipfile.ZipFile(archive) as bundle:
        for relative, expected in report["signed_images"].items():
            if not relative.startswith("Parc.app/") or ".." in Path(relative).parts:
                raise ValueError("Unsafe signed-image inventory path")
            with bundle.open("development/" + relative) as image:
                if hashlib.file_digest(image, "sha256").hexdigest() != expected:
                    raise ValueError("Archive signed image differs from its notarized report: " + relative)
    return app_version, actual, commit, report


def verify_dmg_asset(release, dmg, report, folder):
    filename = f'Parc-{report["app_version"]["version"]}-arm64.dmg'
    assets = [asset for asset in release["assets"] if asset["name"] == filename]
    if len(assets) != 1 or not re.fullmatch(r"sha256:[0-9a-f]{64}", assets[0].get("digest", "")):
        raise ValueError("The stable release lacks its uniquely named DMG and GitHub digest")
    with dmg.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if "sha256:" + digest != assets[0]["digest"]:
        raise ValueError("Downloaded DMG differs from GitHub's digest")
    dmg_tool.verify_dmg(dmg, report, folder)
    return digest


def cask(version, digest):
    return f'''# typed: false
# frozen_string_literal: true

require_relative "../lib/parc_private_release_download_strategy"

cask "parc" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/etsenake/parc/releases/download/v#{{version}}/Parc-#{{version}}-arm64.dmg",
      using: ParcPrivateReleaseDownloadStrategy
  name "Parc"
  desc "Native browser with an independent Chromium engine"
  homepage "https://github.com/etsenake/parc"

  livecheck do
    skip "Private releases; the release publisher updates this cask"
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Parc.app"

  uninstall quit: "org.parc.Browser"
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="published stable tag, for example v1.0.0")
    parser.add_argument("--tap", required=True, type=Path, help="existing etsenake/homebrew-tap clone")
    args = parser.parse_args()
    tap = args.tap.resolve()
    try:
        if run("git", "status", "--porcelain", cwd=tap):
            raise ValueError("The tap clone must be clean before updating")
        origin = run("git", "remote", "get-url", "origin", cwd=tap).removesuffix(".git")
        if origin not in (f"https://github.com/{TAP_REPOSITORY}", f"git@github.com:{TAP_REPOSITORY}"):
            raise ValueError("The tap origin is not " + TAP_REPOSITORY)
        if run("git", "branch", "--show-current", cwd=tap) != "main":
            raise ValueError("Update the tap's main branch")
        run("git", "fetch", "origin", "main", cwd=tap)
        run("git", "merge", "--ff-only", "origin/main", cwd=tap)
        if not (tap / "lib/parc_private_release_download_strategy.rb").is_file():
            raise ValueError("The tap's authenticated Parc download strategy is missing")
        if not re.fullmatch(r"v[0-9]+[.][0-9]+[.][0-9]+", args.tag):
            raise ValueError("Use a stable v<major>.<minor>.<patch> tag")
        release = json.loads(github("api", f"repos/{REPOSITORY}/releases/tags/{args.tag}"))
        verify_tag(args.tag, release["target_commitish"])
        with tempfile.TemporaryDirectory(prefix="parc-homebrew-") as temporary:
            archive = Path(temporary) / "Parc.zip"
            github("release", "download", args.tag, "--repo", REPOSITORY,
                "--pattern", f"Parc-{args.tag.removeprefix('v')}-arm64.zip", "--output", str(archive))
            app_version, _, commit, report = verify_release(release, archive)
            dmg = Path(temporary) / "Parc.dmg"
            github("release", "download", args.tag, "--repo", REPOSITORY,
                "--pattern", f'Parc-{app_version["version"]}-arm64.dmg', "--output", str(dmg))
            digest = verify_dmg_asset(release, dmg, report, Path(temporary))
        version = app_version["version"]
        source_version = json.loads(run("git", "show", commit + ":app-version.json", cwd=ROOT))
        if source_version != app_version:
            raise ValueError("The release source commit declares a different version")
        target = tap / "Casks/parc.rb"
        if target.exists():
            match = re.search(r'^  version "([0-9.]+)(?:,[^"]+)?"$', target.read_text(), re.M)
            if not match or tuple(map(int, version.split("."))) <= tuple(map(int, match[1].split("."))):
                raise ValueError("The release must advance the tap's current version")
        target.write_text(cask(version, digest))
        print(f"Updated {target} to {version} from {commit}; verify, commit and push the tap.")
    except (OSError, ValueError, KeyError, dmg_tool.Refusal, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, "error: " + str(error) + "\n")


if __name__ == "__main__":
    main()
