# Development setup on another Mac

Start with the [developer onboarding checklist](developer-onboarding.md).
This page documents the prerequisite and build commands it uses.

Clone Parc to get its application source, reviewed engine overlays, build tools,
resources and focused tests. Restore the pinned engine artifacts from the
maintainer's private archive repository, `etsenake/parc-private`, using the [engine artifact guide](engine-artifacts.md).
The completed app-and-engine package is available separately. The larger
workspace snapshot retains Chromium source, build tools and compiled work for
incremental development.
The application build does not need another browser installed or a previous
Codex scratch directory.

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
- Install Apple's Metal toolchain once with
  `xcodebuild -downloadComponent MetalToolchain` (about 840 MB). Xcode ships
  only a placeholder `metal` command; the engine build fails without the real
  toolchain, and `xcrun metal --version` succeeds once it is installed. The
  production release and NAS setup download it themselves when it is missing.
- Install Python 3.12 or later and ensure `python3` selects it. The engine scripts
  require at least 3.11; archive tooling also uses modern tar extraction
  filters. **Do not use macOS's Python 3.9.6** for
  this setup. Every `python3` command below assumes a suitable interpreter on
  `PATH`; otherwise replace it with the installed interpreter's absolute path
  (for example `/opt/homebrew/bin/python3.13`). Git must also be available.
  Check `python3 --version` and `git --version` before starting.
  `scripts/release.sh` finds a Homebrew Python 3.12+ itself when `python3` is
  older.
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

