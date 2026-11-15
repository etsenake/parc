# Independent engine packaging

`scripts/build.py` compiles the existing Swift/AppKit application and independent native facade, and packages a **completed Parc Chromium build**. It does not install or launch the app, run GN/Ninja, download a browser, or include a Keychain interposer. The old `scripts/build-engine.sh` is superseded; its independent facade compilation is now part of this tool. Component engines remain ineligible for distribution, even with a signing certificate or release Swift optimization. The separately built non-component engine supports the standalone path below.

For complete production releases use [the master release command](../../docs/master-release.md):
`bash scripts/release.sh`, which chooses the version from Conventional Commits
(`--type major|minor|patch` overrides it). The commands below remain the
individual building blocks.

## Inputs and commands

Use an absolute `--engine-dir` for the locked `Release_GN_arm64` output. First finish the reviewed native-host overlay with `scripts/engine-source.py build`. A successful source-tool completion must record phase `built`; manually linked files and a still-running build cannot be sealed. The direct application requires `Engine/ParcNative/native_application_protocols.h`, whose event-control declarations are app inputs rather than linked engine API. The canonical `Engine/source-lock.json` and `Engine/ParcHost/overlay.json` are the only supported inputs. Sealing refuses a leftover retired sandbox library. The matching reviewed source overlay must include the actual public native bridge headers and compiled exports.

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

The application configuration defaults to `release`, preserving this independent packager's original
optimized Swift build. Add `--configuration debug` for `-g -Onone`; `--configuration release` uses
`-O` with whole-module optimization (`-whole-module-optimization -num-threads <cores>`, as Xcode's
Release does), compiling the module once instead of once per file. This option changes only Swift
optimization, not the sealed Release engine, helper/compiler settings, signing identity or required
explicit fresh output. Packaging purpose defaults to `development`. Seals and reports record the
verified engine flags, `build_classification: development-component` and `distribution_eligible:
false`. The output itself must be a fresh directory whose parent already exists; a `.app` output is
refused with migration guidance. The main bundle calls the shared `scripts/app_icons.py` exporter
and sets `CFBundleIconFile=Parc.icns`. Both configurations export all ten catalog variants, each
with ten standard macOS size/scale representations. The catalog's approved **Original** is the
shared main ICNS, and every variant has identical bytes across debug/release. Source PNG variants
are copied intact. The package report records the configuration and actual ICNS digest.

Every output is new: the tool refuses to overwrite a manifest or development directory. It stages the app, sibling libraries and report together, then publishes the complete directory with macOS exclusive atomic rename; even a concurrently created empty destination is preserved. It keeps the source tool's shared operation lock during verification and copying. Sealing reuses the bootstrap's pinned repository/dependency fingerprint checks, verifies the reviewed overlay's target hashes and the executable's public ABI headers, then records the framework inventory, symlinks, resources, runtime-loaded graphics/sandbox libraries, Mach-O dependency graph and component hashes. Packaging rechecks those inputs and rejects unknown external dependencies, ambiguous paths, symlink escapes and absent native C/Objective-C exports. The supported artifact is the pinned Release ARM64 component configuration; an additional non-system framework requires an explicit resource mapping rather than silently copying only its binary.

The layout follows the pinned Chromium component-development arrangement:

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

The atomically published directory contains a standalone `Parc.app` and its provenance report, with no sibling engine components. Distribution requires release app optimization and certificate-backed signing; normal inside-out hardened signing and strict validation remain unchanged. A non-component engine can also be packaged explicitly for local development with ad-hoc signing. Reports distinguish engine eligibility, intended purpose and actual signing identity, and state `notarized: false`; this command does not submit a notarization request or publish the app. Engine generation/compilation and package production status belong in the [product status](../../docs/parity.md).

## Publishing app builds

### Stable versions and Homebrew

