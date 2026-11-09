# Independent engine packaging


For complete production releases use [the master release command](../../docs/master-release.md):
`bash scripts/release.sh --type major|minor|patch` (choose one release type). The
commands below remain the individual building blocks.

## Inputs and commands

Use an absolute `--engine-dir` for the locked `Release_GN_arm64` output. First finish the reviewed native-host overlay with `scripts/engine-source.py build`. A successful source-tool completion must record phase `built`; manually linked files and a still-running build cannot be sealed. The matching reviewed source overlay must include the actual public native bridge headers and compiled exports.

Create the manifest and package in ignored local directories (replace the example paths with your workspace):

```sh
mkdir -p build/package-1
python3 scripts/build.py seal-engine \
  --engine-dir /absolute/engine-source/chromium/src/out/Release_GN_arm64 \
  --manifest "$PWD/build/package-1/engine-artifacts.json"
python3 scripts/build.py build \
  --engine-dir /absolute/engine-source/chromium/src/out/Release_GN_arm64 \
  --manifest "$PWD/build/package-1/engine-artifacts.json" \
  --output "$PWD/build/package-1/development"
```

The application configuration defaults to `release`, preserving this independent packager's original optimized Swift build. Add `--configuration debug` for `-g -Onone`; `--configuration release` uses `-O` with whole-module optimization (`-whole-module-optimization -num-threads <cores>`, as Xcode's Release does), compiling the module once instead of once per file. This option changes only Swift optimization, not the sealed Release engine, helper/compiler settings, signing identity or required explicit fresh output. Packaging purpose defaults to `development`. Seals and reports record the verified engine flags, `build_classification: development-component` and `distribution_eligible: false`; fresh seals are required after this metadata change, with no engine rebuild. The output itself must be a fresh directory whose parent already exists; a `.app` output is refused with migration guidance. The main bundle calls the shared `scripts/app_icons.py` exporter and sets `CFBundleIconFile=Parc.icns`. Both configurations export all ten catalog variants, each with ten standard macOS size/scale representations. The catalog's approved **Original** is the shared main ICNS, and every variant has identical bytes across debug/release. Source PNG variants are copied intact. The package report records the configuration and actual ICNS digest.

Every output is new: the tool refuses to overwrite a manifest or development directory. It stages the app, sibling libraries and report together, then publishes the complete directory with macOS exclusive atomic rename; even a concurrently created empty destination is preserved. It keeps the source tool's shared operation lock during verification and copying. Sealing reuses the bootstrap's pinned repository/dependency fingerprint checks, verifies the reviewed overlay's target hashes and the executable's public ABI headers, then records the framework inventory, symlinks, resources, runtime-loaded graphics/sandbox libraries, Mach-O dependency graph and component hashes. Packaging rechecks those inputs and rejects unknown external dependencies, ambiguous paths, symlink escapes and absent native C/Objective-C exports. The supported artifact is the pinned Release ARM64 component configuration; an additional non-system framework requires an explicit resource mapping rather than silently copying only its binary.

The layout follows the pinned CEF component-development arrangement:

```text
development/
  Parc.app/Contents/Frameworks/Chromium Embedded Framework.framework
  Parc.app/Contents/Frameworks/Parc Helper*.app
  lib*.dylib
  package-report.json
```

The complete built framework is copied, including locale bundles and runtime data. Engine copies are byte-identical to their seal before signing. Component dylibs retain their output-root paths beside the app; the framework's original six-parent RPATH reaches that directory. There is no `install_name_tool` call or custom load-command rewrite. Original unused fallback RPATHs remain intact; validation follows ordered actual loader paths and permits an actual resolved dependency only inside the owned development directory or a system location. Helpers are checked in their sandbox-first context, before the framework's RPATH stack is available. Move the **whole development directory**, not only `Parc.app`.

