# Embedded webpages in Easels

An Easel browser object saves an HTTP(S) URL. Each physical window and Profile
owns its real native auxiliary page through the Easel page pool. That page is
not a saved tab and is omitted from ordinary tab, closed-window and group
session restoration. See [Easel editing](easels.md).

## Admission and lifetime

`beginEmbeddedNavigation(_:validateOwner:completion:)` returns a cancellable
request. The original wrapper is already attached to the canvas. Pure owner
validation runs before and after asynchronous Profile acquisition, followed by
native validation before any navigation or page creation.

Cancellation before admission settles once without creating a page. After
admission, cancellation retires the actual page through its real owner. It must
not report that a created page never existed. Embedded provenance remains
stable while parked; ordinary tab transfer cannot adopt the page.

The native owner retains weak references to the original Browser, Profile and
window. Selection contributes the embedded page to `visibleNativePages` and
`selectedNativePage`; deselection blocks its input. Whole-document close uses
real `beforeunload` consent for the entire child-page set. A failed or missing
native owner never becomes an invisible replacement browser.

Easel pages sleep on the same four-hour idle rule as background tabs. When an
Easel's tab has gone that long without being shown in its window, its editor has
nothing mid-edit, and no page is in use by the automatic-archive standard, the
window closes those pages through the same page retirement as archiving and
drops the editor. Showing the Easel again rebuilds it, and each page loads its
saved address fresh, without its earlier back history or scroll position.

## Physical-window collection transfer

A same-Profile collection move transfers the original editor, pool, wrappers
and native pages. Creation and retirement are gated while the native transfer
commits atomically. Failure rolls ownership back in reverse order, preserving
WebContents, navigation history and document identity.

If ownership cannot be established after a partial failure, a recovery
reservation prevents competing operations until reconciliation. An empty tab
strip does not authorize closing the caller's NSWindow.

## Cross-profile relocation — EASEL29

Moving an Easel between Profiles creates destination pages under the destination
Profile; cookies and page history do not cross that boundary. Before the move:

1. Refuse active composition, canvas gestures or an uncommitted address draft.
2. Flush the same durable text boundary used by normal editing.
3. Obtain consent and retire every original child page.
4. Revalidate before and after closure, then revoke the source session.
5. Move documents with their IDs, URLs and capture bytes intact.

File rollback reverses every document move before cleaning copied assets. If
any reverse move fails, preserve the copied assets for recovery. Refuse a move
that would leave aliases in another Profile. Private sessions are not copied.

Private windows deliberately host no Easels, so an embedded page never mixes a
private session with a normal one. The decision is recorded in
[capture Library](capture-library.md#private-media-ownership).

## Keyboard and accessibility ownership

`focusPage(for:)` admits only the selected object in its original active owner
with the actual native view attached. A crashed page exposes its recovery
control. Focusing never navigates or reconstructs a page.

Returning to the canvas revalidates the owner, revokes page input and restores
canvas focus. Canvas Delete and movement keys must not consume keys intended
for a selected native editor or webpage.

## Checks

Pool and transfer components exercise injected engines and disposable document
stores, including cancellation, ownership rejection, rollback and retirement.