`app-version.json` is the single app/helper bundle version and build-number
source. The [release command](../../docs/master-release.md) derives a version
from Conventional Commits and advances the bundle build number. Preview packages
keep the prepared version and do not update the stable Homebrew cask. A version
change alone does not establish publication.

```sh
bash scripts/package-app.sh --stable <sealed engine-artifacts.json>
# Or reuse a compatible published engine:
bash scripts/package-app.sh --stable --from-release [app-<stamp>-<commit> or v<version>]
```

Versioned candidate mode keeps the same distribution, signing, notarization and checkout
gates. It publishes `Parc-<version>-arm64.dmg` and a ZIP in the etsenake/parc
`v<version>` pre-release (not latest), titled with the bare version and holding
only that version's release notes, and refuses an existing tag. The DMG contains the stapled
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
cleanup only matches `app-*`. Production publication uses verified artifacts
without installing or opening the app. The release command handles tap
publication; its focused equivalent is below. Set `PARC_RELEASE_TAG` to the
already published versioned candidate tag:

```sh
python3 scripts/publish-homebrew.py "$PARC_RELEASE_TAG" \
  --artifact-only --resume --tap /absolute/homebrew-tap \
  --appcast /absolute/appcast.xml
```

The publisher verifies the release tag/source/version, downloaded ZIP and DMG,
package report, production signing identity, notarization and every signed
image before promoting the release and updating the cask. The signed appcast
and exact public assets must agree. It preserves unrelated tap edits and
refuses older versions; `--resume` permits an identical verified cask.
The [Homebrew guide](../../docs/homebrew-release.md) owns publication and
verification details, including the separate optional user-confirmation path.

Users install on another Apple Silicon Mac with `brew tap etsenake/tap` and
`brew install --cask parc`, and upgrade with `brew update` followed by
`brew upgrade --cask parc`. Stable assets are mirrored unchanged to the public
`etsenake/parc-releases` repository, so no GitHub login is needed. Homebrew
uninstall preserves the Parc profile. Publication does not authorize running
these installation or upgrade commands; users handle their own upgrades.

### Preview builds

The preview command builds and publishes a package that can be used on another
Mac without compiling it there. From a checkout whose `HEAD` is already pushed to `origin/main`, with the engine sealed:

```sh
bash scripts/package-app.sh <sealed engine-artifacts.json>
```

When only app code changed, skip the engine and reuse the one in a published package; this compiles and signs just the app, so it takes minutes on any Mac with an engine workspace:

```sh
bash scripts/package-app.sh --from-release [app-<stamp>-<commit>]
```

Without a tag it picks the newest `app-*` preview or stable `v<version>` release whose tagged source selects the same engine overlay manifest and version as `HEAD`. An explicit stable tag also works, using `--from-release "$PARC_RELEASE_TAG"`; it selects the ZIP even when the release also includes a DMG. It refuses when `Engine/` differs between that release's commit and `HEAD`, checks the downloaded zip against GitHub's digest, then `build.py release-build` checks the package report: a standalone non-component engine whose overlay identity and source lock digest equal `HEAD`'s, with every overlay input still matching its pinned digest, recorded build flags matching `engine-source.py`'s current shipping defines (the recipe lives outside `Engine/`), and no Widevine host signatures from the earlier package. The framework must pass `codesign --verify --deep --strict` and its code must hash to the report's signed images. Upstream packaging inputs come from an engine workspace's Git objects at the source lock's commits and are refused if the overlay patches them. The app uses the checkout's native application protocol header. Engine licenses must match the reused package. Set `PARC_ENGINE_WORKSPACE` to select an engine workspace outside the checkout's `work/engine` directory. The new package report records the reused release and the release that originally built the engine (`engine_release`), so packages can chain. Compiling and signing are `build_app`'s, unchanged.

