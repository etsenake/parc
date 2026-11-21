# Capture destinations and source attribution

The capture palette keeps Library, Copy, Save and Messages first, then the
editing actions and Retake, then New Easel and existing local Easels. The
user-requested reversible Portrait actions remain beside Crop. Existing Easels
rank by their most recent original Sidebar activity, descending; editing a
document does not promote it. Only two destinations show initially. Show More
reveals the rest without performing an output action. Search lowercases the
query and each current displayed title, searches all destinations including the
collapsed ones, and preserves the original action and activity order. A saved
Library toggle matches its current Saved to Library label. Search is a literal
substring match, including spaces; filtered results omit section dividers.

Selection retains an action ID or exact Easel UUID across title changes and
availability refreshes. New search text selects the first available result;
arrows skip unavailable actions, Return activates the selected result, and
Escape uses the existing capture cancellation owner. Expanding selects the first
newly exposed Easel. No result means no output selection. The expansion and
keyboard presentation use the same real action list as pointer clicks.

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

`CaptureDestinationTests` exercises the real destination model, payload builder,
importer, persistent Easel store and Undo session with generated PNGs and a
disposable directory. It covers activity ordering, profile isolation, collapsed
and searched items, renamed UUID selection, disabled/empty results, source
payloads, output failure and preservation of existing documents.
