# Engine overlays and native host harness

`overlay.json` is the reviewed source manifest applied to the pinned Chromium/CEF
workspace. It records source inputs and patched-output hashes. The supported
commands and ownership rules are in [Engine](../README.md) and
[development setup](../../docs/development-setup.md). Never edit generated engine
copies instead of the source-owned files named by the manifest.

The direct Chromium integration uses `overlay-direct.json` with the explicit
`source-lock-direct.json` lock. Startup files install under `parc/`, native
services under `parc/native/`, and retained test sources under `parc/tests/`.
Shared upstream changes are consolidated so each patched target appears once,
with a pristine Chromium preimage. Direct patch variants preserve the stopgap
manifest and its original patch inputs; no CEF patches are applied in direct mode.

## Native host capability harness

`parc_native_host.mm` implements an optional AppKit capability panel in an
ordinary Chrome Browser/Profile window. Its direct source set is
`//parc/tests/parc_native_host:panel`, separate from Parc's production native
windows. This source set does not provide an executable. The retained
`parc_host_harness` executable still needs isolated Keychain startup and a normal
Chrome Views window entry before it can use the direct engine; see the
[harness guide](../../tests/EngineConformance/native/README.md).

The browser-scoped `SidePanelEntry` owns its action and `NativeViewHost`; the
view strongly owns its AppKit view. Attachment waits for a valid widget and
checks the actual NSWindow. The harness does not replace window delegates or
content views, create hidden parking windows, or recreate pages from URLs.

The controls enumerate real `TabStripModel` pages, select immutable session tab
IDs, create and navigate tabs, go Back/Forward, reload, and request close through
beforeunload negotiation. Rows change only on model notifications. The identity
snapshot prints IDs, indices and attachment equality without page URLs or text.

All bridge, model and AppKit operations run on Chromium's UI/main thread. Model
destruction clears borrowed Browser/model pointers. The reverse AppKit owner is
cleared before detach; cached panel views can outlive the model. The harness
never owns Browser, Profile, TabStripModel or WebContents.

## Integration

- `InstallNativeHost` requires an explicit test entry after the first real tab
  exists, with a normal Chrome Views window. Production does not call it.
- Dedicated side-panel and action IDs avoid borrowing existing feature IDs.
- The legacy executable and bundle recipe remain separate from the direct panel
  source set and keep their isolated fixture identities.
- Component builds must remain beside their required engine libraries.
- Production native-window components and their test targets are separate from
  this capability harness; see [native window checks](../../tests/EngineConformance/native-window/README.md).

[Harness procedures](../../tests/EngineConformance/native/README.md) describe the
retained fixture. Browser launch is currently prohibited by
[AGENTS.md](../../AGENTS.md); the fixture is not authorization to run it.
Preserve existing engine objects and caches.
