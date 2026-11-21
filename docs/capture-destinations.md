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

There is one highlight, shared by the pointer and the keyboard, and no row is
highlighted until one of them picks it; a saved capture shows a check on Saved
to Library rather than a filled row. The highlight keeps an action ID, exact
Easel UUID or note file across title changes and availability refreshes, and a
row that becomes unavailable loses it. New search text highlights the first
available result; arrows skip unavailable rows, Return activates the highlighted
row, and Return with nothing highlighted highlights the first one. Right or Return on Easel or Note opens its submenu with its
search focused, Left at the start of that search or Escape closes it, and Escape
in the palette uses the existing capture cancellation owner. Hovering Easel or
Note opens its submenu, and moving to another row closes it after 0.15 seconds.
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
commits actual PNG bytes and metadata, and retains its undo session. Missing or
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
notes fail without a substitute. Private and popup windows offer no notes.

## Ownership and checks

The capture lease owns the exact page, document, Profile, Space and window.
Presentation, reversible editing and destination dispatch share that lease;
none may substitute the later selected page or another document with the same
name. The importer commits exact PNG bytes and metadata to the selected UUID.

`scripts/test-capture-palette.sh` runs the palette model: structure, submenus,
search, private availability, highlight retention, keys and the frame Apply
state. `CaptureDestinationTests` exercises the real payload builder, importer,
persistent Easel store and Undo session with generated PNGs and a disposable
directory: activity ordering, profile isolation, source payloads, output
failure and preservation of existing documents.
