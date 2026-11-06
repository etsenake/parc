# Native extension action bridge

The shell reads immutable copied values from the actual owning Browser's
ToolbarActionsModel and ExtensionActionViewModel. Each value carries opaque
weak model, TabInterface and document identities plus an ownership generation.
It never retains Browser/Profile or grants permission. User operations reject
stale navigation, selection, native detachment and same-ID action replacement.
The host validates the exact CEF page, selected Browser, profile and visible
native attachment. It never recreates a page from its URL.

The real model performs ExecuteUserAction, including activeTab grants and its
disabled-action context-menu fallback. `enabled` describes state; it must not
disable the shell control. The returned execution Boolean acknowledges dispatch,
not successful popup presentation. Context-menu success means actual NSMenu
tracking began. Pinning uses the real model, preserving off-the-record and
managed-pin restrictions. Snapshot order is the actual model ID order;
`pinnedIndex` preserves the separate pinned sequence.

Icons are eagerly copied from the upstream icon renderer, including badge,
grayscale and blocked-access state. Separate badge fields are metadata, not an
record builder `0x6897194`; the native shell centers the result within a
16-point content frame independently of its button surface. See
[extension geometry](../../docs/extensions-geometry.md). Copied images contain native
bitmap representations, not a lazy Browser-backed image source.

Model/icon/pin, document and selection updates coalesce into posted shell change
notifications. Shutdown immediately disables entry, then waits for the real
synchronous action/model call scopes to unwind, including nested native menus.
Only after that barrier does the host drain the existing popup/action services
and allow Browser/Profile deletion. This does not replace their own drains.

## Reference and current-engine adaptation

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
The installed reference subsequently updated; these addresses remain attributed
to this preserved binary only.

- `0x68b79c4 -> 0x6804810 -> 0x6098160`: real ID lookup/user action, source 2
  (menu entry). Evidence
  `ev_ff171a026325fb05f71ffab3819dce745280710200d1303346815d555c667074`.
- `0x689ab44`: actual owning Browser's selected TabStrip content. Disabled
  execution reaches native menu fallback `0x6896a3c`, not a synthetic success.
- `0x6896dac -> 0x68aa8ec -> 0x6809b14 -> 0x68b92c0`: model-ID snapshot and
  pinned positions delivered to the native shell. Add/remove/update observation
  is Browser/Profile-owned. The native caller retains real action identity.
  focused-content or whole-window anchoring for the actual child NSWindow.
  The public anchor value carries that layout without exposing engine types.

The current Chromium 156 toolbar button uses `kToolbarButton`; the native
extensions menu uses `kMenuEntry`. Both invoke the real user-action path. The
bridge does not substitute the API-trigger path, a duplicate permission system,
a stock BrowserView or a toolbar-arrow popover. Generation tokens, eager image
copies and explicit dispatch drain are source-owned lifetime safeguards.

## Verification and integration gates

The canonical v59 integration preserves v58 native crash/recovery. The actual AppKit shell controls pass 21 assertions, both application Objective-C objects compile and the combined full Swift app typecheck passes. Exact overlay replay passes. Normal generation and the incremental production engine build now pass; actual installed-extension popup/panel behavior remains pending. The genuine Chrome test executables have not been linked or executed.

Nine genuine Browser/TabList/model cases cover copied metadata and pin order,
navigation, selection/detachment epochs, unload/reload under the same ID,
disabled-action fallback, actual activeTab target, security refusal, nested pin
observer shutdown and change coalescing. They use the upstream test profile and
real native container/controller; they do not establish installer, worker,
popup or full browser-runtime compatibility. The standard Chrome fixture's CEF
runtime prerequisite remains an execution gate.

`check-chromium.py SOURCE_TREE` requires the complete current applied source/hash
cohort and exact generated object membership, then runs only syntax checks using
each owning target's actual flags. It refuses an unintegrated candidate. The
private candidate was checked with an isolated VFS against v49 target flags;
that is compatibility evidence, not registration, linking or executed tests.

Root integration adds this test target to the existing macOS CEF unit-tests
block and the bridge to the shared `native_extensions` target. Full generation,
linking, actual shell clicks, asynchronous icon updates, real extension
