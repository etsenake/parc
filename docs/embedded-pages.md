# Embedded pages

Easel browser objects and note embed blocks show real Chromium pages inside a
document. Each physical window and Profile owns those auxiliary pages through a
shared page pool. They are not saved tabs and are left out of ordinary tab,
closed-window and group session restoration. See [Easel editing](easels.md) and
[Notes](notes.md).

## Owners and the shared pool

`EmbeddedPagePool` owns the native side for both document types: page creation,
the window binding, selection and visibility, close consent, window transfer
and retirement. A document plugs in through `EmbeddedPageOwner`, which answers
whether it still wants a page at an address, fingerprints its embedded objects
for transfers and records navigation. Easel's session and the note editor both
implement it. `EaselBrowserObjects` and `NoteEmbeddedPages` are thin subclasses
that add their canvas behaviour. Both host the same surface, `NoteEmbedSurface`,
set up for a note or for an Easel: the Easel set-up adds live-capture framing,
the ••• menu, title-click address editing and the select-first rule, while the
note set-up keeps first-click activation, the scroll latch and the caption
button. Note live-capture blocks still use their own `NoteCaptureLiveSurface`.

`EmbeddedPageOwnerGate` is the owner's lifecycle state: open, retiring, moving
between windows (with a generation that a finished move advances) and disposed.
Creation needs an open owner; input stops during a move or a retirement; a
moving or disposed owner publishes no visible or selected page.

## Admission and lifetime

`beginEmbeddedNavigation(_:validateOwner:completion:)` returns a cancellable
request. The original wrapper is already attached to the document view. Pure
owner validation runs before and after asynchronous Profile acquisition,
followed by native validation before any navigation or page creation.

Cancellation before admission settles once without creating a page. After
admission, cancellation retires the actual page through its real owner. It must
not report that a created page never existed. Embedded provenance remains
stable while parked; ordinary tab transfer cannot adopt the page.

The native owner keeps weak references to the original Browser, Profile and
window. Selection contributes the embedded page to `visibleNativePages` and
`selectedNativePage`; deselection blocks its input. Whole-document close uses
real `beforeunload` consent for the entire child-page set. A failed or missing
native owner never becomes an invisible replacement browser.

Embedded pages sleep on the same four-hour idle rule as background tabs. When
the document's tab has gone that long without being shown in its window, nothing
is mid-edit (no canvas gesture or IME draft) and no page is in use by the
automatic-archive standard, the window closes those pages through the same
retirement as archiving. An Easel also drops its editor and rebuilds on show; a
note keeps its editor and only its pages nap. Either way each page loads its
saved address fresh on show, without its earlier back history or scroll position.

## Live embeds in notes

An embed block with a web address shows the live page in the note's Profile,
with its cookies and sign-ins. A slim header shows the favicon, title and host,
plus Back, Reload (Stop while loading) and Open, which opens the page in a tab.
While a page warms up, can't open, closes or crashes, the block shows the
bookmark-style card with a short status and Retry. Easel webpage objects and
captured cards share this header (`EmbeddedPageHeader`) and status card. In
notes and Easels alike, YouTube, Vimeo, Loom, Spotify and Figma links load their
embed players (`NoteEmbedAddress`); Open still uses the saved address, and an
Easel doesn't record the player address as navigation. Every embed's first load
sends Parc's app identifier (`https://<bundle id>`) as its Referer with a
strict-origin-when-cross-origin policy, as an iframe would. YouTube's player
refuses to play without one (Error 153). Live captures load their saved source
without it.

The page is a fixed height that people change with the handle on the bottom
edge. The height is stored as `height` in the block's
[parc comment](notes-format.md#block-colours-and-other-block-settings); the default
height writes nothing. Locked notes keep their pages but hide the handle.

Unlike an Easel, where the first click only selects a browser object so it can
be moved, a note page takes its first click. The note pool's mouse-down monitor
activates the page under the pointer before the window delivers the click, so a
ring appears, keyboard focus moves into the page, it becomes the window's
selected page and the same click reaches the link, button or player. Easels
keep their select-first rule. A click anywhere else, the header's check mark or
Escape ends it; switching tabs or moving the note to another window pauses it
until the note is back. Escape comes from the engine's unhandled-Escape route:
an Escape the page doesn't use goes back to the note, while one the page uses
or one typed in a page field needs a second press within a second.

Scrolling follows the browser's chaining rule. A gesture that starts over the
note scrolls the note, even when a page slides under the pointer. A gesture or
wheel run that starts over a page, active or not, scrolls that page. When the
page reports a vertical scroll step it couldn't use (it hit its edge or can't
scroll), the rest of the gesture, momentum included, scrolls the note; a page
that handles the wheel itself, like a map, keeps it. The decision is
`NoteEmbedScrollLatch`, fed by the page's scroll acknowledgements through the
history-swipe handler. Note shortcuts stay out of a focused page: Find, Find
Next, Find Previous and Use Selection for Find search the page with its own find
bar, as in an Easel, and Find and Replace is off.

Easel blocks in notes reuse this scroll latch for their canvas. Their webpage
objects and live captures are pages in the note's own pool, so they share the
note tab's window, Profile, sleep, window moves and leave-page checks; each
page's id mixes the block's and the object's, so the same Easel shown twice gets
two pages. They keep the Easel's select-first rule and don't take the note's
Escape route. Deleting an object or turning a capture back into a snapshot
closes its pages in the note and in any Easel tab first; navigation is saved to
the Easel. An Easel tab that deletes an object closes the note's copy afterwards
with the page's usual leave-page check.

Live capture blocks share the note pool: their page loads the capture's saved
source without the app Referer and is framed to the captured region; see
[live captures in notes](easel-live-captures.md#live-captures-in-notes).

Navigation inside a note embed doesn't rewrite the file. Deleting the block
closes its page with the page's usual leave-page check; if someone chooses to
stay, the page parks out of sight until Undo brings the block back or the note
closes. Undo after a confirmed close loads the page fresh. A page starts only
once its block scrolls into view.

## Physical-window collection transfer

A same-Profile collection move transfers the original editor, pool, wrappers
and native pages, for Easels and notes alike. Creation and retirement are gated
while the native transfer commits atomically. Failure rolls ownership back in
reverse order, preserving WebContents, navigation history and document identity.

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

A note tab moved to another Profile closes its pages with consent and reopens
them in the new Profile, since the file itself stays where it is.

Private windows deliberately host no Easels or Notes, so an embedded page never
mixes a private session with a normal one. The decision is recorded in
[capture Library](capture-library.md#private-media-ownership).

## Keyboard and accessibility ownership

`focusPage(for:)` admits only the selected object in its original active owner
with the actual native view attached. A crashed page exposes its recovery
control. Focusing never navigates or reconstructs a page.

Returning to the document revalidates the owner, revokes page input and restores
document focus. Canvas Delete and movement keys must not consume keys intended
for a selected native editor or webpage. An inactive page is left out of the
window's key loop and accessibility tree; a note embed's header stays reachable.

## Checks

The Easel pool component exercises injected engines and disposable document
stores, including cancellation, ownership rejection, rollback and retirement;
it opens windows, so it runs only where that is allowed.
`bash scripts/test-notes-editor.sh EmbeddedPageLifecycle` covers the owner
gate and the sleep rule, `NoteEmbedModel` covers height clamping, the embed
players and the `height` round trip, and `NoteEmbedInput` covers first-click
activation, scroll latching and chaining, and the Escape confirmation.