Swift's deployment tool supplies any compiler-required Swift runtime libraries. Signing changes copied signatures, so `package-report.json` records both pre-sign engine copy hashes and final signed image hashes, with source/overlay identity, layout and `executed: false`. The original engine output is never changed. The main app lives at `development/Parc.app`; the report lives inside the same atomically published directory.

## Standalone distribution

Finish `scripts/engine-source.py shipping-build` in the same owned workspace. Its output is `out/ParcDistribution_GN_arm64`; its separate successful receipt must match the current reviewed source and GN arguments. The packager verifies actual non-component flags and refuses any engine dependency outside the framework bundle. Final app auditing restricts every resolved non-system load to `Parc.app` itself, including runtime-loaded graphics/sandbox libraries. No load command is rewritten.

```sh
mkdir -p build/shipping-1
python3 scripts/build.py seal-engine \
  --engine-dir /absolute/engine-source/chromium/src/out/ParcDistribution_GN_arm64 \
  --manifest "$PWD/build/shipping-1/engine-artifacts.json" --purpose distribution
python3 scripts/build.py build \
  --engine-dir /absolute/engine-source/chromium/src/out/ParcDistribution_GN_arm64 \
  --manifest "$PWD/build/shipping-1/engine-artifacts.json" \
  --output "$PWD/build/shipping-1/package" --purpose distribution \
  --configuration release --sign-identity 'Developer ID Application: YOUR IDENTITY'
```

The atomically published directory contains a standalone `Parc.app` and its provenance report, with no sibling engine components. Distribution requires release app optimization and certificate-backed signing; normal inside-out hardened signing and strict validation remain unchanged. A non-component engine can also be packaged explicitly for local development with ad-hoc signing. Reports distinguish engine eligibility, intended purpose and actual signing identity, and state `notarized: false`; this command does not submit a notarization request or publish the app. Engine generation/compilation and package production status belong in the [parity ledger](../../docs/parity.md).

## Publishing app builds

### Stable versions and Homebrew

`app-version.json` is the single app/helper bundle version and build-number
source. Josh confirmed normal startup of 1.0.0 (bundle build 1); the automated
observation was interrupted by his deliberate behavior test and remains raw
evidence, not an automated pass. Wait for Josh's ready candidate before preparing 1.0.1
(bundle build 2). Then use `python3 scripts/app_version.py bump 1.0.1`, review the source and
version change, run applicable checks, then commit and push before packaging.
The command requires a numerically greater three-part version and advances the
bundle build. Preview packages keep the prepared version and do not update the
stable Homebrew cask.

```sh
bash scripts/package-app.sh --stable <sealed engine-artifacts.json>
# Or reuse a compatible published engine:
bash scripts/package-app.sh --stable --from-release [app-<stamp>-<commit> or v<version>]
```

