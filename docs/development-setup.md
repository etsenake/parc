# Development setup on another Mac

Start with the [developer onboarding checklist](developer-onboarding.md).
This page documents the prerequisite and build commands it uses.

Clone Parc to get its application source, reviewed engine overlays, build tools,
resources and focused tests. Restore the pinned engine artifacts from the
repository's private release assets using the [engine artifact guide](engine-artifacts.md).
The completed app-and-engine package is available separately. The larger
workspace snapshot retains Chromium source, build tools and compiled work for
incremental development.
directory.

## Host and tools

- Use a native Apple Silicon Mac and a writable APFS volume. The supported
  engine configuration is ARM64; the source tool rejects an Intel/Rosetta host.
- Install the full Xcode application, complete its first-launch setup and select
  it as the active developer directory. Command Line Tools alone are insufficient
  for the application's SwiftUI compiler macros. For a standard installation:

  ```sh
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  xcodebuild -version
  xcrun --sdk macosx swiftc --version
  xcrun --sdk macosx --show-sdk-path
  ```

  Substitute the actual Xcode path if needed. `check-swift.py` and `build.py`
  respect `DEVELOPER_DIR`; the engine bootstrap uses a restricted environment,
  so select Xcode with `xcode-select` for engine work. The pinned Chromium
  source's `docs/mac_build_instructions.md` and
  `build/config/mac/mac_sdk.gni` describe its SDK policy. The macOS 13 deployment
  target is not a claim that an old Xcode can build the current source.
- Install Python 3.12 or later and ensure `python3` selects it. The engine scripts
  require at least 3.11; archive tooling also uses modern tar extraction
  filters. **Do not use macOS's Python 3.9.6** for
  this setup. Every `python3` command below assumes a suitable interpreter on
  `PATH`; otherwise replace it with the installed interpreter's absolute path
  (for example `/opt/homebrew/bin/python3.13`). Git must also be available.
  Check `python3 --version` and `git --version` before starting.
  The checked-in orchestration scripts use the Python standard library. Xcode
  supplies the native compilers and packaging/signing tools; the pinned source
  bootstrap fetches its own depot_tools, Chromium dependencies and build tools.
- When building from source, allow for the source tool's storage policy: at
  least 80 GB free before sync and 40 GB free before building. These are preflight thresholds,
  not an estimate of the final size or a guarantee of sufficient capacity.
  Downloads require access to the upstream repositories and dependency servers.

## Restore the engine first

Follow the [engine artifact guide](engine-artifacts.md) to download and verify
the last completed engine package and saved build workspace. The restore tool
checks their provenance without starting a build. Preserve the downloaded parts
to avoid downloading them again after an interrupted restore.

