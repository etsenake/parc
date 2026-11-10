# Page-bound JavaScript dialogs

This is a source-owned AppKit presenter and the page's own
`content::JavaScriptDialogManager`. Each native page installs it before its
first navigation, and the page's WebContents delegate returns it to content.
The Objective-C facade and Swift shell use that independent engine path.

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
AppKit or Chromium headers. Output goes under ignored `build/tests/`.

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
beforeunload decisions. Busy rejection returns refusal rather than consent to close.

The source checker compiles both implementations with the pinned Clang,
generated headers and the ObjC++ flags of their own `parc/native` targets, with
ARC and warnings treated as errors. Use an already generated checkout:

```sh
python3 tests/NativeJavaScriptDialogs/check-chromium.py /path/to/chromium/src
```

The default output is `Release_GN_arm64`; `--output-name` selects another existing
output. This reuses the NativeLocationBar Ninja flags reader with `cflags_objcc`,
and writes logs, source/flags digests and exact commands only to
`build/tests/native-javascript-dialogs/chromium-syntax/`. It never generates,
builds or modifies the external source checkout. A missing generated header is
a failed check, not replaced with a stub. This command provides syntax-only
evidence.

## Source integration

CEF and Chromium revisions are pinned in
[the source lock](../../Engine/source-lock.json).

The presenter compiles in the native AppKit component source set and the
manager in `native_javascript_dialogs`. Content calls the manager with the
asking frame, so the title uses that frame's real origin and beforeunload keeps
its typed reload distinction. Only the page's own frames may ask. The
"Don't show this again" block uses content's own suppression, which answers as
Cancel, and resets with the primary page or when content asks to reset the
page's dialog state.

The manager starts detached. The page association gate calls
`SetNativeJavaScriptDialogsAttached(false)` before cancellation and rejects
reentrant requests and reattachment during that delivery. After the real
tab/window binding and containment, the shell must attach it again, including
same-window reattachment. Native movement, close and WebContents destruction
also cancel. No request is transferred to a different window.

The canonical `native-host-route.patch` connects typed preparation and the
BrowserWindow/platform factories. `native_appkit_host.mm` performs attachment
after genuine Browser/tab registration; the Swift `BrowserWindowController`
registers its supplied window and brackets native page reparenting with
`pageWillDetach`/`pageDidAttach`. Current first-tab feature hooks are also
integrated. Chromium's renderer and unload close flow remains the
owner: no app-modal fallback, unconditional unload acceptance or manual Browser
deletion is part of this service. The callback box is independent of the manager
and may complete while its owner is being destroyed.

The same page/window association brackets reparenting and terminal teardown.
A dialog belongs to its originating document; moving the page cancels the
request instead of transferring consent to a new window.
