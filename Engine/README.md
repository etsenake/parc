# Independent Chromium engine

Parc builds its own Chromium/CEF engine and integrates it with a source-owned
Swift/AppKit shell. No installed third-party browser or executable is a build or
runtime dependency. `source-lock.json` pins Chromium, CEF and depot_tools;
`ParcHost/overlay.json` records the reviewed native integration and patched hashes.

For current delivery and unfinished product work, use
[product status](../docs/parity.md). For an authorized production release, use
[the release command](../docs/master-release.md).

## Build configuration

Use native Apple Silicon, Xcode, modern Python and a writable APFS workspace.
Restore the [saved engine workspace](../docs/engine-artifacts.md) before considering
a fresh sync. Keep source/objects in ignored `work/` and receipts/packages in
ignored `build/`. Preserve compiled objects and caches.

Read-only planning entry points:

```sh
python3 scripts/engine-source.py plan --workspace "$PWD/work/engine"
python3 scripts/engine-source.py check --workspace "$PWD/work/engine"
```

Sync, overlay application and engine builds require the task's explicit engine
ownership/authorization. Fetch main before choosing an overlay version or applying
one. Supported commands and sequencing are in
[development setup](../docs/development-setup.md). Never hand-edit generated copies
instead of their manifest-owned inputs.

Both engine configurations use ARM64 Release, `dcheck_always_on=false`,
`disable_fieldtrial_testing_config=true`, no dSYM bundles and the workspace's
chosen symbol level (default zero). The disabled field-trial testing config
removes the testing JSON startup path; individual supported feature overrides
remain separate from product exclusions. Packaging verifies the arguments and
corresponding generated build flag.

The development output is component-based. Its app requires sibling libraries;
keep the packaged directory together and preserve upstream load commands.
Production output is non-component in `out/ParcDistribution_GN_arm64`, with
`is_official_build=true`, ThinLTO/stripping and `chrome_pgo_phase=0`. The PGO
profile is not pinned by the source lock. Development objects remain in their
separate output directory. A Swift release build or signing certificate cannot
turn component artifacts into a standalone distribution.

Codec flags select macOS decoding/encoding rather than bundled proprietary
FFmpeg/OpenH264 paths. See [engine policy](../docs/engine-flags.md) and
[FairPlay integration](ParcNative/fairplay_chromium/README.md).

Build-setting-only lock changes use the guarded reconfiguration path:

```sh
git show <previous-commit>:Engine/source-lock.json > "$PWD/work/previous-source-lock.json"
python3 scripts/engine-source.py reconfigure --workspace /absolute/engine-source \
  --previous-lock "$PWD/work/previous-source-lock.json"
```

For a pinned-source upgrade with unchanged build settings and storage policy:

```sh
python3 scripts/engine-source.py retarget --workspace /absolute/engine-source \
  --previous-lock "$PWD/work/previous-source-lock.json"
```

Retarget requires an idle, owned workspace in a good recorded phase. It verifies
its previous lock and fingerprint, restores recorded overlay originals, removes
only verified overlay additions, and restores tracked CEF patch changes before
checking out the new pins. It repeats dependency sync, hooks and CEF patching,
then records `synced`; reapply the new overlay before generation/build. Outputs,
caches and unrelated untracked files are preserved. Interrupted retargeting is
left incomplete for inspection rather than guessed recovery. The **80 GB sync
floor** applies: dependency downloads and replacement source blocks still need
space even when compiled objects survive. No storage floor is lowered.

It verifies that only supported defines changed and preserves sources/objects.
The next authorized build regenerates and compiles. Shipping planning, generation
and building use one operation lock:

```sh
python3 scripts/engine-source.py shipping-plan --workspace /absolute/engine-source
python3 scripts/engine-source.py shipping-generate --workspace /absolute/engine-source
python3 scripts/engine-source.py shipping-build --workspace /absolute/engine-source
```

Only `shipping-plan` is read-only. A successful receipt binds source lock, overlay,
source fingerprint and GN arguments. Generated-only, stale, failed or interrupted
outputs cannot be sealed. Returned failures can resume without deleting objects;
unowned output is preserved and refused. Disk reserves are preflight policy,
not a measured guarantee that another output fits.

