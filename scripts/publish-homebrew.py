#!/usr/bin/env python3
"""Promote an accepted Parc candidate and update its cask in the existing tap clone.

Does not commit or push: inspect/check the resulting diff, then publish it.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from xml.etree import ElementTree
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "etsenake/parc"
PUBLIC_REPOSITORY = "etsenake/parc-releases"
TAP_REPOSITORY = "etsenake/homebrew-tap"
PRODUCTION_TEAM = "94HKA7L2DR"
PRODUCTION_DESIGNATED_REQUIREMENT = ('designated => identifier "org.parc.Browser" and anchor apple generic and '
    'certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and '
    'certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and '
    'certificate leaf[subject.OU] = "94HKA7L2DR"')
_github_environment = None
spec = importlib.util.spec_from_file_location("parc_release_dmg", Path(__file__).with_name("package-dmg.py"))
dmg_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg_tool)
spec = importlib.util.spec_from_file_location("parc_release_notes", Path(__file__).with_name("release_notes.py"))
release_notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_notes)


def run(*args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


def github(*args):
    global _github_environment
    if _github_environment is None:
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
    if release["draft"] or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("The versioned candidate must be published at an exact source commit")
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
        report_bytes = bundle.read("development/package-report.json")
        report = json.loads(report_bytes)
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
    return app_version, actual, commit, report, hashlib.sha256(report_bytes).hexdigest()


def require_startup(observation):
    seconds = observation.get("observed_seconds")
    if (observation.get("passed") is not True or type(seconds) not in (int, float)
            or not math.isfinite(seconds) or seconds < 60
            or observation.get("new_crash_reports") != [] or observation.get("failure") is not None
            or type(observation.get("main_pid")) is not int or observation["main_pid"] <= 0):
        raise ValueError("Promotion requires a passed startup observation of at least 60 seconds with no new crash reports")


def require_evidence(acceptance):
    kind = acceptance.get("acceptance_kind")
    if kind == "automatic":
        require_startup(acceptance.get("launch_observation", {}))
        if acceptance.get("status") != "passed":
            raise ValueError("Automatic startup acceptance must have passed")
    elif kind == "user-confirmed":
        confirmation = acceptance.get("user_confirmation", {})
        try:
            confirmed_at = datetime.datetime.fromisoformat(confirmation["confirmed_at"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError("User-confirmed acceptance requires a dated statement") from error
        if (acceptance.get("status") != "user-confirmed" or confirmation.get("confirmed_by") != "Josh"
                or confirmed_at.tzinfo is None or confirmation.get("scope") != "normal-startup"
                or not isinstance(confirmation.get("statement"), str) or not confirmation["statement"].strip()
                or acceptance.get("automatic_startup_acceptance_claimed") is not False):
            raise ValueError("User-confirmed acceptance requires the user's explicit dated normal-startup statement")
    else:
        raise ValueError("Acceptance must explicitly identify automatic or user-confirmed evidence")


def verify_acceptance(acceptance, tag, commit, app_version, report_sha):
    require_evidence(acceptance)
    manual = acceptance["acceptance_kind"] == "user-confirmed"
    code_verified = acceptance.get("artifact_code_hashes_verified" if manual else "installed_code_hashes_verified")
    strict_verified = acceptance.get("artifact_strict_verified" if manual else "prelaunch_strict_verified")
    if (acceptance.get("schema_version") != 1
            or acceptance.get("release_tag") != tag or acceptance.get("source_commit") != commit
            or acceptance.get("app_version") != app_version
            or acceptance.get("package_report_sha256") != report_sha
            or acceptance.get("signing_team") != PRODUCTION_TEAM
            or code_verified is not True or strict_verified is not True
            or acceptance.get("designated_requirement") != PRODUCTION_DESIGNATED_REQUIREMENT):
        raise ValueError("Startup acceptance must bind this exact release commit, app report hash, version and production identity")


def promote_release(release, acceptance, app_version, report_sha, notes):
    verify_acceptance(acceptance, release["tag_name"], release["target_commitish"], app_version, report_sha)
    promote_verified_artifacts(release, notes)


def promote_verified_artifacts(release, notes):
    verify_tag(release["tag_name"], release["target_commitish"])
    if github("api", f"repos/{REPOSITORY}", "--jq", ".private") != "true":
        raise ValueError("Parc release assets must remain in the private repository")
    github("release", "edit", release["tag_name"], "--repo", REPOSITORY,
           "--prerelease=false", "--latest", "--title", release["tag_name"].removeprefix("v"), "--notes", notes)
    after = json.loads(github("api", f'repos/{REPOSITORY}/releases/tags/{release["tag_name"]}'))
    if (after["prerelease"] or after["draft"] or after["target_commitish"] != release["target_commitish"]
            or [(item["id"], item["digest"]) for item in after["assets"]]
            != [(item["id"], item["digest"]) for item in release["assets"]]):
        raise ValueError("Release promotion changed immutable provenance or did not complete")


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


def publish_public(release, files, notes):
    tag = release["tag_name"]
    text = ("--title", tag.removeprefix("v"), "--notes", notes)
    if github("api", f"repos/{PUBLIC_REPOSITORY}", "--jq", ".private") != "false":
        raise ValueError(PUBLIC_REPOSITORY + " must be public")
    try:
        public = json.loads(github("api", f"repos/{PUBLIC_REPOSITORY}/releases/tags/{tag}"))
    except subprocess.CalledProcessError:
        public = None
    if public is None:
        github("release", "create", tag, "--repo", PUBLIC_REPOSITORY, "--target", "main", "--latest", *text,
               *[str(path) for path in files])
    else:
        existing = {item["name"]: item.get("digest", "") for item in public["assets"]}
        for path in files:
            with path.open("rb") as stream:
                digest = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
            if path.name not in existing:
                github("release", "upload", tag, str(path), "--repo", PUBLIC_REPOSITORY)
            elif existing[path.name] != digest:
                raise ValueError(f"{PUBLIC_REPOSITORY} {tag} already has a different {path.name}")
        github("release", "edit", tag, "--repo", PUBLIC_REPOSITORY, "--draft=false", "--prerelease=false", "--latest",
               *text)
    public = json.loads(github("api", f"repos/{PUBLIC_REPOSITORY}/releases/tags/{tag}"))
    published = {item["name"]: item.get("digest", "") for item in public["assets"]}
    for path in files:
        with path.open("rb") as stream:
            if published.get(path.name) != "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest():
                raise ValueError(f"{PUBLIC_REPOSITORY} {tag} {path.name} was not verified after upload")


def verify_appcast(appcast, tag, archive):
    enclosure = ElementTree.parse(appcast).find("channel/item/enclosure")
    url = f"https://github.com/{PUBLIC_REPOSITORY}/releases/download/{tag}/{archive.name}"
    if enclosure is None or enclosure.get("url") != url or enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("The appcast does not offer this release's ZIP")


def cask(version, digest):
    return f'''# typed: false
# frozen_string_literal: true

cask "parc" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/{PUBLIC_REPOSITORY}/releases/download/v#{{version}}/Parc-#{{version}}-arm64.dmg"
  name "Parc"
  desc "Native browser with an independent Chromium engine"
  homepage "https://github.com/{PUBLIC_REPOSITORY}"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Parc.app"

  uninstall quit: "org.parc.Browser"
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="versioned candidate tag, for example v1.0.1")
    evidence = parser.add_mutually_exclusive_group(required=True)
    evidence.add_argument("--artifact-only", action="store_true", help="publish verified notarized artifacts without installation or startup checks")
    evidence.add_argument("--acceptance", type=Path,
                        help="passed receipt from scripts/record-release-acceptance.py")
    parser.add_argument("--tap", required=True, type=Path, help="existing etsenake/homebrew-tap clone")
    parser.add_argument("--resume", action="store_true", help="reconcile this release's exact generated cask")
    parser.add_argument("--appcast", required=True, type=Path, help="this release's signed Sparkle appcast.xml")
    args = parser.parse_args()
    tap = args.tap.resolve()
    try:
        acceptance = json.loads(args.acceptance.read_text()) if args.acceptance else None
        if acceptance is not None:
            require_evidence(acceptance)
        dirty = run("git", "status", "--porcelain", cwd=tap)
        if dirty and (not args.resume or dirty.strip() not in ('M Casks/parc.rb', 'M  Casks/parc.rb')):
            raise ValueError("The tap clone has unrelated edits; preserved without overwriting")
        origin = run("git", "remote", "get-url", "origin", cwd=tap).removesuffix(".git")
        if origin not in (f"https://github.com/{TAP_REPOSITORY}", f"git@github.com:{TAP_REPOSITORY}"):
            raise ValueError("The tap origin is not " + TAP_REPOSITORY)
        if run("git", "branch", "--show-current", cwd=tap) != "main":
            raise ValueError("Update the tap's main branch")
        run("git", "fetch", "origin", "main", cwd=tap)
        run("git", "merge", "--ff-only", "origin/main", cwd=tap)
        if not re.fullmatch(r"v[0-9]+[.][0-9]+[.][0-9]+", args.tag):
            raise ValueError("Use a stable v<major>.<minor>.<patch> tag")
        release = json.loads(github("api", f"repos/{REPOSITORY}/releases/tags/{args.tag}"))
        verify_tag(args.tag, release["target_commitish"])
        with tempfile.TemporaryDirectory(prefix="parc-homebrew-") as temporary:
            archive = Path(temporary) / "Parc.zip"
            github("release", "download", args.tag, "--repo", REPOSITORY,
                "--pattern", f"Parc-{args.tag.removeprefix('v')}-arm64.zip", "--output", str(archive))
            app_version, _, commit, report, report_sha = verify_release(release, archive)
            if acceptance is not None:
                verify_acceptance(acceptance, args.tag, commit, app_version, report_sha)
            dmg = Path(temporary) / "Parc.dmg"
            github("release", "download", args.tag, "--repo", REPOSITORY,
                "--pattern", f'Parc-{app_version["version"]}-arm64.dmg', "--output", str(dmg))
            digest = verify_dmg_asset(release, dmg, report, Path(temporary))
            version = app_version["version"]
            notes = release_notes.text(json.loads(run("git", "show", commit + ":release-notes.json", cwd=ROOT)), version)
            public_dmg = Path(temporary) / f"Parc-{version}-arm64.dmg"
            public_zip = Path(temporary) / f"Parc-{version}-arm64.zip"
            dmg.rename(public_dmg); archive.rename(public_zip)
            appcast = Path(temporary) / "appcast.xml"
            appcast.write_bytes(args.appcast.read_bytes())
            verify_appcast(appcast, args.tag, public_zip)
            publish_public(release, [public_dmg, public_zip, appcast], notes)
        source_version = json.loads(run("git", "show", commit + ":app-version.json", cwd=ROOT))
        if source_version != app_version:
            raise ValueError("The release source commit declares a different version")
        target = tap / "Casks/parc.rb"
        if target.exists():
            match = re.search(r'^  version "([0-9.]+)(?:,[^"]+)?"$', target.read_text(), re.M)
            equal = match and version == match[1]
            if (not match or tuple(map(int, version.split("."))) < tuple(map(int, match[1].split(".")))
                    or (equal and (not args.resume or target.read_text() != cask(version, digest)))):
                raise ValueError("The release must advance the tap or resume its identical verified cask")
            if dirty and target.read_text() != cask(version, digest):
                raise ValueError("Local cask edits differ from this verified release; preserved")
        target.write_text(cask(version, digest))
        if acceptance is not None:
            promote_release(release, acceptance, app_version, report_sha, notes)
        else:
            promote_verified_artifacts(release, notes)
        print(f"Promoted {args.tag} and updated {target} from {commit}; verify, commit and push the tap.")
    except (OSError, ValueError, KeyError, dmg_tool.Refusal, subprocess.CalledProcessError, zipfile.BadZipFile,
            ElementTree.ParseError) as error:
        parser.exit(1, "error: " + str(error) + "\n")


if __name__ == "__main__":
    main()
