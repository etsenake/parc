# Archive previews

Selecting an eligible archived web tab opens its live page over the Library as
a Peek, whatever the window shows behind it: a web page, including one that
hasn't loaded yet, a Note, an Easel, a split whose focused pane is a document,
or the start page of an empty Space or empty window. Closing the preview leaves the archive record intact. Expand
restores the original archived item into the current Space and transfers the
preview's existing native page into that tab. The Library remains visible until
a successful expansion.

## Opening the preview

`BrowserWindowController.previewArchivedItem` picks a route from
`PeekBackdrop`, which describes what the window shows. Over a live web page it
uses the native `openPeek` route from that page and the reopened-Peek identity
flag, and `adoptPeek` accepts the new page. Over a Note, an Easel, the start
page or a web tab whose page is still opening, blank or failed to open, there
is no page to open from, so the window creates the preview's page itself,
hidden among its parked pages, and wraps it in a Peek with no parent page.
That Peek belongs to the current tab, or to the Space while its start page
shows, so like any Peek it hides when you switch away and returns with you.

When a web tab's page arrives under its preview, the preview adopts that page
as its parent on the page's first report, after the same window, Profile,
binding and single-Peek checks `adoptPeek` makes, and from then on it is an
ordinary Peek over that page: it closes and moves with the tab and is promoted
if the page goes. Until then the lookup keeps showing it, while a Peek that has
a parent still shows only over that exact page.

A pending request holds the parent page (none for the window route), archive
lease and one-shot token, and keeps any second Peek out. A missing callback
releases the reservation after two seconds. Adoption rechecks the window,
Profile, backdrop and archive lease before accepting the new page; a refused or
late page is closed. `PeekBackdropTests` covers each backdrop's route and that
the window then shows the preview.

The preview is admitted only for a single HTTP(S) web item. Notes, Easels,
splits and folders are restored with Put Back instead; see
[product decisions](#product-decisions).

## App responsibilities

`BrowserStore.acquireArchivePreview` reserves the original archived record.
`archivePreviewIsValid` and `restoreArchivePreview` guard subsequent changes.
Requests to preview another row first dismiss the current preview and retain a
queued request. Window retirement releases pending and active leases.

Close follows real native close consent and releases the lease after teardown;
it does not restore or delete the archive record. Expand restores the original
model identity before handing off the live wrapper and page. Native attachment
and saved-item ownership must both succeed. Failed attachment reattaches the
preview wrapper; if the archive item was already restored, it stays restored and
loads its own page rather than being silently removed.

A window-hosted preview returns focus to the Note, Easel or start page behind
it when it closes, and its sound gets a Mini Player that brings that host back.
It never holds up closing, archiving, moving or splitting its Note or Easel. If
that Note, Easel or Space goes away or moves to another window while the
preview is hidden, or a tab takes the start page's place, the preview closes so
it can't hide out of reach holding its archive item. If its page refuses to
close, it stays open as a Today tab, as any Peek does when its parent goes.

Selection, focus, capture, authentication, downloads, popups and external routes
retain the actual preview page and its original native security owner. They must
never fall back to the underlying selected tab merely because it is easier to
find. Preview metadata remains separate from the archived item until an explicit
restore succeeds.

## Product decisions

Library previews only single web pages. Notes, Easels and splits are restored
instead, and the preview never shows a saved picture of the page. These are
deliberate decisions, not unfinished work.

### Archived Notes and Easels

Archived Notes and Easels are restored, not previewed. A single click only
selects the row; double-click, Return or Put Back restores the document into the
current Space. A preview would have to own a live Note or Easel editor,
including an Easel's embedded web pages, and hand that same editor to the
restored tab on Expand. If that handover failed and the editor were replaced,
half-typed text and other unsaved input would be lost. Archiving removes only
the sidebar entry: the document stays in Library → Easels & Notes, where it can
be searched and opened, so a preview would add little for that risk.

### Archived splits

Archived splits are restored, not previewed side by side. Their row already
lists each page's title, and double-click, Return or Put Back restores the whole
split into the current Space. A split preview would need a new surface holding
several live pages at once, with their close prompts and a handover of every
page to the restored split. That is large work inside the page-ownership code
that ordinary Peek and Expand rely on, for little gain over the visible titles.

### Live page, not a close-time picture

Archive records keep tab metadata and complete split geometry but no picture of
the page. The preview loads the archived address again, so it shows the page as
it is now rather than as it looked when archived. Parc deliberately saves no
picture at archive time. Automatic archiving reaches pages nobody has viewed for
at least twelve hours, and many of them are unloaded or were never drawn in a
window, so there would often be nothing to capture. Saved pictures would also
keep whatever was on screen, such as balances or private messages, on disk for
up to two months, until [retention cleanup](archive.md#automatic-archive-clocks-wake-and-occlusion--auto10)
removes the record.