For an isolated local engine, the engine owner can use `cp -c -p -R` followed
by `adopt-clone --source-workspace` as described in
[Engine](../Engine/README.md#build-configuration). The copy must have the same
path depth and volume as its idle owned source. Adoption requires regeneration;
use `--previous-lock` when copying a workspace still on the previous pins.

The source bootstrap below is for intentionally creating a new engine workspace.
It is not the default new-machine onboarding path.

## Build from source: choose the engine location

```sh
git clone https://github.com/etsenake/parc.git
cd parc
python3 scripts/engine-source.py --help
python3 scripts/build.py --help
python3 scripts/check-swift.py --help
```

Keep local build products **inside this checkout under ignored directories**:
engine source/objects in `work/`, packages and logs in `build/`. Chromium is
gitignored there; do not put it under tracked trees like `Sources/` or
`Engine/`. The engine directory itself must not exist before the first `sync`.
Use only ASCII letters, digits, `/`, `.`, `_` and `-` in the path, with no
symlinked ancestors. For example:

```sh
mkdir -p "$PWD/work" "$PWD/build"
PARC_ENGINE="$PWD/work/engine"
python3 scripts/engine-source.py plan --workspace "$PARC_ENGINE"
python3 scripts/engine-source.py check --workspace "$PARC_ENGINE"
```

`plan` and `check` do not download or build. Read `ready` and `blockers` in their
JSON output: `plan` may exit successfully while reporting blockers. Do not
pre-create the final engine directory to try to fix a refusal.

`Engine/source-lock.json` remains the stopgap lock. Direct mode is opt-in with
`--lock-file "$PWD/Engine/source-lock-direct.json"` on every source-tool command;
use the separately integrated `Engine/ParcHost/overlay-direct.json` for its overlay.
Keep the stopgap workspace intact; direct retargeting is guarded off in this
preparatory slice. After the first direct build, the
coordinator promotes the direct lock to the canonical filename. The selected
lock is authoritative for repositories and build settings. Do not substitute a system CEF package or manually update one
dependency. For pinned-source upgrades, use `retarget --previous-lock` as described
in [Engine](../Engine/README.md#build-configuration); preserve the previous lock
before updating it. Verified same-branch incremental retargets use the existing
40 GB build reserve; fresh syncs and cross-branch or unverifiable retargets keep
the 80 GB sync reserve. The engine guide defines the required lock/CEF proofs.
The source tool owns its dependency checkout and lock/receipt files;
it does not reset, clean, delete or adopt an arbitrary existing checkout.

## Build from source: sync, apply, build, seal and package

Run each command after the preceding command succeeds. These are the supported
tracked entry points; no historical `integrated-engine*/run.py` wrapper is
needed. Keep this Parc checkout unchanged through the engine stages and app
packaging. In a shared workspace, coordinate the freeze with the explicitly assigned
engine owner as required by [the collaboration guide](collaboration.md). These
commands document the workflow; engine apply/build still requires authorization.

```sh
python3 scripts/engine-source.py sync --workspace "$PARC_ENGINE"
python3 scripts/engine-source.py overlay-check --workspace "$PARC_ENGINE" \
  --manifest "$PWD/Engine/ParcHost/overlay.json"
python3 scripts/engine-source.py overlay-apply --workspace "$PARC_ENGINE" \
  --manifest "$PWD/Engine/ParcHost/overlay.json"
python3 scripts/engine-source.py plan --for build --workspace "$PARC_ENGINE"
mkdir -p "$PWD/build"
python3 scripts/engine-source.py build --workspace "$PARC_ENGINE" --jobs 4 \
  2>&1 | tee "$PWD/build/engine-build.log"
```

The first build is substantial; retain this checkout and its generated output
for incremental work. Tail `$PWD/build/engine-build.log` for progress. The
default symbol level is zero. If choosing `--symbol-level 1`, use it
consistently for sync, checks, builds and shipping commands for that workspace.
The source tool preserves recorded failures and refuses incompatible or
in-progress state; inspect its error rather than editing receipts or removing
locks. It may resume an unchanged recorded dependency-sync failure or returned
build/generation failure as documented in [Engine/README.md](../Engine/README.md).

After a successful engine build, select a new package-run directory **under
ignored `$PWD/build/`**. A unique name keeps the seal, package, logs and
provenance together:

```sh
PARC_RUN="$PWD/build/local-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$PARC_RUN"
python3 scripts/build.py seal-engine \
  --engine-dir "$PARC_ENGINE/chromium/src/out/Release_GN_arm64" \
  --manifest "$PARC_RUN/engine-artifacts.json"
python3 scripts/build.py build \
  --engine-dir "$PARC_ENGINE/chromium/src/out/Release_GN_arm64" \
  --manifest "$PARC_RUN/engine-artifacts.json" \
  --output "$PARC_RUN/development" --configuration release
```

For a distributable development app, package with `bash scripts/package-app.sh
"$PARC_RUN/engine-artifacts.json"` instead of the `build` step above: it
packages from the clean pushed checkout into its own run folder and publishes
the result to GitHub ([publishing app builds](../tests/Packaging/README.md#publishing-app-builds)).

`build.py` also appends progress to `$PARC_RUN/seal.log` and
`$PARC_RUN/package.log`. One live view for engine build or packaging:

```sh
bash scripts/watch-progress.sh
```

The manifest and output must not already exist. Sealing verifies the completed
engine's source lock, applied overlay, public headers and binaries; packaging
rechecks that seal. A stale engine is rejected rather than selected implicitly.
An app-only edit can use an existing seal if its engine inputs still match.
Engine/header/overlay changes require the corresponding engine work and a new
seal. `--configuration debug` changes Swift optimization only.

The result is `development/Parc.app` **with required sibling engine libraries**.
Keep the entire `development` directory together. Read its
`package-report.json` and the engine workspace's `.parc-engine-source.json`
alongside command exit statuses; a start record or existing directory is not a
completed stage. These commands do not install or launch Parc. The separate
non-component shipping build, certificate signing and distribution boundaries
are documented in [the packaging guide](../tests/Packaging/README.md).

Component development packages load many sibling libraries per helper process.
Their launch costs are not representative of the non-component shipping engine;
measure the intended configuration before making performance claims.

## Check Swift without building an engine or app

The reusable checker preserves the previous scratch helper's compiler contract:
warnings as errors, whole-module checking, ARM64 macOS 13, the checkout's current
native bridge headers. The direct facade needs no engine headers or built
package. Legacy facades require an explicitly selected CEF include tree.

For a direct facade:

```sh
python3 scripts/check-swift.py --plan
python3 scripts/check-swift.py
python3 scripts/check-swift.py --mode sil
```

The default `typecheck` mode is for iteration. `--mode sil` emits SIL to
`/dev/null` with `-Onone`; use it for completed features with material Swift changes,
as required by [the working contract](../AGENTS.md). It catches compiler stages
that plain typechecking omits, including definite initialization.

The script finds its own checkout regardless of the shell's working directory.
Use `--repo /absolute/other-worktree` to select another checkout, or
`--chromium-source "$PARC_ENGINE/chromium/src"` or
`--cef-include /absolute/cef/include` when checking a legacy facade.
When the facade imports `native_application_protocols.h`, the checker uses the
self-contained declarations in `Engine/ParcNative` without an engine checkout.
Explicit legacy header options are refused for the direct facade.
`PARC_CHROMIUM_SOURCE` is an optional environment default; an explicit header
option takes precedence. There are no historical username, workspace or package
defaults.

Each execution creates a fresh directory under `build/swift-checks` containing
`start.json`, `compiler.log` and `result.json`. Use `--output-dir` and `--label`
to choose another location/name; an existing receipt directory is never
overwritten. A passing result requires compiler exit zero, unchanged Git HEAD
and unchanged hashes/file membership for the Swift sources, bridge headers,
CEF include tree, source lock and checker. The receipt records the command,
selected compiler/SDK, source hashes and Git state. `--plan` validates input
paths and prints the command/hashes without invoking the compiler or writing
receipts.

The checker's own tests use temporary source trees and a fake compiler:

```sh
python3 -m unittest discover -s tests/BuildTools -v
```

Select application/component tests appropriate to the change and inspect their
scripts first. The current user instructions and working contract determine
which checks are authorized; a setup guide is not permission to run a browser
fixture or change a real profile.

## What to carry over from the old Mac

Git carries the reusable application/build tools and pinned artifact manifests.
The private release assets carry the completed engine package and build workspace
archives. Use the documented restore commands so their hashes,
provenance and compatibility are checked. Do not manually rewrite receipts to
make a copied workspace pass validation. Code-signing certificates and local app
profiles are separate machine-specific inputs and are not part of these archives.

Binaries and compiler caches belong in release assets and restored local
directories, outside Git history.
