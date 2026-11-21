# Local Easel editing

Easels are local documents backed by `EaselStore`. A shared `EaselSession`
commits an atomic save before publishing changes to other editors. File → New
Easel opens the Easel in its own tab; Add Split's draft fills its pending pane.
In a split, New Easel, an Easel row and a typed Easel address go to the
command bar's pane, and over a web page the Easel sits on top of the page like
a note: Back returns to the page as it was and Forward to the Easel
([navigation](navigation.md#links-to-markdown-and-text-files)). Local editing
and export do not require a collaboration service.

## Object-wide text styles

The whole-selection palette offers four families and five sizes:

| Family | Typeface | Sizes |
| --- | --- | --- |
| Mono | Space Mono, regular body/bold display | 15, 24, 44, 60, 80 |
| Fancy | EB Garamond | 16, 28, 48, 60, 80 |
| Hip | Parc Wide (Mona Sans Expanded) | 18, 21, 44, 60, 80 |
| Clean | System | 15, 24, 44, 60, 80 |

During native text editing, selection formatting applies to the selected range
and caret formatting updates typing attributes. Native text Undo precedes
canvas/document Undo. Composition is never serialized as a finished edit.
Durable saves coalesce within the editing UUID while native Undo retains its
own transactions; another owner's edits invalidate obsolete local history.

## Content-hugging text fill and native metrics

Optional `contentHugging` fill needs no migration. It draws black behind actual
TextKit line fragments and temporarily displays white ink, preserving stored
colors. Empty lines have no fill. Radius follows text size (6, 8, 10, 10, 10);
padding is at least six points or 1.3 times descent, with adjacent edges smoothed.

Changing fill breaks typing coalescing and preserves selection, attributed runs
and exact Undo history. Text geometry comes from the native editor, including
paragraphs and attachments, instead of estimating line height independently.

## Range formatting and persistence

Rich text stores contiguous UTF-16 runs. Reject gaps, overlaps, overflow,
surrogate splits, unsafe links, nonfinite fonts, excessive runs and unsupported
attributes before mutation. Supported data includes fonts/axes, colors,
emphasis, links, kerning, baseline offsets, paragraph tabs/lists and images.
Missing fonts use a local fallback; opening a document does not download fonts.

Paragraph commands apply to all intersecting paragraphs, excluding the next
paragraph when selection ends at its boundary. Heading sizes are 32/26/22.
Lists use native text-list/tab markers with seven indentation levels. Return
continues a list, an empty item exits it, Backspace exits and Tab changes indent.
Each command is one native Undo transaction; composition and unsupported
multiple selections refuse without partial edits.

## Clipboard boundary

Copy publishes the private version-3 rich carrier plus RTF/RTFD and plain text;
versions 1 and 2 remain readable. Cut mutates only after publication succeeds.
Private ranges are rebased. Explicit plain paste keeps receiving attributes.

The private rich carrier takes precedence over its fallback, even when fallback
text resembles a URL. Unsupported tables and non-image attachments refuse
atomically with a Plain Text alternative; directories and symlink wrappers are
never followed. PDF/vector/animated-image conversion is outside the local
image carrier. Refusal does not modify the source clipboard.

## Typed markdown

Only a single typed character at a collapsed caret triggers syntax conversion.
Heading prefixes `#`, `##`, `###` plus space, bullet `-`/`*`, and ordered `1.` plus
whitespace create paragraph formatting. Single asterisks, underscores and
hyphens around eligible words apply bold, italic and strike-through.
Unsupported punctuation and doubled delimiters stay literal.

Paste, composition, Undo and programmatic insertion never trigger conversion.
A conversion is one native transaction with exact selection/attribute Undo.

## Canvas selection and original-object transactions

Selection drag captures the original document, selection and frames. It commits
one atomic change; intermediate geometry is not saved. A competing geometry
change cancels the gesture, while an unrelated content change can coexist.
Travel of three points or less cancels a body drag.

## Original-group frame resizing

Corner handles have 20-point hit regions; edges have ten-point regions. Small
objects under 30 points hide idle handles. Option resizes around the captured
center. Crossing an edge reflects geometry/freehand paths without reflecting
payload text/images. Invalid geometry rejects the whole transaction. Modifier
changes recompute from the original geometry instead of accumulating drift.

## Content hits and transient alignment guides

Small objects have a 30-point minimum target. Strokes use a 30-point round hit
region; large circles pass through transparent corners. Marquee selection uses
actual geometry. A selected rectangle remains available for manipulation.

Guides compare object edges/centers and 24-point spacing. Admission uses a
strict six-pixel radius (doubled for center X) and velocity below 125, with
bounded hysteresis up to 3.5. Command suppresses snapping. Only satisfied final
alignments display guide lines; transient guides never become document data.

## Canvas anchors and original resize centering

Canvas edge anchors are at 42 and 1000; width provides a center anchor. Initial
alignment is normalized with a `1e-6` tolerance. Captured centered axes remain
separate from the live Option modifier. A canvas-width change cancels a pending
resize rather than applying it to a different coordinate space.

## Arrow endpoints and image aspect controls

Endpoint targets are 20 points, with eight-point marks and 2.5-point borders.
Dragging fixes the opposite endpoint and uses white/black with blue `#6CBAD9`
feedback. Endpoints highlight exact guides without adding snap corrections.

Images, webpage cards and links preserve aspect by default. Shift applies
aspect to a group; Command overrides it. Resize changes geometry without
resampling stored images. Intrinsic image dimensions drive guides; webpage
cards have a square fallback and links a 220 × 160 fallback.

## Endpoint and guide feedback — EASEL25

Feedback is transient and belongs to the current owner/gesture. Cancellation,
selection changes and invalid geometry clear it. A stale callback cannot leave
handles or guides over a different document. Model checks cover the shared
geometry and ownership rules.

## Inline images in rich text

PNG, JPEG and single-frame TIFF import copies bytes, not source paths. Each
image occupies one U+FFFC run. Limits are four MiB per text object and 16 million
decoded pixels. The native cell centers the image, fits within line width minus
60 without upscaling, and adds 60 points of height with separating newlines.
RTFD preserves exact supported attachment bytes. A failed save rolls the editor
back with its correct native Undo state.

## Embedded webpages and captured cards

Webpage objects own real auxiliary native pages, scoped to the editor's physical
window and Profile. Captured cards retain immutable PNG data and provenance;
their optional live page is a separate owner. Selection, cancellation,
`beforeunload`, transfer and Profile relocation contracts are in
[embedded pages](embedded-pages.md).

### Webpage address, search and durable navigation

Address entry accepts credential-free HTTP(S), adding HTTPS when appropriate.
Search uses DuckDuckGo with All, Images, Videos, News, Maps and Shopping; Images
is the default. Encode a query once, preserve literal plus signs and use
`iaxm=maps` for Maps. This is an explicit URL/search flow, without autocomplete.

Admission checks the original owner, composition and validation errors. A
selected real page's committed URL updates durable object metadata. Other
editors acknowledge that revision without navigating their own pages. Canvas
Undo must retain the latest acknowledged navigation metadata.

## Default text, selection and empty-object retirement — EASEL24

New text starts with “Start typing to enter text”. Empty-canvas double click
creates a 280 × 28 object with its top 14 points above the click. Keyboard
editing selects the prompt; ordinary double click selects a word.

Whitespace-only text retires at the final editing boundary through the same
Undo transaction, never through a sweep on load. Failed saves refuse the next
action. Shared-owner changes cannot be erased by an old local empty-text result.

## External clipboard and non-image boundary — EASEL21

Native Paste recognizes a credential-free HTTP(S) URL from the standard URL
flavor or exact plain text. A selected label becomes its link; a self-labelled
URL is replaced by the new URL. At a caret, insert the URL as its own label.
One Undo restores the original attributes and selection. Composition and
attachment-bearing labels refuse before mutation. Later typing and explicit
plain paste do not inherit the pasted link.

The canvas accepts URL-only pasteboards as local link objects. Capture's
memory-only image editor instead inserts annotation text and never creates an
Easel or browser owner. Existing public RTF/RTFD interoperability is retained.

## Canvas keyboard and accessibility ownership — EASEL26

Objects expose stable native accessibility stops. Only selected native text or
browser children receive editing input. Return enters the actual editor; its
keys must not become canvas Delete or movement commands. Keyboard handle
movement changes exact geometry by one point and remains one Undo transaction.
Every entry/return action validates the original document/window owner.

## Export as Image

Share → Export as Image and Command–Shift–S export a saved document snapshot.
The canvas uses its width and height `max(lowest object bottom, width) + 60`;
fixed capture canvases use exact capture bounds. Selection, guides and carets
are excluded. Background is white or black from the Easel's own light or dark
appearance, matching its ink ([appearance](easel-appearance.md#ink-and-saved-colours)).

Each native embedded-page snapshot has a five-second deadline; the app allows
eight seconds for the full collection. Missing, denied, late or unsupported
snapshots fall back to the saved card/capture, never silently to a newly navigated
page.

Encoding streams 256-row strips to a temporary destination, then atomically
publishes PNG or JPEG. JPEG dimensions cannot exceed 65,535; PNG does not inherit
that restriction. The native save panel and file extension agree on format.
Callbacks revalidate the exact window/focus; errors appear once per window and
queue behind an existing sheet.

## Checks and limits

`bash scripts/test-easels.sh` and the focused editor/pool/capture components
exercise atomic saves, rich-text validation, native Undo, ownership, geometry,
clipboard conversion and export bytes.

Private windows deliberately offer no Easels or Notes and send no captures to
Easels; the reason is in [capture Library](capture-library.md#private-media-ownership).
Local documents do not publish to cloud or collaboration services.
The [backlog](backlog.md) owns remaining product work; this guide owns the stable
editing and data-safety contract.
