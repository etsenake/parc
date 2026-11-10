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
instruction to paint a second badge. The native shell requests a 32-point logical raster and centers it within a
16-point content frame independently of its button surface. See
[extension geometry](../../docs/extensions-geometry.md). Copied images contain native
bitmap representations, not a lazy Browser-backed image source.

Model/icon/pin, document and selection updates coalesce into posted shell change
notifications. Shutdown immediately disables entry, then waits for the real
synchronous action/model call scopes to unwind, including nested native menus.
Only after that barrier does the host drain the existing popup/action services
and allow Browser/Profile deletion. This does not replace their own drains.

## Engine integration

Toolbar buttons use Chromium's `kToolbarButton` source and menu tiles use
`kMenuEntry`. Both invoke the real user-action path with its existing permissions.
Generation tokens, eager image copies and explicit dispatch draining protect
lifetimes across synchronous model callbacks and nested menus.

## Verification and integration gates

The AppKit shell, model snapshots and bridge have component and compiler
coverage. A passing source check does not mean a genuine Chromium test linked or
executed; the test fixture needs valid CEF initialization.

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

The production bridge and tests share the native extension target. Actual shell
clicks, asynchronous icon delivery, extension restart, security ordering and
multi-window behavior require their own recorded integration results.
