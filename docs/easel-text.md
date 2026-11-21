# Easel text

How text sizes and aligns on an Easel. The editing contract (families and
sizes, rich text, clipboard, typed markdown and native Undo) lives in
[Easels](easels.md#object-wide-text-styles); `EaselTextSizing` in ParcCore owns
the rules below and their windowless tests.

## Point text and area text

A click with the text tool, a double-click on empty canvas and Add text make
**point text**: an auto-width box that widens as you type and wraps only at your
own line breaks until it reaches a comfortable limit of 36 ems of the object's
base size (at least 560 and at most 4,000 points), where it starts wrapping. Its
height always hugs the words. Left-aligned point text grows to the right,
centred text grows from its middle and right-aligned text keeps its right edge.
The box follows typing live, including while an input method is composing.

A drag with the text tool makes **area text** with the dragged width; it wraps
and grows taller as you type. Every text object saved before point text existed
opens as area text with its width and height unchanged, and pasted or dropped
text arrives as area text.

A selected text object shows a width handle in the middle of its left and right
sides, even when it is a single short line. Dragging one sets a fixed width and
turns point text into area text; the text re-wraps and the box hugs its height
while you drag. Double-clicking a width handle returns the text to auto width
in one Undo step. Text has no top or bottom handles, because its height follows
the words. Mixed selections keep every handle and resize as before.

## Corner scaling and custom sizes

Dragging a corner of selected text scales it instead of stretching the box: the
font follows the drag continuously, snapping to whole points between 8 and
400, every run keeps its proportion (headings stay bigger than body text) and
list indents, tab stops, spacing and letter spacing scale with it. Area text
keeps its line breaks because its width scales too; point text refits its
width. The opposite corner stays put (the centre with Option), alignment guides
step aside while you scale, and a small badge under the text shows the size:
the preset's name when you land back on it (“Body · 15”), otherwise the points
(“36 pt”). Several selected text objects scale together; mixed selections
resize as before. The whole drag is one Undo step.

A scaled size is stored as the text style's `customSize` and keeps the preset's
family and weight. Landing exactly on the preset's own size clears it again.
The floating toolbar's size menu offers the five presets plus **Custom…**, a
small field that takes 8 to 400 points for the selected objects, or for the
selected range while editing. Picking a preset clears a custom size, and Bigger
and Smaller step from a custom size to the next preset above or below it.

## Alignment

Text, shapes and stickies align their whole text left, centre or right with
⌥⌘L, ⌥⌘T and ⌥⌘R, whether the objects are selected or one is being edited; with
nothing that holds text selected, the chords fall through to Parc. Shapes start
centred; text and stickies start on the left. There is no justify. While
editing, Format → Text → Align Left, Center and Right change the whole object
too, so one alignment always covers every paragraph. Locked objects keep theirs.

The alignment is stored once on the object's text style (`alignment`) and never
in its rich-text runs: the editor shows it on every paragraph and strips it
again when it saves, and copying text out of an aligned object leaves the
alignment behind. Text saved without an alignment keeps whatever paragraph
alignment its runs already carried, such as centred lines pasted from another
app, so older Easels look the same. Changing the alignment is one Undo step; while
editing it joins the editor's own Undo history like the text fill does.

## Whole-object links

A selected text object, shape or sticky that isn't being edited can carry one
link to a web page: ⌘K (Format → Add Link… or Edit Link…) or the context menu's
Add Link… opens the link field. It takes an `http` or `https`
address, adds `https://` to a bare domain like `example.com`, and refuses
anything else; Remove Link clears it. Range links inside the text keep working
as before while editing. A linked object shows a small round link badge just
outside its top-right corner at a constant on-screen size, with the pointing
hand; clicking it opens the page in Parc without selecting the object. VoiceOver
offers Open link. Locked objects keep their link but refuse a new one. HTML
exports wrap linked objects in a link so they stay clickable. The link is saved
in the object's existing `url` field, which link cards and captured pages also
use for their source; those keep their own Open Source rows instead.

## Emoji

Typing `:` and two or more letters of a shortcode in any Easel text opens the
Notes emoji suggestions (the same search, ranking, recents and skin tone) under
the caret; ↑ and ↓ move, Return or Tab picks and Esc closes the list without
leaving the text. Typing a complete `:shortcode:` swaps it for the emoji right
away. Each emoji insertion is its own Undo step. Custom emoji from the Notes
library aren't offered, because Easel text stores only characters.
