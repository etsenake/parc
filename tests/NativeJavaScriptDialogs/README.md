# Page-bound JavaScript dialogs

This is a source-owned AppKit presenter and an adapter for the real pinned CEF
runner interface. The canonical production native route selects Parc's platform
delegate, which constructs this runner. The promoted Objective-C facade and
Swift shell use that independent engine path. The complete v50 engine build has
linked, but independent app launch and renderer-driven dialog/close acceptance

## Decisions

Dialogs preserve per-page identity and retained asynchronous completion.
Exactly-once cancellation, weak page/window binding, missing-host rejection and
terminal teardown prevent stale requests from accepting. Cancel returns false;
OK returns true under Chromium's actual beforeunload contract.

The native sheet uses Chromium's origin-aware title, OK/Cancel, a prompt field
when appropriate and the repeated-dialog suppression checkbox. Its presentation
contract is maintained in [web interactions](../../docs/web-interactions.md).

## Executable AppKit checks

```sh
bash tests/NativeJavaScriptDialogs/run.sh
```

The suite compiles source against real AppKit and opens offscreen test windows.
title, accessory stack and suppression reporting, Unicode prompt entry, nil versus empty override, repeated completion,
per-page and per-window contention, actual window close, page movement and
detachment, balanced reattachment, cancellation reentry, terminal invalidation,
reentrant replacement, destruction during
completion, independent windows, external sheet abort and retained callback
AppKit/CEF headers. Output goes under ignored `build/tests/`.

All APIs require the main thread. A presenter holds one request, not its page or
parent window. Completing a request clears callback and presenter state before
ending its sheet and delivering the result. Any later AppKit completion is
ignored. A click is accepted only if the originating page still belongs to the
captured window. Explicit invalidation rejects the current request, so a lost
host never grants consent to leave. AppKit's ordinary autorelease behavior still
applies; callers must invalidate before teardown rather than rely on deallocation
timing.

Another pending request or an existing sheet in that same window is rejected
with false; the original request is unchanged. Independent windows can each
present a dialog. The contention policy is covered by component tests. The canonical native window/application close
coordinator and exact-page retirement coordinator serialize genuine Chromium
beforeunload decisions. Their renderer-driven interaction with this runner
remains a runtime gate; busy rejection must not become acceptance.

Both implementations also pass syntax checking with the real pinned Clang,
as errors. Reproduce it against an already generated checkout:

```sh
python3 tests/NativeJavaScriptDialogs/check-chromium.py /path/to/chromium/src
```

The default output is `Release_GN_arm64`; `--output-name` selects another existing
output. This reuses the NativeLocationBar Ninja flags reader with `cflags_objcc`,
and writes logs, source/flags digests and exact commands only to
`build/tests/native-javascript-dialogs/chromium-syntax/`. It never generates,
builds or modifies the external source checkout. A missing generated header is
a failed check, not replaced with a stub. This command provides syntax-only
evidence. Renderer-driven exercise requires a separate authorized run and receipt.

## Source integration and remaining runtime work

Pinned CEF is `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f` and Chromium is
`d0c02bfad08ec92a6ffcf989e53cd995e6381a4c` (156.0.8078.48).

The original v5 integration, retained by the current overlay, compiles the
presenter in the native AppKit component source set and the runner in actual
`libcef_static`. It adds typed
`RunBeforeUnload(CefBrowserHostBase*, bool is_reload, const std::u16string&,
DialogClosedCallback)` dispatch to CEF's real base and manager. Parc overrides
it; the default implementation preserves the previous generic-confirm behavior
for upstream runners. Client-handler precedence and real callback ownership
remain unchanged. No message-text or empty-origin inference is used.

`NativeChromePlatformDelegate::CreateJavaScriptDialogRunner()` supplies its
actual existing WebContents and retains only a weak runner handle. The page
association gate calls `PageHostWillDetach()` before cancellation and rejects
reentrant requests/reattachment during that delivery. After actual tab/window
binding and containment, the shell must call `PageHostDidAttach()`, including
same-window reattachment. Native movement, close and WebContents destruction
also cancel. No request is transferred to a different window.

The canonical `native-host-route.patch` connects typed preparation and the
BrowserWindow/platform factories. `native_appkit_host.mm` performs attachment
after genuine Browser/tab registration; the Swift `BrowserWindowController`
registers its supplied window and brackets native page reparenting with
`pageWillDetach`/`pageDidAttach`. Current first-tab feature hooks are also
integrated. These source connections and the successful engine link do not
prove renderer-driven dialogs. CEF's renderer/manager close flow remains the
owner: no app-modal fallback, unconditional unload acceptance or manual Browser
deletion is part of this service. The callback box is independent of the runner
and may complete while its owner is being destroyed.

Verify the integrated route with actual disposable Chromium pages: alert/confirm/
prompt results, script-dialog cancellation on navigation/close, two panes and
two windows, a moved page, renderer/process failure, DevTools Handle/Cancel,
and Stay → interactive page → second Leave for both tab close and application
quit. Check that every callback resolves once and each sheet belongs to its
originating page's window. CEF compilation and live-browser verification must
be reported separately from the AppKit suite.
