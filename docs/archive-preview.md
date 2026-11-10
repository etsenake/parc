# Archive previews

Selecting an eligible archived web tab opens its live page over the Library as
a Peek. Closing the preview leaves the archive record intact. Expand restores
the original archived item into the current Space and transfers the preview's
existing native page into that tab. The Library remains visible until a
successful expansion.

## Engine dependency

The current implementation is in `BrowserWindowController.previewArchivedItem`,
`adoptPeek` and the Peek promotion path. It uses the existing native `openPeek`
route and the reopened-Peek identity flag; the former separate-engine handoff is
obsolete. A pending request captures the exact parent page, archive lease and
one-shot token. A missing native callback releases the reservation after two
seconds. Adoption rechecks the exact window, Profile, parent page and archive
lease before accepting the new page.

The preview is admitted only for a single HTTP(S) web item over an eligible
current page. Splits, folders, Notes and Easels are not previewed through this
route. [Document preview ownership](archive-preview-documents.md) describes the
separate supporting owner and its unfinished integration; its presence is not
proof that grouped or document previews are available.

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

Selection, focus, capture, authentication, downloads, popups and external routes
retain the actual preview page and its original native security owner. They must
never fall back to the underlying selected tab merely because it is easier to
find. Preview metadata remains separate from the archived item until an explicit
restore succeeds.

## Remaining work

Archive records contain tab metadata and complete split geometry, but no persisted
close-time page image. The live preview loads the archived address again; it
cannot show how the page looked when closed. A close-time snapshot cache and
document/group preview integration remain in [the backlog](backlog.md).