`Engine/source-lock.json` and `Engine/ParcHost/overlay.json` are the sole engine
inputs. For pinned-source upgrades, preserve the previous lock and use
`retarget --previous-lock` as described in
[Engine](../Engine/README.md#build-configuration). Changed pins require the
80 GB sync reserve; unchanged pins use the 40 GB build reserve.
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

The app is a Swift package at the repository root. `scripts/check-swift.py`
builds its `Parc` target through SwiftPM with the package's own settings:
warnings as errors, the Swift 5 language mode, macOS 13 and the checkout's
bridge headers. The build weak-links the committed engine stub, so it needs no
engine build. `scripts/build.py` packages through the same package build.

Run:

```sh
python3 scripts/check-swift.py --plan
python3 scripts/check-swift.py
python3 scripts/check-swift.py --mode sil
python3 scripts/check-swift.py --mode release
```

The default `typecheck` mode is the incremental debug build in `.build`, the
same cache `swift build` and `swift test` use. `--mode sil` is a whole-module
debug build, which runs every mandatory SIL diagnostic, including definite
initialization, across the module at once. `--mode release` is the release's
optimized whole-module build for ARM64. Both write to a scratch folder inside
the receipt and remove it. Run release mode before publishing material Swift
changes, as required by [the working contract](../AGENTS.md). The
[release command](master-release.md#pipeline) runs it on the commit it is about
to release before committing the version.

Every compiler and linker warning is an error. `treatAllWarnings` alone doesn't
guarantee that: Swift deliberately keeps some downgraded concurrency
diagnostics, such as a non-Sendable closure handed to a Dispatch API, as
warnings and exits successfully. The checker fails any run whose build log
holds a warning. Packaging stops the same way for the Swift app, the native
facade, Dock tile and restart helper (all built with `-Wall -Wextra -Werror`),
the icon renderer and the signing keychain helper, and every one of their links
also passes the linker's `-fatal_warnings`. Packaging links the app itself from
the package's objects with the old link command, against the sealed engine and
the pinned Sparkle, so the shipped binary keeps its load commands and run paths.

The script finds its own checkout regardless of the shell's working directory.
Use `--repo /absolute/other-worktree` to select another checkout, or add
`--source-archive` for an extracted source tree that isn't a Git checkout, as the
release does; that skips the Git HEAD checks and relies on the input hashes.

Each execution creates a fresh directory under `build/swift-checks` containing
`start.json`, `compiler.log` and `result.json`. Use `--output-dir` and `--label`
to choose another location/name; an existing receipt directory is never
overwritten. A passing result requires build exit zero, no warning in the log,
unchanged Git HEAD and unchanged hashes/file membership for the Swift sources,
bridge headers, manifest, pinned dependencies, engine stub, source lock, checker
and its compiler module. `--plan` validates input paths and prints the
command/hashes without building or writing receipts.

The checker's own tests use temporary source trees and a fake build tool:

```sh
python3 -m unittest discover -s tests/BuildTools -v
```

Select application/component tests appropriate to the change and inspect their
scripts first. The current user instructions and working contract determine
which checks are authorized; a setup guide is not permission to run a browser
fixture or change a real profile.

## Run and write tests

Parc's tests are Swift Testing suites in the Swift package at the repository
root. `swift test` builds what changed and runs every suite in parallel in one
process; `swift test --filter EaselStoreTests` runs one suite and
`swift build --build-tests` only compiles. Builds are incremental and cached
in `.build`, so a run after a small edit recompiles only that file and what
depends on it.

`ParcCoreTests` (in `tests/ParcCoreTests`) tests the `ParcCore` library, which has
no AppKit or engine dependency. `ParcTests` (in `tests/ParcTests`) tests the `Parc`
app library with `@testable import Parc`. The app's code is the `Parc` library; the `ParcMain` executable only calls its launch function, so tests load the app's code without starting the app. Put a test in the lowest target that
can reach the code under test, in a folder named for its feature area.

Sparkle is a package dependency on the official `sparkle-project/Sparkle`
package, pinned to the exact version in `Package.resolved`, so a fresh clone
builds with no manual step. SwiftPM verifies the release archive against the
checksum the pinned package declares, and packaging embeds that framework.
Scripted builds pass `--disable-keychain` so a credential prompt can never stall
dependency resolution.

The manifest uses the package manager's own settings for warnings, defines, header paths and frameworks. It passes raw compiler options only where no setting exists: the engine bridge headers' folder for Swift's Objective-C importer, the release optimization level the bridge has always shipped with, weak linking against the engine stub, and the launcher's framework search path and fatal linker warnings.

Package builds never need an engine binary. Debug and test builds weak-link
`Stubs/Chromium Embedded Framework.framework`, a text stub of what the engine
bridge headers export, so the local engine can lag the headers. `ParcTests` also
links `ParcEngineDoubles`, empty classes with the engine classes' names and
superclasses, so XCTest's class discovery can load the app module without an
engine. Release packaging links the sealed engine itself. Both generated files
are committed. When the bridge headers add or remove an export, a package link
fails with an undefined `_OBJC_CLASS_$_PCNative…` or `parc_engine_…` symbol;
regenerate both files from the headers:

```sh
swift package --allow-writing-to-package-directory generate-engine-stub
```

Engine components that build without Chromium are in the `ParcNative` library,
which compiles the `Engine/ParcNative` sources named in the manifest's
`nativeLibrarySources`, so adding a Chromium-free source means adding its name
there. Its public headers folder, `tests/ParcNativeShims`, holds the shims for
Chromium include paths.
`ParcNativeTests` (in `tests/ParcNativeTests`) tests the library with
Objective-C XCTest cases built on `ParcNativeTestCase`. Check with `PARC_CHECK`
or the suite's `Check(condition, message)`; both stop the test at the first
failure. Name the classes with a `Tests` suffix and filter by class, for example
`swift test --filter PageHostTests`. Never edit an engine input for a test.

Parc's native presenters reach windows and time through two protocols in
`page_host.h`. `PCNativePresentation` covers sheets, child windows, ordering,
visibility and popovers; `PCNativeScheduling` covers uptime, dates, timers,
run-loop and main-queue hops and animation groups. Each presenter starts with
the system implementation, which makes exactly the AppKit, Foundation and GCD
calls. A test hands it the test case's offscreen doubles, `ParcNativePresentation()`
and `ParcNativeScheduler()`, which keep sheets, children and visibility as state
and never order a window on screen. Check that state with the `ParcNative…`
helpers in `ParcNativeWindows.h`, such as `ParcNativeAttachedSheet`.

Native tests never wait in real time. `ParcNativeAdvance(seconds)` moves the test
clock, fires the timers that fall due and then settles pending work.
`ParcNativeSettle()` handles only the work that is already pending. Animation
groups run at zero duration.

The `EngineFacade*Tests` targets compile the app's engine facade against test
doubles of the native classes. Each set of doubles gets its own target, so the
old-engine target fails to link if the facade names a class older engines lack.

Every test here is a unit test: a small, isolated check of one behaviour that
runs in milliseconds. Keep logic in models, stores and pure functions so it can
be tested without any view. Write one behaviour per `@Test`, named as a plain
sentence in camelCase, and build only the fixture that behaviour needs. Check
with `#expect`, and use `try #require` when later lines depend on a value. Give
inputs to a parameterized `@Test(arguments:)` instead of looping inside a test,
so each case runs and reports on its own. Randomized tests keep a fixed seed.

Unit tests never put a window on screen, never wait for drawing or animation,
and never wait on real time. Construct and lay out a view directly. When
responder or key handling needs a window, host the view in a borderless window
that is never ordered front. Inject time through Swift's `Clock` protocol, or a
scheduler, and advance it in the test instead of sleeping or polling. End-to-end
checks of the running app are UI tests, which this suite doesn't contain.

Tests run in parallel by default, so they share no mutable state: give each test
its own temporary directory and `UserDefaults(suiteName:)`. Mark a suite
`.serialized` only when the code under test touches process-wide state that
can't be injected, and mark a test `@MainActor` only when the code needs the
main actor. Test fixtures are resources on the test target (`resources:` in the
manifest), loaded through `Bundle.module`, never paths built from `#filePath`.
Nest helpers in the suite or make them `private`, because each target is one
module.

Keep test files small: one suite per file, named after the suite, usually 150
to 300 lines and never more than 500. When a suite grows past that, split it by
behaviour group into sibling suites that share the original name as a prefix,
and move helpers they share into a `<Name>Support.swift` file beside them.

Never drive AppKit's simulated clicks. `performClick(_:)` on a control and
`performClose(_:)` on a window spin a nested event-tracking run loop; with tests
running in parallel that loop can stop the main run loop, which ends the test
process silently with no summary. Call `sendClick()` from
`tests/ParcTests/Support/ControlClick.swift`, call a menu item's action on its
target, and give a window double a `performClose` that asks its delegate.

Test behaviour, not wording: never assert that source files contain particular
code. Warnings are errors in every target (`treatAllWarnings`), matching the
release compile.

Python `unittest` suites exist only for the Python tooling they exercise:
`tests/BuildTools` (build and release scripts), `tests/Site` (the website, also
run by GitHub CI), `tests/Documentation` (the docs checker) and the release
tooling suites beside them.

Checks that need a completed engine build stay outside `swift test`, each in its
own `tests/` folder with a README and runner: FairPlay (`scripts/test-fairplay-*.sh`),
error pages, the browser import readers, helper routing, platform codecs and the
native runtime harness.

## What to carry over from the old Mac

Git carries the reusable application/build tools and pinned artifact manifests.
The private archive's release assets carry the completed engine package and build workspace
archives. Use the documented restore commands so their hashes,
provenance and compatibility are checked. Do not manually rewrite receipts to
make a copied workspace pass validation. Code-signing certificates and local app
profiles are separate machine-specific inputs and are not part of these archives.

Binaries and compiler caches belong in release assets and restored local
directories, outside Git history.
