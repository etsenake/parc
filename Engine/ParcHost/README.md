# Engine overlays and native host harness

`overlay.json` is the reviewed source manifest applied to the pinned Chromium/CEF
workspace. It records source inputs and patched-output hashes. The supported
commands and ownership rules are in [Engine](../README.md) and
[development setup](../../docs/development-setup.md). Never edit generated engine
copies instead of the source-owned files named by the manifest.

## Native host capability harness

`parc_native_host.mm` is an optional upstream capability harness, separate from
Parc's production native-window architecture. Its `parc_host_harness` target
uses an ordinary Chrome Browser/Profile and side-panel slot with AppKit controls
to exercise real engine identities. It is not the production application.

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

- The extra-info Boolean `parc.native_host.v1` enables the hook after the first
  real tab and focus operation. The hook rejects Views-backed/non-normal hosts.
- Dedicated side-panel and action IDs avoid borrowing existing feature IDs.
- The target uses the upstream CEF wrapper, framework bundle and helper entry
  point, with separate application/helper identifiers.
- Component builds must remain beside their required engine libraries.
- Production native-window components and their test targets are separate from
  this capability harness; see [native window checks](../../tests/EngineConformance/native-window/README.md).

[Harness procedures](../../tests/EngineConformance/native/README.md) describe the
retained fixture. Browser launch is currently prohibited by
[AGENTS.md](../../AGENTS.md); the fixture is not authorization to run it.
Source validation, compilation and runtime behavior are distinct forms of
verification. Preserve existing engine objects and caches.