See [packaging](../tests/Packaging/README.md#standalone-distribution). CEF's
`docs/master_build_quick_start.md` and `tools/gn_args.py` in the pinned source
checkout explain its build and distribution configuration; exact dependency
versions live in [the source lock](source-lock.json).

## Required native integration

Keep real Chromium Profile, Browser, TabList and WebContents identities behind
the native shell. Extensions, permissions, commands, navigation and lifecycle
must use the objects owning the visible page. Callbacks carry exact ownership,
generation and main-thread requirements; a URL is not page identity.

The shell owns NSWindow. A native BrowserWindow adapter supplies real Chromium
services without a hidden BrowserView. One physical window may have multiple
profile-bound Browsers, while selected state determines activation. Page hosts
retain the actual native view independently of tab selection and profile ownership.
Parc supports up to four visible panes, live popup adoption and cancellable close.

Do not substitute stock embedding assumptions for these contracts: macOS CEF
native-parent embedding selects Alloy, and stock Chrome Views have their own
window/tab constraints. The optional [ParcHost harness](ParcHost/README.md) tests
upstream capabilities; it is not the production architecture.

## Native construction and startup source integration

`ParcNative` contains the native factory, BrowserWindow, page delegate and
source-owned presentation services. The source manifest maps these to the pinned
CEF graph. `native_components`, `autofill_save_sessions` and `native_extensions`
are shared production/test source sets; other engine-facing units belong to their
actual CEF owners. The Swift/Objective-C facade uses the independent route.

Before teardown, close request gates, invalidate native associations, cancel
pending UI and drain callbacks while Browser/Profile services remain alive.
Source and generated-target checks must verify the exact applied manifest.

## Native relaunch and independent encrypted storage

Application reopen resolves registered native windows through the shell's owner.
It does not create a replacement profile or infer consent to close anything.
Profiles and Keychain storage use Parc's own namespace. Keep normal encryption
separate from disposable test-Keychain modes, and preserve signing continuity.
See [relaunch checks](../tests/NativeRelaunch/README.md) and
[Keychain checks](../tests/KeychainNamespace/README.md).

## Typed native site permissions

Permissions bind the actual WebContents, origin, typed request and completion.
Quiet and unsupported states remain truthful; stale owner/navigation changes
cancel. The native presenter does not fabricate grants.
[Permission checks](../tests/NativeSitePermissions/README.md) describe the boundary.

## Native extension installation consent

The actual Chromium prompt supplies permissions, withholding and enterprise
justification. Consent and installation outcome are distinct. Exact page/profile/
window identity and exclusive security reservations survive asynchronous icon
loading and are rechecked at delivery. See
[consent checks](../tests/NativeExtensionInstall/README.md) and
[extensions](../docs/extensions.md).

## Same-profile live page transfer

Move the actual tab/WebContents only within its profile. Preserve pending
navigation, POST data and opener identity. Transfer/rebind native delegates and
observers; reject stale or cross-profile owners before mutation. A failed move
restores surviving source state. [Transfer checks](../tests/NativeTabTransfer/README.md).

## Profile downloads and native file selection

The real profile DownloadManager owns transfer state and GUIDs. Closing the page
does not discard a transfer. Chromium target determination, safety policy and
actual command capabilities remain authoritative. Native sheets bind exact
profile/page/window identity; settings use real DownloadPrefs.
[Download and chooser checks](../tests/NativeDownloads/README.md) and
[Downloads](../docs/download-library.md) cover controls and security review.

## Native HTTP and proxy authentication

Authentication presents the real page-bound request and returns its actual
credentials or cancellation once. It cannot migrate to a newly active page or
fallback window. [Authentication checks](../tests/NativeHTTPAuth/README.md).

## Native client certificates

The actual Chromium selector/controller and native auxiliary window retain their
own identity, policy and cancellation semantics. The shell hosts their supplied
presentation. [Client-certificate checks](../tests/NativeClientCertificates/README.md).

## Native external protocols

A request retains its original page, origin, handler and decision callback.
Stale owners cancel; approval is not inferred from an available OS handler.
[External-protocol checks](../tests/NativeExternalProtocol/README.md).

## Native WebAuthn

Use the real Chromium authenticator request and platform presentation, with the
actual auxiliary window. Do not replace it with a generic successful prompt.
[WebAuthn checks](../tests/NativeWebAuthn/README.md).

## Native DevTools

Chromium owns the real tools WebContents and controller. Parc hosts its supplied
view, preserving inspected-page identity, docked bounds, undocked window lifetime,
focus and modal/security ownership. The auxiliary host does not require a saved
tab. [DevTools checks](../tests/NativeDevTools/README.md),
[auxiliary ownership](../tests/NativeDevTools/Auxiliary.md) and
[Developer Mode](../docs/developer-mode.md) describe the current interfaces.

## Native server-certificate inspection

Use the visible page's real security certificate and owning window with the macOS
certificate panel. Cancellation and page/window invalidation are explicit.
[Certificate checks](../tests/NativeCertificateViewer/README.md).

## Page compositing across tab switches

Each pane owns its compositor. A new page in the same pane retains the previous
frame until its first frame, while an incompatible picture is concealed without
disconnecting the display. Shown pages must attach to their compositor first;
all compositors die before CefShutdown.
The host settles changed constraints before showing fresh content, including
DevTools composition and infobar geometry.
See [page compositing](../docs/page-compositing.md) and
[page-host checks](../tests/NativePageHost/README.md).

## Product name

The grit hook in `integration/parc_branding.py` names the running browser Parc
without forking translated resources or message IDs. It replaces Chromium in
browser strings and Chrome only in the explicitly classified messages that mean
this browser. Google products/services, copyright, Chromium project links and
device names retain their real names. IDs, user agents, paths, Keychain items and
preference keys are unchanged. Language-specific endings follow the reviewed
substitutions.

`tests/ProductName` checks compiled translations and application strings against
those decisions; it needs `PARC_ENGINE_WORKSPACE`. Every new Chrome-bearing
message requires classification.

## Maintenance

The independent engine is the production path. Current gaps belong in
[the backlog](../docs/backlog.md).

Browser/app launch is currently prohibited by
[AGENTS.md](../AGENTS.md); historical fixture commands do not authorize it.

Maintain upstream security through deliberate pinned Chromium/CEF upgrades and
appropriate integration checks. Preserve product exclusions without expanding
them into unrelated Google/Chromium networking removal. Keep generated outputs,
profiles, logs and dependency binaries outside Git.