Versioned candidate mode keeps the same distribution, signing, notarization and checkout
gates. It publishes `Parc-<version>-arm64.dmg` and a ZIP in the private
`v<version>` pre-release (not latest) and refuses an existing tag. The DMG contains the stapled
app and an Applications shortcut. It is separately Developer ID signed,
notarized, stapled and assessed by Gatekeeper; mounting it read-only also checks
the app's signature, ticket, identity, version and every signed-image hash.
Its immutable submission receipt and Apple log stay in `dmg-notarization/`
beside the package. Interrupted status/stapling work resumes that same
submission with `scripts/package-dmg.py`; an ambiguous upload must be reconciled
against Apple's history rather than automatically submitted twice. This follows
[Apple's container workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and Pi Garden's signed DMG plus ZIP release arrangement. The ZIP retains the
package report and supports later engine reuse. Stable releases are retained; the three-preview
cleanup only matches `app-*`. Install and open the completed app immediately,
as required below, then update the existing public tap clone:

```sh
python3 scripts/publish-homebrew.py v1.0.1 \
  --acceptance /absolute/acceptance.json --tap /absolute/homebrew-tap
```

First use the source-owned `scripts/record-release-acceptance.py` on a fresh
installed ready candidate; it verifies strict signing before normal open,
observes at least 60 seconds without exits/new crash reports, and checks every
image, production Team and stable designated requirement again afterward.
Alternatively, `--user-confirmed` records Josh's dated explicit acceptance and
statically verifies the preserved package artifact without current-app access
or launch; it retains an interrupted observation unchanged and never claims
an automatic pass. The publisher requires either valid receipt bound to the exact raw archived
report hash, source commit and version. It verifies the actual GitHub tag resolves to the release's exact source
commit, both downloaded assets against GitHub's digests, the bundle and report
versions, the production Team ID `94HKA7L2DR`, app and DMG notarization and every
signed-image hash before promoting stable/latest and changing the
cask. Review the tap diff, run its downloader harness, `brew audit --cask
etsenake/tap/parc` and a real `brew fetch --cask etsenake/tap/parc`, then commit
and push the tap immediately and compare its local/remote SHA. The updater
requires a clean main checkout of `etsenake/homebrew-tap`; it preserves unrelated
casks and rejects equal or decreasing release versions.

On another Apple Silicon Mac, run `brew tap etsenake/tap` and
`brew install --cask parc`; no GitHub login is needed. Upgrade with `brew update`
and `brew upgrade --cask parc`. Stable releases are mirrored with identical
bytes to the public `etsenake/parc-releases` repository, which the cask
downloads from; the source stays private. Homebrew uninstall preserves the Parc
profile. The initial 0.1.0 bootstrap cask can adopt the verified matching existing
notarized app with `brew install --cask --adopt etsenake/tap/parc` before its
first accepted stable upgrade. Actual DMG installation/upgrade validation waits
for an authorized app operation; promotion of user-confirmed 1.0.0 is authorized
now. Follow the complete [release runbook](../../docs/homebrew-release.md)
for fresh installation, recording, immutable retries, local-seal reuse for
documentation-only engine differences and promotion. No app/build/Keychain
checks are authorized by this documentation while the current hold applies.

### Preview builds

Every app package Josh will run is built and published by one command, so his other Macs can use it without building. From a checkout whose `HEAD` is already pushed to `origin/main`, with the engine sealed:

```sh
bash scripts/package-app.sh <sealed engine-artifacts.json>
```

When only app code changed, skip the engine and reuse the one in a published package; this compiles and signs just the app, so it takes minutes on any Mac with an engine workspace:

```sh
bash scripts/package-app.sh --from-release [app-<stamp>-<commit>]
```

Without a tag it picks the newest `app-*` preview or stable `v<version>` release titled with `HEAD`'s overlay version. An explicit stable tag also works, for example `--from-release v1.0.0`; it selects the ZIP even when the release also includes a DMG. It refuses when `Engine/` differs between that release's commit and `HEAD`, checks the downloaded zip against GitHub's digest, then `build.py release-build` checks the package report: a standalone non-component engine whose overlay identity and source lock digest equal `HEAD`'s, with every overlay input still matching its pinned digest, recorded build flags matching `engine-source.py`'s current shipping defines (the recipe lives outside `Engine/`), and no Widevine host signatures from the earlier package. The framework must pass `codesign --verify --deep --strict` and its code must hash to the report's signed images. The few upstream files packaging reads besides the engine (CEF's `include/cef_application_mac.h` and `LICENSE.txt`, Chromium's `LICENSE` and `chrome/app/app-entitlements.plist`) are read from an engine workspace's Git objects at the source lock's commits, never its working tree, and refused if the overlay patches them; both licenses must equal the ones the release shipped. Set `PARC_ENGINE_WORKSPACE` if the workspace isn't at `work/engine` in the main checkout or the historical `~/Documents/Codex/2026-10-23/re/work/engine-source`. The new package report records the reused release and the release that originally built the engine (`engine_release`), so packages can chain. Compiling and signing are `build_app`'s, unchanged.

For runtime testing on a Mac whose newest published engine is older than `main`'s overlay, `bash scripts/package-app.sh --local-test [tag]` packages `main`'s app against the newest published engine without publishing anything. It refuses a changed source lock, and `build.py release-build --local-test` asks the compiler which `Engine/ParcNative` headers the app's native facade and bridging header include, then refuses if any differs from the engine's commit: a changed header means the app may call engine API that engine lacks. When every new call is guarded with `respondsToSelector:` (or `responds(to:)`), `PARC_ALLOW_CHANGED_ENGINE_HEADERS=1` accepts the changed headers and the report lists them; a new class or exported function would still stop the app launching. Engine-internal changes are allowed and simply absent. The bundle's `Info.plist` gets `ParcLocalTestBuild`, the report's `engine_release.local_test` records the checkout's overlay and the headers compared, and the package stays in `build/local-test-<stamp>`.

Every published production app requires a valid **Developer ID Application** identity and Apple notarization. Apple Development and ad-hoc identities are refused for publication. The explicit unpublished `--local-test` path and direct development/fixture builds remain available. Published packages use `--purpose distribution`, release optimization and the official standalone engine; compatible published engines can also be reused for distribution.

On each building Mac, create a unique private key and CSR in the login Keychain, then issue a Developer ID Application certificate from the team's Apple Developer account. The certificate and all builders must use the same Team ID. Import Apple's Developer ID G2 intermediate from [Apple PKI](https://www.apple.com/certificateauthority/) if needed, using normal certificate-chain validation without a custom trust override. Validate with `security find-identity -v -p codesigning`, then select the exact identity:

```sh
bash scripts/setup-signing.sh 'Developer ID Application: YOUR NAME (TEAM ID)'
xcrun notarytool store-credentials parc-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

The second command securely prompts for an Apple app-specific password and stores it in Keychain. Never put that password in shell arguments, source, logs or chat. `PARC_NOTARY_PROFILE` selects a different saved profile; `parc-notary` is the default. The publishing command validates authentication before compilation. Private signing keys remain in the building Mac's Keychain; do not copy them between Macs or replace Parc Safe Storage encryption with a file. Developer ID provisioning does not require an App Store Connect app listing.

The publisher calls `scripts/notarize-app.py` before creating the GitHub release. It verifies every signed image against its report, actual Developer ID Team IDs, secure timestamps and strict signatures, submits a ZIP, and retains the submission ID and immutable input fingerprint under the package run's `notarization/`. It polls that same submission, downloads Apple's log, and requires Accepted status plus the exact archive hash/job ID. It then staples and validates the ticket, verifies strict signatures/image hashes again and requires Gatekeeper acceptance. Only then does it write `notarized: true` with the evidence into `package-report.json`, and publish a ZIP containing the stapled app. Failed notarization, stapling or assessment cannot publish a production release.

An interrupted status poll resumes the existing submission by rerunning the helper with the same package, profile and Team ID. Keep those inputs frozen. An upload with no confirmed submission ID requires reconciliation against `notarytool history`; the helper deliberately refuses to submit a second copy automatically. Inspect Apple's `apple-log.json`, including any warning issues, before claiming acceptance. Do not restart compilation or advance main to resolve a pending Apple submission.

Moving from Apple Development to Developer ID changes the designated requirement once. Verify the actual new requirement and same Team ID, record the intentional transition, and retain that stable production requirement for later builds. The first production launch can require normal Safe Storage approval again; leave it to the user. Never broaden its Keychain ACL or bypass macOS authorization. Notarization confirms Apple's distribution checks, not browser functionality or third-party allowlists.

The main bundle declares `http` and `https`, web Handoff, HTML/XHTML Viewer document types and the Productivity category. These declarations make it available to macOS as a browser and in Open With. They do not change the user's chosen default browser. Extra iOS default-browser entitlements or App Store metadata are not required for this Mac distribution.


**Install each completed build immediately.** After publication and package verification, replace `/Applications/Parc.app` and open it before checking newer main, starting another build, or writing receipts. Never hold a completed app for stable main or a newer catch-up package. The twenty-minute refresh uses one fetched source snapshot; later commits belong to the next cycle. Josh authorizes stopping running Parc instances during these refreshes. Preserve `~/Library/Application Support/Parc`; stage a fresh bundle, replace the old one without merging, verify launch, then remove the superseded installed copy. Engine/cache objects remain intact.

To install on another Mac (quit Parc first; the profile lives in `~/Library/Application Support/Parc`, not the install folder):

A prod (shipping) build's `Parc.app` carries its engine inside `Contents/Frameworks`, so it installs on its own into `/Applications`:

```sh
PARC_TAG='app-YYYYMMDDTHHMMSSZ-commit' # replace with the published tag
PARC_INSTALL=$(mktemp -d /tmp/parc-install.XXXXXX)
PARC_STAGE=$(mktemp -d /Applications/.Parc-install.XXXXXX)
(
  set -e
  gh release download "$PARC_TAG" -R etsenake/parc -O "$PARC_INSTALL/Parc.zip"
  ditto -x -k "$PARC_INSTALL/Parc.zip" "$PARC_INSTALL/unpacked"
  codesign --verify --deep --strict "$PARC_INSTALL/unpacked/development/Parc.app"
  ditto "$PARC_INSTALL/unpacked/development/Parc.app" "$PARC_STAGE/Parc.app"
  codesign --verify --deep --strict "$PARC_STAGE/Parc.app"
  if [ -d /Applications/Parc.app ]; then
    mv /Applications/Parc.app "$PARC_INSTALL/previous-Parc.app"
  fi
  if ! mv "$PARC_STAGE/Parc.app" /Applications/Parc.app; then
    if [ -d "$PARC_INSTALL/previous-Parc.app" ]; then
      mv "$PARC_INSTALL/previous-Parc.app" /Applications/Parc.app
    fi
    exit 1
  fi
  rmdir "$PARC_STAGE"
  open /Applications/Parc.app
)
```

Keep `$PARC_INSTALL` until the new app's window opens and its launch check passes; then remove that temporary directory and its previous app. If launch fails, quit the failed app, remove only `/Applications/Parc.app`, move `$PARC_INSTALL/previous-Parc.app` back to `/Applications/Parc.app`, and reopen it. Failed download, extraction or staging validation leaves the existing app untouched. Do not copy over a running app or merge its old and new bundle contents.

A development component build needs its whole `development` folder; install that into `~/ParcApp` (`ditto -x -k "$PARC_INSTALL/Parc.zip" ~/ParcApp` using the downloaded component archive, then `open ~/ParcApp/development/Parc.app`). Never install into `~/Parc`: macOS folder names ignore case, so on a Mac with the `~/parc` checkout that is the repository, and `rm -rf` would delete it. Remove the previous install first: `ditto -x` merges into an existing folder, which would leave an older build's files inside the new `Parc.app`.

- The package is a development component build. `Parc.app` loads its engine libraries from the `development` directory that contains it, so keep that directory together; copying `Parc.app` alone fails. All its load paths are relative, so the directory can live anywhere.
- It's ARM64 only.
- Published builds use the configured Apple signing identity. Explicit unpublished development builds may still be ad-hoc. `gh release download` leaves no quarantine attribute; a browser download does, and Gatekeeper can require the appropriate installation approval.
- Each Mac has its own profile; nothing syncs from the building Mac.

## Helper and signing contract

`Sources/ParcHelper/main.cc` follows the pinned CEF macOS entry order: load `Libraries/libcef_sandbox.dylib`, resolve both sandbox entry points, initialize the sandbox context, then load the engine framework and call the exported `parc_engine_execute_process`. The sandbox stays alive through process execution and framework unloading. A missing sandbox, missing entry point, initialization failure or browser-process return fails. The helper links only system libraries; packaging checks its actual load commands before including it.


Copied code is signed inside-out. The app is verified with `codesign --verify --deep --strict`, and sibling component dylibs are individually verified with `codesign --verify --strict` because they are outside the app bundle. Signing itself never uses `--deep`. The default ad-hoc identity is for development and requires library validation to be disabled because its separately signed component dylibs have no Team ID. Supply `--sign-identity` with an Apple-issued certificate (`Developer ID Application: …` or `Apple Development: …`); packaging reads its Team ID from a signed probe, and with one it does not add the development library-validation exception. A self-signed certificate has no Team ID, so it keeps the exception, like ad-hoc signing. Its only exception is `Parc Helper (CDM)`, signed with just `com.apple.security.cs.disable-library-validation` because the component-updated CDM carries Google's signature. Every other helper and the main app keep library validation ([why](../../docs/engine-flags.md#library-validation)). The tool does not create certificates, install trust, modify Keychain ACLs or claim signing/notarization continuity. Normal encrypted startup/restart across rebuilt packages remains a runtime gate.


## Widevine host signatures

Packages are unsigned Widevine hosts unless a VMP signer is configured; the report's `widevine` entry records `unsigned` and why. With a Google-issued VMP certificate and its RSA key, add to `build`:

```sh
PARC_WIDEVINE_KEY_PASSPHRASE="$(security find-generic-password -s parc-widevine-key -w)" \
  python3 scripts/build.py build … \
  --widevine-certificate /absolute/private/vmp-cert.pem \
  --widevine-private-key /absolute/private/vmp-key.pem
```

Keep the passphrase in the Keychain as above, or type it with `read -rs PARC_WIDEVINE_KEY_PASSPHRASE` and `export` it; don't write it into the command. It's optional, for encrypted keys, and read only from that variable. The tool removes it from its environment at startup and hands it to the `openssl` signing call alone. `openssl` from `PATH` runs without a terminal, so an encrypted key without the variable fails at once with a message to set it rather than prompting. Keys inside any Git checkout, including `.git` directories, worktrees and submodules, are refused. A signing service can stand in for the key with `--widevine-sign-command /absolute/signer`, run as `signer BINARY SIGNATURE FLAGS` with no terminal; it must write a complete `.sig`, not a symlink, without changing the binary. Either way the tool signs the framework binary (flag 1) and `Parc Helper (CDM)` (flag 0) where CEF reads them, verifies both, signs with Apple, then verifies them again. Component engines are refused. The format and evidence are in [engine flags](../../docs/engine-flags.md#widevine).

## Verification

```sh
python3 -m unittest discover -s tests/Packaging -v
```


Run the real layout/loading tests, including the compact sectionless fixture, with the actual pinned Chromium toolchain:

```sh
PARC_CHROMIUM_SOURCE=/absolute/engine-source/chromium/src \
  python3 tests/Packaging/test_development_layout.py -v
```

The real Mach-O tests copy unchanged engine-shaped fixtures into the normal CEF layout, preserve their load commands, sign copied libraries, remove the original output from its path, move the complete development directory, and execute both a framework-linked app and a runtime-style dynamic loader. Separate fresh helper processes load the sandbox first using only their own upstream RPATH. Omitting that helper RPATH is rejected. A genuine sectionless LLD dylib also retains its original bytes before signing and loads successfully without rewriting. The test suite rejects malformed header/segment bounds and altered sealed inputs.

These checks cover fixtures and packaging policy, not a Chromium launch. Set `PARC_CHROMIUM_SOURCE` to include the pinned LLD sectionless-library fixture; otherwise that one case is explicitly skipped.

Other focused cases exercise ordered dependency resolution, source/output protection, exclusive whole-directory publication, stale/forged seals, component-distribution refusal, standalone dependency boundaries, compiler/signing fixtures, and real icon export/round-trip across debug and release. The genuine helper fixture still checks all four variants, sandbox failure and process exit propagation. Earlier relocation-specific production logic and its tests have been removed; the retained first-launch failure evidence explains that change, not an alternate packaging mode.

