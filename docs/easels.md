# Local Easel editing

Easels are local documents backed by `EaselStore`. A shared `EaselSession`
commits an atomic save before publishing changes to other editors. File → New
Easel opens the Easel in its own tab; Add Split's draft fills its pending pane.
In a split, New Easel, an Easel row and a typed Easel address go to the
command bar's pane, and over a web page the Easel sits on top of the page like
a note, as one step in the pane's history, which it shares with the pages and
notes around it: Back walks through every note, Easel and page before it, with
each page as it was, and Forward returns to them, and an address typed over the
Easel keeps it behind the new page
([navigation](navigation.md#links-to-markdown-and-text-files)). Local editing
and export do not require a collaboration service. Board-wide tools such as
find and replace are in [board features](easel-board-features.md).

Saves refuse a document with duplicate object IDs. A file that already has
them opens with the later copies given new IDs, and an unreadable file is left
out of Easel lists rather than hiding every other Easel.

An Easel's icon is the Library card's Easel mark, light or dark with the
appearance, drawn from the same `DocumentDefaultIcon` as the note mark: sidebar
rows, Favorites, the folded Pinned peek, folders, the tab switcher, command bar
rows and New Easel, history menus and swipes, and Easel blocks, pickers and
paste choices in notes.

## Object-wide text styles

The [selection toolbar](#selection-toolbar)'s typeface and size menus offer four families and five sizes:

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
Point and area text, width handles and alignment are described in
[Easel text](easel-text.md).

## Selection toolbar

Selecting objects floats a toolbar over them, styled and animated like the
Notes format bar ([look](easel-appearance.md), [motion](easel-motion.md)).
`EaselSelectionToolbarPlan` in ParcCore decides its controls from what is
selected: text, stickies, shapes, connectors, sections, images and drawings
each get their own set, several objects of one kind keep that kind's set,
mixed selections keep only the controls every kind shares, and several objects
add align and distribute, tidy up, group, create section and lock tools.
Stickies get a wide toggle, sections a Rename button and pictures Crop, Mask,
Replace and Alt text (Mask and Alt text only in the Easel editor, which hosts
their pickers); the toolbar steps away while a picture is cropped. Text, shapes
and stickies get an alignment menu and, one at a time, a Link button that edits
the object's own link (or the selected words' link while typing), washi tape a pattern menu, and a table its
typeface, size, bold, strike, text and cell colour, alignment and Merge or
Unmerge cells, switching to range formatting while a cell is edited. A fully locked
selection shows only a Locked button whose menu unlocks it, a section with its
contents. A single webpage, captured card or link keeps its own page
header instead. A control appears only once its canvas command exists, and the
••• menu always ends the bar. Each button shows the pointing hand and a tooltip
with its name and live shortcut, and VoiceOver finds it among the canvas's
objects as a "Selection tools" toolbar. ⇧⌘/, the Notes format bar's shortcut,
moves keyboard focus into it, even while text is being edited; it is also a
Tab stop after the canvas's objects. The arrow keys move between buttons,
Return or Space presses one and Escape returns to the canvas or the text being
edited.

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

Copying whole objects on the canvas uses its own private Easel payload, with
the objects, their styles and their picture bytes, plus image and text
fallbacks for other apps; see [arranging](easel-arranging.md#clipboard).

## Typed markdown

Only a single typed character at a collapsed caret triggers syntax conversion.
Heading prefixes `#` to `####` plus space (32, 26, 22 and 19 points), bullet
`-`/`*`, ordered `1.` plus whitespace and `>` plus space for a quote create
paragraph formatting. A quote is a list-style paragraph with a `▎` bar marker, so
Return continues it, an empty line or Backspace at its start ends it and Tab
nests it. Single asterisks, underscores and hyphens around eligible words apply
bold, italic and strike-through; backticks around any run of characters on one
line make inline code, monospaced on a soft grey fill that reads on light and
dark paper. Unsupported punctuation and doubled delimiters stay literal.

Paste, composition, Undo and programmatic insertion never trigger conversion.
A conversion is one native transaction with exact selection/attribute Undo.

## Canvas selection and original-object transactions

Selection drag captures the original document, selection and frames. It commits
one atomic change; intermediate geometry is not saved. A competing geometry
change cancels the gesture, while an unrelated content change can coexist.
Travel of three points or less cancels a body drag. Group and lock click rules,
the marquee, Option-drag copies and Shift's axis lock are in
[arranging](easel-arranging.md#selecting).

## Original-group frame resizing

Corner handles have 20-point hit regions; edges have ten-point regions. Small
objects under 30 points hide idle handles. Option resizes around the captured
center. Crossing an edge mirrors shapes, images and drawings and keeps text
readable; turned objects resize along their own sides
([rotate and flip](easel-rotation.md)). Invalid geometry rejects the whole
transaction. Modifier changes recompute from the original geometry instead of
accumulating drift.

## Content hits and transient alignment guides

Small objects have a 30-point minimum target. Strokes use a 30-point round hit
region; large circles pass through transparent corners. Marquee selection uses
actual geometry. A selected rectangle remains available for manipulation.
Shapes in the newer styles follow the [shape hit rules](easel-shapes.md#hit-rules).

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

Arrows are connectors: their ends snap to side magnets, pinned points or an
automatic side on other objects, route straight, elbow or curved, and carry
heads, labels and bends. Endpoint targets are 20 points; dragging an end fixes
the other one. Attaching, routing, labels and quick create are in
[connectors](easel-connectors.md).

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

## Images and media

Image objects crop in place, mask to the Notes shapes, carry alt text, swap
pictures without moving and play GIFs while selected, all without touching the
stored picture. Their behaviour, saved fields and code owners are in
[Easel images and media](easel-images.md).

## Embedded webpages and captured cards

Webpage objects own real auxiliary native pages, scoped to the editor's physical
window and Profile. Captured cards retain immutable PNG data and provenance;
their optional live page is a separate owner. Selection, cancellation,
`beforeunload`, transfer and Profile relocation contracts are in
[embedded pages](embedded-pages.md).

Webpage objects and captured cards wear the Notes embed block's header
(`EmbeddedPageHeader`): favicon, page title and host, then labelled state and
actions. A selected captured card floats that header over the top of its image,
above every other object; it pins to the visible top while the card scrolls
past and sits just outside cards shorter than the header. It says “Snapshot ·
captured <day>” and offers **Make live** plus Open in a tab. A card without
saved region geometry (full-page, cropped, marked-up, Portrait-framed or older)
says “Snapshot only” and explains why in its tooltip. A live card shows a Live
badge, **Back to snapshot**, Reload (Stop while loading), Open in a tab and a
••• menu with Site Information. A webpage object shows Back, Reload, Open and a
••• menu with Forward, Edit Address or Search… and Site Information; clicking
its title also edits the address. The check mark (“Back to the Easel”) appears
while a page has input. Warming up, alignment failures, closed and crashed
pages use the embed block's bookmark card with a short status and Retry.
`EaselWebItemChrome` decides the state, labels and header placement.

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
creates [point text](easel-text.md#point-text-and-area-text) fitted to that
prompt, with its left edge at the click and its top 14 points above it. Keyboard
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

The canvas accepts URL-only pasteboards as local link objects, and plain text
that reads as a Mermaid flowchart or ER diagram becomes editable shapes, arrows
and sections ([Mermaid diagrams](easel-mermaid.md)). Capture's memory-only
image editor instead inserts annotation text and never creates an Easel or
browser owner. Existing public RTF/RTFD interoperability is retained.

## Canvas keyboard and accessibility ownership — EASEL26

Objects expose stable native accessibility stops. Only selected native text or
browser children receive editing input. Return enters the actual editor; its
keys must not become canvas Delete or movement commands. Keyboard handle
movement changes exact geometry by one point and remains one Undo transaction.
Every entry/return action validates the original document/window owner.

## Page menu and exports

The ••• button at the end of the title row opens the Easel's page menu, built
from the same floating menu, rows, highlight, motion and keyboard handling as
the Notes page menu: Copy Link (the Easel's `parc://easel/…` address), Copy as
Image (a PNG on the pasteboard), Export (Image…, HTML File…, PDF…), Show in
Library, Duplicate, and Delete Easel…, with the object count and last edit
underneath. Easels have no lock. Exports are named after the Easel's title and
end with the Notes "Exported …" toast.

HTML exports are one self-contained file in the Notes export style: the title
over the Easel drawn as SVG sized to the content bounds plus margins. Shapes,
arrows and strokes are vector paths, text runs keep the Easel's fonts,
emphasis, links and fills, images and web snapshots are embedded as data URIs,
and web cards link to their source. Automatic ink and card colours follow the
viewer's light or dark preference with both palettes inlined, while chosen
colours stay exact. PDF exports draw the canvas into a single vector PDF page
the size of the content bounds plus margins (scaled down past PDF's 200-inch
limit), so text and shapes stay sharp. `EaselVectorExport` in ParcCore owns
bounds, escaping and the SVG and HTML; its per-kind switch, and the canvas
drawing switch the PDF reuses, are where a new object kind adds its case.

Export → Image… and Command–Shift–S export a saved document snapshot.
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

## Saved format for board objects

Every object field added for shapes, stickies, sections and connectors is
optional and left out of the file when unused, so an Easel saved before them
opens and draws exactly as it did. Rectangle-kind objects are the [shape](easel-shapes.md) family:
`shape` names their outline (absent means a plain rectangle) and circle-kind
objects are ellipses. `fill`, `fillOpacity`, `strokeWidth` and `strokeDash`
style shapes, stickies and sections; absent values keep the original look. Only
arrows carry arrowheads (`startHead`, `endHead`; absent means none at the start
and an arrow at the end), `routing` (absent means straight) and connections to
other objects, which may pin a point on the object (`anchor`), plus a label
(`text`, `labelPosition`, `labelBackground`) and manual bends (`waypoints`).
Drawings may use a highlighter or washi `brush` with a tape `pattern`.
`groupID`, `locked`, `rotation` (degrees around the frame's centre),
`flipHorizontal`, `flipVertical` and `attachedTo` (an object it sticks to and
moves with) apply to any object. Text, shapes and stickies hold rich text;
sections keep a plain title. Tables keep their grid, cell text and merges in a
`table` field described in [Easel tables](easel-tables.md#saved-format), and
[code blocks](easel-code-blocks.md#saved-format) keep their code in `text` with an
optional `language`. A text style may carry `alignment`, `customSize` (8 to 400
points, overriding the preset size) and, on text objects only, `autoWidth` for
point text; absent means the preset size and fixed-width area text.
Validation refuses each field on objects it doesn't belong
to, so a malformed file is rejected whole rather than half drawn.

## Checks and limits

`bash scripts/test-easels.sh` and the focused editor/pool/capture components
exercise atomic saves, rich-text validation, native Undo, ownership, geometry,
clipboard conversion, export bytes and the SVG/HTML serialiser.

Private windows deliberately offer no Easels or Notes and send no captures to
Easels; the reason is in [capture Library](capture-library.md#private-media-ownership).
Local documents do not publish to cloud or collaboration services.
The [backlog](backlog.md) owns remaining product work; this guide owns the stable
editing and data-safety contract.
