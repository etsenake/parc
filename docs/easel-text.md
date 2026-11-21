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
400, every run keeps its proportion on whole points too (headings stay bigger
than body text) and
list indents, tab stops, spacing and letter spacing scale with it. Area text
keeps its line breaks because its width scales too; point text refits its
width. The opposite corner stays put (the centre with Option), alignment guides
step aside while you scale, and a small badge under the text shows the size:
the preset's name when you land back on it (“Body · 15”), otherwise the points
(“36 pt”). Several selected text objects scale together; mixed selections
resize as before. The whole drag is one Undo step. On the capture editor's
fixed board, scaled or narrowed text stays inside the board, shrinking the
scale if it has to, and there's no auto width there.

A scaled size is stored as the text style's `customSize` and keeps the preset's
family and weight. Landing exactly on the preset's own size clears it again.
The floating toolbar's size menu offers the five presets plus **Custom…**, a
Notes-style panel: a field that takes 8 to 400 points for the selected objects, or
for the selected range while editing, above rows for common sizes (12 to 144).
Return applies the typed size (or the highlighted row when the field is empty),
Escape cancels, and a size outside the range keeps the panel open with “Pick a
size from 8 to 400.” Picking a preset clears a custom size, and Bigger
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

## Text colour

While editing, a text colour paints the selected range, or the caret's typing
attributes so the next words follow, as one native Undo step. With objects
selected instead, it recolours their whole text in one document Undo step and
skips locked objects: a text object's ink and every run change together, while
shapes and stickies change only their words and keep their outline and paper
(plain shape or sticky text gets runs of its own for this). The context menu's
Text Color offers the palette for any selection that holds text. Palette colours are
stored as their canonical light hex, so they keep switching to their dark variant
on dark paper.

## Whole-object links

A selected text object, shape or sticky that isn't being edited can carry one
link to a web page: ⌘K (Format → Add Link… or Edit Link…), the selection
toolbar's Link button or the context menu's Add Link… opens the Notes link
editor (a floating panel under the badge, with “Paste a link”). It
takes an `http` or `https`
address, adds `https://` to a bare domain like `example.com`, and refuses
anything else with “Enter a web link, like example.com.”; it offers no note
search, because the object link shares the `url` field with link cards and
captured pages, which stay web-only. Remove Link clears it. Range links inside the text keep working
as before while editing. A linked object shows a small round link badge just
outside its top-right corner at a constant on-screen size, with the pointing
hand; clicking it opens the page in Parc without selecting the object. VoiceOver
offers Open link. Locked objects keep their link but refuse a new one. HTML
exports wrap linked objects in a link so they stay clickable. The link is saved
in the object's existing `url` field, which link cards and captured pages also
use for their source; those keep their own Open Source rows instead.

## Range links

Links inside text (text objects, stickies, shapes and connector labels) use the
same Notes link editor as a note: select words and press ⌘K, then paste a link
or find a note. The panel lists the notes of the Profile's Notes folder (or the
hosting note's own folder for an Easel block in a note) and keeps Open Link and
Remove Link rows for an existing link. A web link, `mailto:` or `tel:` link
opens as it always did; a link to a note is stored as the note's file address
(only Markdown and text files are accepted, so no other file can be linked) and
opens the note the way a note link does from a page. Exports leave note links
out, since they only make sense on this Mac.

Hovering a link, whether the text is being edited or not, shows the Notes link
card after the same short delay: Open, Copy, Edit and Remove (Edit and Remove
are left off for locked objects and in read-only Easel blocks). The card
follows the pointer's link, stays while the pointer is over it, and goes away on
a scroll, a key press or a click elsewhere. Links in rotated or flipped objects
don't show the card.

## Slash menu

Typing `/` at the start of a line or after a space, in a text object, sticky
or shape, opens the Notes block menu under the caret: the
same list view, keywords, ranking, preview card, keyboard handling and motion as
a note (`NoteSlashMenuController` and the Easel's `EaselSlashCompletion` share
`NoteSlashListPresenter`). Typing keeps filtering, ↑ and ↓ move, Return or Tab
picks and Escape closes the list and leaves the typed slash as text. Backspacing
into a closed query reopens it, and clicking away closes it. Code spans, table
cells and connector labels never open it.

The rows are the Notes catalog rows that make sense in text: Text, Heading 1–3,
Bulleted and Numbered list, To-do, Quote, Divider, Mention, Date, Inline
equation and Emoji. Picking a row removes
the typed `/query` and turns the paragraph into it as one native Undo step;
Mention and Date open the mention menu, Inline equation opens the equation
editor and Emoji opens the Notes emoji picker (with the custom section) at the
caret. Below them, **Add to the
Easel** places a Sticky, Shape, Image, Video, Audio, File, PDF, Embed,
Bookmark, Block equation, Table or Code block beside the text, to its right or
below it when something is already there (`EaselSlashPlacement`), selected and
as one Undo step, using the same empty placeholders as the toolbar's Add menus.
The object rows come from `EaselSlashCatalog`, whose windowless tests cover the
rows, search and placement.

## Highlight, code and Turn Into

