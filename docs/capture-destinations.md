# Capture destinations and source attribution

The capture palette is a Notes menu card beside the captured image: a search
field, then Save to Library, Copy, Save… and Send via iMessage…; a divider before
Edit, Crop, Frame in Portrait Mode (Edit Portrait Frame and Remove Frame once
framed) and Retake; then a Send To header over Easel and Note. Each of those two
opens a submenu beside its row with its own search: New Easel or New Note first,
then every Easel or recent note under Recent, scrolling when the list is long, so
the palette never grows with the number of documents. Easels rank by their most
recent original Sidebar activity, descending; editing a document does not promote
it. Notes keep the notes catalog's order. Typing in the main search runs across
every action, New Easel, New Note, each Easel and each note as one flat list
without headers or dividers, documents labelled Easel or Note, in action, Easel,
then note order. Search lowercases the query and each current title and is a
literal substring match, including spaces; a saved Library toggle matches its
current Saved to Library label.

There is one highlight, shared by the pointer and the keyboard. The palette
opens with it on the first available action, Save to Library, as Parc's other
keyboard-opened Notes menus do, so one Return saves; the pointer and arrows then
move it, and it is never a second, permanently filled row. A saved capture
shows a check on Saved to Library rather than a filled row. The highlight keeps
an action ID, exact Easel UUID or note file across title changes and
availability refreshes, and a row that becomes unavailable loses it. New search text highlights the first
available result; arrows skip unavailable rows, Return activates the highlighted
row, and Return with nothing highlighted highlights the first one. Right or Return on Easel or Note opens its submenu with its
search focused, Left at the start of that search or Escape closes it, and Escape
in the palette uses the existing capture cancellation owner. Hovering Easel or
Note opens its submenu. Once one is open, crossing another row only switches or
closes it after 0.3 seconds, and reaching the submenu cancels that, so a
diagonal path into it never swaps in the other list. A submenu with no room on
either side overlaps the card rather than leaving the capture overlay, so every
row stays clickable, and a press follows its row even if the list refreshes.
Tab stays in the palette, as in Parc's other menus. No result means no output
selection, and input-method composition keeps every key.

`CaptureEaselDestination.catalog` joins the profile's actual local document
catalog with the original non-archived Sidebar records. It resolves current and
saved internal Easel URLs to exact document UUIDs, takes the maximum matching
activity date in the original profile, and gives documents without a matching
Sidebar record no activity date. Local profile partitioning substitutes for the
excluded account/cloud permission model. A UUID tie-break for equal or absent
dates and including local documents without Sidebar references are deterministic
ordering rules. The existing Easel importer still reopens the selected UUID,
commits actual PNG bytes and metadata, and retains its undo session. The capture
lands on the page that Easel shows in the window (page one otherwise), and the
Easel opens on it with the card selected ([pages](easel-pages.md#sending-captures-and-images)). Missing or
deleted destinations fail without creating substitutes. New Easel still uses
the original page title and opens the committed document, as the established
local document ownership policy.

Messages prepares the currently previewed PNG together with the original
capture lease's absolute URL, in URL-then-image order. It adds no title or brand
text. Crop and Portrait changes replace the image while keeping that original
source. An absent or relative source address produces an image-only payload;
this preserves the available image-only output. No replacement URL is
looked up and no attribution is derived from the later selected tab. The same
prepared item types are checked for service availability and passed to the
native Compose Message service. The existing delegate continues to distinguish
completion, cancellation and failure; completion is not proof of recipient
delivery. Original lease invalidation detaches the callback. AppKit owns an
already-open composer and exposes no public retraction API.

Notes are the other document destination. `CaptureNoteDestination.catalog`
joins the Space Profile's notes with Sidebar activity like Easels, keyed by the
file's identity so selection survives renames; notes without activity follow by
modification date, and the catalog keeps the 50 most recent. New Note creates a
note titled from the page. `NoteCaptureDelivery` copies the PNG into the note's
Attachments folder and inserts the capture at the open note's caret (replacing
an empty line) or at the end, as one Undo step; missing, locked and plain-text
notes fail without a substitute. The note then opens scrolled to the new
capture with it selected, including from a capture taken in a Peek. Private and
popup windows offer no notes.

A capture bigger than an Easel accepts (over 16,384 pixels on a side, 80 million
pixels or 30 MB, as long full-page captures often are) is scaled down to fit
rather than refused. Any failure shows as a red banner with a warning icon under
the search field of the menu and of an open Easel or Note list, with a beep, and
a send that can't happen names its reason there: an inactive window (which Parc
first tries to make active), an open dialog, a capture whose page changed, or a
window still rearranging.