For runtime testing on a Mac whose newest published engine is older than `main`'s overlay, `bash scripts/package-app.sh --local-test [tag]` packages `main`'s app against the newest published engine without publishing anything. It refuses a changed source lock, and `build.py release-build --local-test` asks the compiler which `Engine/ParcNative` headers the app's native facade and bridging header include, then refuses if any engine API header differs from the engine's commit (the app-only event protocol declarations are excluded): a changed header means the app may call engine API that engine lacks. When every new call is guarded with `respondsToSelector:` (or `responds(to:)`), `PARC_ALLOW_CHANGED_ENGINE_HEADERS=1` accepts the changed headers and the report lists them; a new class or exported function would still stop the app launching. Engine-internal changes are allowed and simply absent. The bundle's `Info.plist` gets `ParcLocalTestBuild`, the report's `engine_release.local_test` records the checkout's overlay and the headers compared, and the package stays in `build/local-test-<stamp>`.

Every published production app requires a valid **Developer ID Application** identity and Apple notarization. Apple Development and ad-hoc identities are refused for publication. The explicit unpublished `--local-test` path and direct development/fixture builds remain available. Published packages use `--purpose distribution`, release optimization and the official standalone engine; compatible published engines can also be reused for distribution.

On each building Mac, create a unique private key and CSR in the login Keychain, then issue a Developer ID Application certificate from the team's Apple Developer account. The certificate and all builders must use the same Team ID. Import Apple's Developer ID G2 intermediate from [Apple PKI](https://www.apple.com/certificateauthority/) if needed, using normal certificate-chain validation without a custom trust override. Validate with `security find-identity -v -p codesigning`, then select the exact identity:

```sh
bash scripts/setup-signing.sh 'Developer ID Application: YOUR NAME (TEAM ID)'
xcrun notarytool store-credentials parc-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

The second command securely prompts for an Apple app-specific password and stores it in Keychain.
Never put that password in shell arguments, source, logs or chat. `PARC_NOTARY_PROFILE` selects a
different saved profile; `parc-notary` is the default. The publishing command validates
authentication before compilation. Private signing keys remain in the building Mac's Keychain. Use
the encrypted [backup and restore workflow](../../docs/master-release.md#credentials-on-another-mac)
when provisioning another Mac; never replace Parc Safe Storage encryption with a file. Developer ID
provisioning does not require an App Store Connect app listing.

The publisher calls `scripts/notarize-app.py` before creating the GitHub release. It verifies every signed image against its report, actual Developer ID Team IDs, secure timestamps and strict signatures, submits a ZIP, and retains the submission ID and immutable input fingerprint under the package run's `notarization/`. It polls that same submission, downloads Apple's log, and requires Accepted status plus the exact archive hash/job ID. It then staples and validates the ticket, verifies strict signatures/image hashes again and requires Gatekeeper acceptance. Only then does it write `notarized: true` with the evidence into `package-report.json`, and publish a ZIP containing the stapled app. Failed notarization, stapling or assessment cannot publish a production release.

An interrupted status poll resumes the existing submission by rerunning the helper with the same package, profile and Team ID. Keep those inputs frozen. An upload with no confirmed submission ID requires reconciliation against `notarytool history`; the helper deliberately refuses to submit a second copy automatically. Inspect Apple's `apple-log.json`, including any warning issues, before claiming acceptance. Do not restart compilation or advance main to resolve a pending Apple submission.

Moving from Apple Development to Developer ID changes the designated requirement once. Verify the actual new requirement and same Team ID, record the intentional transition, and retain that stable production requirement for later builds. The first production launch can require normal Safe Storage approval again; leave it to the user. Never broaden its Keychain ACL or bypass macOS authorization. Notarization confirms Apple's distribution checks, not browser functionality or third-party allowlists.

The main bundle declares `http` and `https`, web Handoff, HTML/XHTML Viewer document types and the Productivity category. These declarations make it available to macOS as a browser and in Open With. They do not change the user's chosen default browser. Extra iOS default-browser entitlements or App Store metadata are not required for this Mac distribution.

It refuses uncommitted or untracked files under `Sources`, `Resources`, `Engine` or `scripts`, ignored files under `Resources` (which packaging copies wholesale; Finder's `.DS_Store` files are deleted first), and a checkout that moves while packaging, so the release matches its commit. It packages into a fresh `build/local-<stamp>` (`package.log`, with compiler output in `package-output.log`), zips the whole `development` directory with `ditto`, and uploads it as a private pre-release tagged `app-<stamp>-<first 8 characters of the commit>`, titled with the engine overlay. It then keeps only the three newest of those releases; a failed cleanup only warns, since the new release is already live. Other releases, such as the engine snapshot, never match its tag pattern. Report the published tag and any material limitations.

Publication ends after package verification and reporting the tag. Do not
install, replace, quit or open the local app, run browser checks, or run
Homebrew install/upgrade/reinstall as a publication follow-up. Users upgrade
Homebrew themselves. Preserve profiles, existing signed artifacts and engine
objects/caches. Installation and runtime testing require separate explicit
authorization; [release operations](../../docs/master-release.md) owns this
boundary.

The following manual installation instructions are for a user installing an
already published package on another Mac. Quit Parc first; its profile lives
in `$HOME/Library/Application Support/Parc`, outside the install folder.

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

A development component build needs its whole `development` folder. Extract it
into a new installation directory outside every source checkout, and keep its
sibling libraries together. macOS commonly treats folder names without regard
to case, so capitalization alone does not distinguish an install directory from
a checkout. Never merge an archive into an existing installation; that can leave
old files inside the new app. Preserve the previous installation until the new
one is accepted, following the same manual-install boundary above.

- The package is a development component build. `Parc.app` loads its engine libraries from the `development` directory that contains it, so keep that directory together; copying `Parc.app` alone fails. All its load paths are relative, so the directory can live anywhere.
- It's ARM64 only.
- Published builds use the configured Apple signing identity. Explicit unpublished development builds may still be ad-hoc. `gh release download` leaves no quarantine attribute; a browser download does, and Gatekeeper can require the appropriate installation approval.
- Each Mac has its own profile; nothing syncs from the building Mac.

## Helper and signing contract

Direct engines use the GN-built `//parc/helper:parc_helper`, built at `Parc Helper.app/Contents/MacOS/Parc Helper` in the engine output and copied into all eight helper bundles: Default, Renderer, GPU, Alerts and CDM, plus the Aperitif Default, Renderer and GPU variants Chromium launches while its `AperitifHelpers` feature is on. The helper links Chromium's Apéritif library, `libaperitif.dylib`, which the framework carries in `Libraries` and the helper loads by its exact `@loader_path` location. Chromium's build also links the framework against that library, so the framework's own link rewrites Chrome's install path to the copy beside its binary, `@loader_path/Libraries/libaperitif.dylib`. Its static initializer registers the allocator zone and engages Seatbelt before any other helper code runs, a required sandbox with no server or failed initialization is fatal, and the helper's constructor stops the process if Apéritif did not run. `Sources/ParcHelper/main.cc` then loads the framework. Sealing hashes the helper and audits its complete bootstrap graph: only system libraries, the framework's `libaperitif.dylib` and the component build's `@rpath/libseatbelt.dylib` are permitted. The helper contract pins Chromium's classic and Aperitif helper lists, so a change to either stops packaging. Component helper RPATHs resolve that library from the package's sibling libraries. Framework name, identifier, versioned layout, helper identities and signing entitlements stay the same.

Sealing and packaging support only the direct GN helper. They refuse any
retired sandbox library, preserve the framework bundle identity and require
helper hashes, modes and load commands to match the seal. Component helpers
resolve only the sealed sibling Seatbelt library before sandbox initialization.
The eight helper identities and entitlements remain unchanged.

## Sparkle

Software updates use the official Sparkle release pinned in `scripts/sparkle.py` (version and SHA-256). `build.py` and `check-swift.py` download it on first use, verify the digest and extract `Sparkle.framework` and `bin/` into the ignored `build/sparkle/`; there is no manual step. The app links it with the existing `@executable_path/../Frameworks` RPATH. Packaging embeds it without headers, module map or the XPC services, which [Sparkle documents](https://sparkle-project.org/documentation/sandboxing/#removing-xpc-services) as unused by apps that aren't sandboxed, thins its code to ARM64 and signs it in Sparkle's documented order (Autoupdate, Updater.app, then the framework) with the app's identity, hardened runtime and timestamp. A distribution package's Info.plist carries `SUFeedURL`, `SUPublicEDKey` and automatic check/install settings; development and local test builds have no feed, so they never replace themselves. The report records the embedded Sparkle version and digest. The EdDSA private key is in the release Mac's login Keychain (Sparkle's service, account `parc`); only the public key is committed. Updater behavior is in [software updates](../../docs/software-update.md).

## Widevine host signatures

Packages are unsigned Widevine hosts unless a VMP signer is configured; the report's `widevine` entry records `unsigned` and why. With a Google-issued VMP certificate and its RSA key, add to `build`:

```sh
PARC_WIDEVINE_KEY_PASSPHRASE="$(security find-generic-password -s parc-widevine-key -w)" \
  python3 scripts/build.py build … \
  --widevine-certificate /absolute/private/vmp-cert.pem \
  --widevine-private-key /absolute/private/vmp-key.pem
```

Keep the passphrase in the Keychain as above, or type it with `read -rs PARC_WIDEVINE_KEY_PASSPHRASE` and `export` it; don't write it into the command. It's optional, for encrypted keys, and read only from that variable. The tool removes it from its environment at startup and hands it to the `openssl` signing call alone. `openssl` from `PATH` runs without a terminal, so an encrypted key without the variable fails at once with a message to set it rather than prompting. Keys inside any Git checkout, including `.git` directories, worktrees and submodules, are refused. A signing service can stand in for the key with `--widevine-sign-command /absolute/signer`, run as `signer BINARY SIGNATURE FLAGS` with no terminal; it must write a complete `.sig`, not a symlink, without changing the binary. Either way the tool signs the framework binary (flag 1) and `Parc Helper (CDM)` (flag 0) where Chromium reads them, verifies both, signs with Apple, then verifies them again. Component engines are refused. The format and evidence are in [engine flags](../../docs/engine-flags.md#widevine).

## Verification

```sh
python3 scripts/test-python.py tests/Packaging
```

The runner discovers the folder like `unittest discover -s` and spreads tests
across every core; a class with `setUpClass` stays in one job. `--jobs N` limits
the workers and `--durations N` lists the slowest jobs.


Run the real layout/loading tests, including the compact sectionless fixture, with the actual pinned Chromium toolchain:

```sh
PARC_CHROMIUM_SOURCE=/absolute/engine-source/chromium/src \
  python3 tests/Packaging/test_development_layout.py -v
```

The real Mach-O tests copy unchanged engine-shaped fixtures into the Chromium component layout, preserve their load commands, sign copied libraries, remove the original output from its path, move the complete development directory, and execute both a framework-linked app and a runtime-style dynamic loader. Direct helper checks reject changed RPATHs and Seatbelt resolution. A genuine sectionless LLD dylib also retains its original bytes before signing and loads successfully without rewriting. The test suite rejects malformed header/segment bounds and altered sealed inputs.

These checks cover fixtures and packaging policy, not a Chromium launch. Set `PARC_CHROMIUM_SOURCE` to include the pinned LLD sectionless-library fixture; otherwise that one case is explicitly skipped.

Other focused cases exercise ordered dependency resolution, source/output protection, exclusive
whole-directory publication, stale/forged seals, component-distribution refusal, standalone
dependency boundaries, compiler/signing fixtures, and real icon export/round-trip across debug and
release. The genuine helper fixture checks all five variants, including CDM, sandbox failure and
process exit propagation.