While editing, the selection toolbar carries the Notes format bar's marks. **Highlight**
opens the Notes colour grid with only its nine backgrounds and Last Used row; the
choice paints the selected words, or the next typed ones, as one native Undo
step. A highlight is the run's `background`, saved as the Notes colour's light
value at its light tint (for example `#E8B53A29` for yellow). On dark paper it
reads as that colour's dark tint, because the editor and every drawing map the
stored value onto a colour that follows the appearance, and copying or saving
always goes back to the light value. HTML and SVG exports draw a rounded
rectangle behind the words filled with a `--easel-mark-*` variable that has light
and dark values. **Code** (⌘E) toggles the Notes inline code look, a monospaced
face over a soft grey fill; turning it off restores the object's typeface.
⇧⌘H repeats the last colour or highlight, shared with Notes for highlights.
**Turn Into** is the toolbar's paragraph menu, showing the Notes rows and icons
for Text, Headings, lists (including To-do list) and Quote. The @ button starts a mention in place of the
selection and the equation button (⇧⌘E) turns it into an inline equation, both
the same ones typing `@` or `$` makes.

## Emoji

Typing `:` and two or more letters of a shortcode in any Easel text opens the
Notes emoji suggestions (the same search, ranking, recents and skin tone) under
the caret; ↑ and ↓ move, Return or Tab picks and Esc closes the list without
leaving the text. Typing a complete `:shortcode:` swaps it for the emoji right
away. Only typing counts: pasted, dropped, dictated or autocorrected text
never converts, and nothing happens inside inline code. Each emoji insertion is
its own Undo step. Custom emoji from the Notes library of the Profile's Notes
folder come first in the suggestions and complete on `:name:`; each lands as
an inline run that keeps a copy of its picture, so it still draws, copies and
exports when the library changes or the Easel moves.

## Mentions, dates and inline equations

Typing `@` (or `[[` for notes only) in any Easel text opens the Notes mention
menu (`NoteMentionMenu`) under the caret: notes from the Profile's Notes folder
with their icons, New note “…”, dates and reminders, with the Notes date parser,
so `@Jan 3 - 5`, `@3-5pm` and `@8:40` behave exactly as in a note. Picking a row
replaces the typed `@query` with one inline run, as one native Undo step.

A note mention draws as the Notes mention pill with the note's title; clicking
it while editing opens the note, and on the canvas hovering it shows the link
card with Open and Copy. Mentions count in the note's backlinks and follow the
note through renames and moves. A date draws with the Notes wording (Today,
Tomorrow, Yesterday, then the full date) and rewords itself as days pass;
clicking it opens the Notes date picker (range, time, format, time zone and
Remind). Reminders ring as the same local notifications notes use, named after
the Easel; clicking one opens the Easel. They follow the Easel through renames
and disappear when it's deleted. Typing `$x^2$` or picking Inline equation
makes an inline equation typeset by the Notes math renderer; clicking it opens
the Notes equation editor, and an empty one that's left empty goes away.

Inline runs are saved as typed payloads on a U+FFFC character (see
[Easels](easels.md#range-formatting-and-persistence)). Find matches their words
and highlights the whole pill, Replace leaves them alone, VoiceOver reads them
as Notes does (“Page, Roadmap”, “Reminder, Tomorrow 9:00 AM”), and copying
writes their words to RTF and plain text. PDF and PNG exports draw them as on
the canvas; HTML and SVG write mentions and dates as words and equations and
custom emoji as pictures.

## To-do lists and dividers

**To-do list** is a paragraph kind in text objects, stickies and shapes (connector
labels draw and export them too): pick it from Turn Into, the `/` menu (To-do) or type `[] `
at the start of a line. Each item shows the Notes to-do box (the same symbol,
colours and size rule, `NoteTheme.todoGlyph`) and a ticked item fades its words
like a ticked Notes to-do. Clicking the box ticks it without moving the caret,
⌘↩ ticks every item the selection touches (all ticked becomes all open), and
the box pops with the Notes check spring unless Reduce Motion is on. A text
object, sticky or shape that isn't being edited ticks from a click on its
box too, as one Undo step, and its boxes show the pointing hand. Return starts
a new unticked item, Return on an empty item and Backspace at the start turn
it back into text, and Tab nests it. Ticking while editing is one native Undo
step.

A divider is a quiet rule across the paragraph in the Notes divider colour.
Insert it from the `/` menu (Divider) or `EaselStyledTextView.insertDivider()`;
the caret always lands on a fresh paragraph below, Return or typing inside a
divider moves there, and Backspace or Delete next to one removes it.

Both are list paragraphs whose marker is saved in the existing list `marker`
field (`☐` open, `☑` ticked, `―` divider, all ParcCore `EaselChecklist`
constants), so old files are unchanged and the 128-byte marker limit still
holds. `EaselChecklistLayoutManager` hides the marker glyph and draws the box or
rule (canvas, PDF and PNG use it through `EaselTextLayout.Layout`); HTML and SVG
exports draw a ring or a filled tick circle, a line and faded runs, with
`--easel-rule` and `--easel-todo` variables for light and dark. Plain-text and
RTF fallbacks keep the marker character as readable text, VoiceOver reads
resting items as “To-do, …”, “Done, …” and “Divider”.