A Library save in progress holds only Save to Library and the editing rows;
sending, copying, saving and Messages stay available. The Easel list is read
once per capture, in the background, from a light summary of each Easel, and a
failed send reloads it the same way. A capture whose page stops being current
closes instead of leaving a menu that ignores clicks.

## Sharp long captures

A Full Page capture that carries the engine's vector PDF still lands as the same
capture card or capture block, but its picture is drawn from the PDF. On an
Easel the card is sized from the PDF page (one point per CSS pixel): up to 480
wide at the page's shape, since a very long page's PNG may be rendered narrow to
stay under 16,384 pixels. The capture send, pasting and dragging in a note's
capture block all size it this way. On an Easel the PDF is a second asset on the card
(`snapshot`); the PNG stays for thumbnails, HTML export and fallback. A PDF over
the 30 MB asset limit, or one PDFKit can't open, is simply left out. The canvas
draws the PNG while it is at least as sharp as the zoom needs; past that it
draws 512-pixel tiles rendered off the main thread at the next power-of-two
scale for only the visible part of the card, from one shared 32-million-pixel
cache. Until a tile lands, the canvas shows cached tiles of the same spot from
the nearest other scale, sharper first, and the PNG only where none exist or
where a coarser tile would be blurrier than it. The newest requests render
first and older queued ones are dropped, so tiles for a zoom already left never
render; unused tiles age out of the cache. PDF, PNG, Copy as
Image and print draw the PDF itself as vectors in the card's frame; HTML export
embeds the full-resolution PNG. Copy, paste, Send and Copy to
Easel and moving an Easel between Profiles carry the PDF with the card. In a
note the PDF sits in Attachments beside the PNG, sizes the block, draws in the
zoom view and travels with the block, as [Notes](notes.md) describes.

## Ownership and checks

The capture lease owns the exact page, document, Profile, Space and window.
Presentation, reversible editing and destination dispatch share that lease;
none may substitute the later selected page or another document with the same
name. The importer commits exact PNG bytes and metadata to the selected UUID.

`tests/ParcCoreTests/Capture` runs the palette model under `swift test`: structure, submenus,
search, private availability, highlight retention, keys and the frame Apply
state, activity ordering and profile isolation. `CaptureMessagePayloadTests`
and `CaptureEaselPlacementTests` exercise the payload builder, importer,
persistent Easel store and Undo session with generated PNGs. They cover source
payloads, output failure and preservation of existing documents.
`CaptureControllerSendTests` drive the real capture controller through the
configurable capture lease in `tests/ParcEngineDoubles/PageCaptureEngineDoubles.h`,
in a key window that is never shown, clicking palette rows as a pointer would.
They check that a visible-area, framed or Library-saved capture reaches the chosen
Easel or note, that a Library save in flight holds only Save to Library and
Retake, that a page or lease that stops being current or a window that cannot
become key refuses the send with its banner and leaves the capture open, and that
a failed send stays open with its error while the Easel list reloads in the
background. `CaptureControllerSnapshotTests`, `EaselCaptureSnapshotTests`,
`CaptureSnapshotPDFTests` and `NoteCaptureSnapshotDeliveryTests` cover which
captures carry the page PDF, how it is stored and refused, tile geometry and
vector export, built from tiny generated PDFs.
