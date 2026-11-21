# Easel board features

Board-wide tools that work across a whole Easel rather than on one object:
find and replace, links to a single object, Easel History, selection
export, templates and the timer. They sit beside
the [Easel editing contract](easels.md) and use the Notes look
([appearance](easel-appearance.md)) and motion rules ([motion](easel-motion.md)).

## Find and replace

⌘F opens the Notes find bar over the top right of the canvas, with the same
field, count, Match Case, previous and next arrows, Replace disclosure and
chips. ⌥⌘F opens it with Replace showing. The chords belong to the Easel while
anything in the Easel has the keyboard: the canvas, an object stop, text being
edited in a text object, sticky or shape, the title or the find bar. Inside a
live webpage on the canvas they stay with that page, as in a note's embeds.

Finding runs as you type over the text the canvas actually shows: text
objects, stickies, shape text, connector labels, section titles, table cells,
code blocks, link cards and webpage cards that draw their title. Captured and live webpages show the
page itself, so their titles aren't searched, and URLs never are. Objects
tucked inside a section whose contents are hidden are left out, since nobody
can see them. Matching ignores case and accents until Match Case is on.
Matches run in reading order: objects on roughly the same row left to right,
then the next row down, and within an object from start to end. The first
match is the first one already in view, so opening find doesn't throw the
canvas somewhere else.

Return and ⇧Return, the arrows, and ⌘G and ⇧⌘G step through matches while the
bar is open (with the bar closed they keep their usual meaning).
Each step pops the matched object with a brief glow and glides the canvas to the match, keeping it clear of the bar, zooming
out when the object is bigger than the view and in to 100% when the board is
zoomed too far out to read it; a match already in view doesn't move anything.
Reduce Motion makes the move instant.

Matches are highlighted on the canvas in the Notes find colours. Text objects,
stickies and code blocks highlight the matched words themselves, with the
current one outlined; a section highlights its title tab, a connector its
label, a table the matching cell, and other objects get a soft ring, with a
stronger ring and wash on the current match. Highlights are
drawing only: they never reach the document, exports or the selection.

Replace changes the current match and moves to the next; Replace All (or
⌘Return in the replace field) changes every match and flashes the count. Each
is one undo step. Replace only ever changes the match you can see: if an edit
made it disappear, the bar shows the new current match first and the next
press replaces that. A replacement takes the formatting of the first character
it replaces, never swallows an inline picture, and grows a text object,
sticky or code block to fit; a table refits the rows whose cells changed. If
any match in an object can't be rewritten, Replace All leaves that whole
object (or table) alone rather than changing half of it.

Locked objects and card titles are found but can't change. While Replace is
showing, the count says so ("2 of 5 · locked" or "· read-only") and the
Replace chip dims; Return in the replace field skips ahead to the next match
that can change. After Replace All the count line says what was skipped and
why ("Skipped 2 locked, 1 read-only"), and VoiceOver reads it too. Escape
closes the bar and selects the object of the last current match, ready for the
keyboard.

The matching, reading order, replacement and the bar's replace and refresh
rules are pure ParcCore code (`EaselFinder`, `EaselFindSession`,
`EaselViewportFocus`). Adding a kind that shows text means listing its text in
`EaselFinder.searchableParts(of:)` (table cells are their own parts) and its
`replaceability(of:)`.

## Links to objects

Copy Link to Object in an object's context menu copies the Easel's address
with the object's id after a `#`, for example
`parc://easel/<easel id>#<object id>`, and shows the Copied toast. Opening it
from anywhere Parc follows Easel links (a note, the command bar, a pasted
address) opens the Easel the usual way, then selects that object and glides
the canvas to it at up to 100%. If the object has since been deleted, the
Easel still opens and a toast says the object isn't there anymore. Tabs keep
the plain Easel address, and any other fragment is not an Easel link.

## Links to notes and Easels

Text links and object links in an Easel can point at a note (a `file://`
address of the note) or at another Easel (`parc://easel/<id>`), besides web
addresses. Clicking one opens the note or Easel the way note links do.
Notes list the Easels that link to them under "N backlinks", and renaming or
moving a note rewrites those links in the Easel documents, changing only the
link, as one undo step in each Easel. `EaselBacklinkScanner` and
`EaselBacklinkRewriter` in ParcCore read and rewrite Easel documents;
`NoteBacklinkIndex` lists the Profile's Easel files off the main thread and
re-reads the ones that changed.

Dragging a note or an Easel from the sidebar onto the canvas puts a text
object with its title as a link where the drop lands, as one undo step.

## Send to Easel

Send to Easel and Copy to Easel, in the right-click menu of a selection, list
the Profile's other Easels (the twelve most recently edited) and New Easel. Send
moves the objects, Copy leaves them, and both take their pictures and other
assets along. The objects land beside what the other Easel already holds, on its
first page, and each Easel gets one undo step. Locked objects stay behind when
moving. A locked Easel isn't offered as a destination or a source.

## Lock Easel

Lock Easel, in the page menu like Lock Note, makes the canvas view-only: no
tools in the bar except Select, Hand and zoom, no typing, dropping, pasting or
moving, and no context menu. Panning, zooming, copying, opening links and the
live pages inside the Easel still work, and Undo undoes the lock. The document
refuses every other change while locked, so nothing else can edit it by
accident. `EaselDocument.locked` is left out of the file when unlocked.

## Easel History

Easel History, in the ••• page menu, keeps restorable versions of an Easel the
way Note History does for notes. Parc keeps the Easel as it was when you
started changing it, then a snapshot at most every five minutes while you
work and one more two minutes after you stop. Edits made in an Easel block in
a note count too, since they're the same Easel. Identical states are never
stored twice. Snapshots are whole Easel files kept beside the Easels, in a
`history` folder named after each Easel, and point at the same stored images,
so nothing is copied twice. Each Easel keeps its newest 40 snapshots, up to
96 MB. Deleting an Easel deletes its history; moving one to another Profile
starts its history afresh there.

The panel lists the current version and each snapshot with when it was saved
and how many objects it had, and previews the selected one drawn exactly as
the canvas would draw it, on the Easel's own light or dark paper. Restore
first keeps the current state as a snapshot, then brings back the old one,
with its title, icon, pages and objects, as a single undo step, so ⌘Z returns to where you were. ↑ and ↓ move through the
list and Return restores. A version whose pictures are missing can't be
previewed and won't restore, and the Easel stays as it was.

## Export a selection

⇧⌘E with objects selected (and the canvas holding the keyboard) opens Export
Selection beside them; the same list sits under Export Selection in the
right-click menu. Image, PDF and HTML File save just what's picked, using the
same drawing as the whole-Easel exports. Picking a section brings its
contents, and stuck-on highlights and stamps come along with their object;
objects tucked in a hidden section stay out, as on the canvas. A connector
whose other end is left out keeps its last route. Copy as Image in the same
menu follows the same rules and puts a PNG on the clipboard. While text is
being edited, ⇧⌘E stays with the text.

Copy as Markdown in the page menu and Export → Markdown File… write the Easel in
reading order: pages become headings, sections become headings with their
contents under them, then text (headings, lists, quotes, bold, italic, strike,
code and links), stickies as list items, tables as Markdown tables, code
blocks as fences, links, bookmarks and embeds as links, and pictures and videos
as links to files saved in a "<name> Files" folder beside the file (a copy
carries their alt text instead). `EaselMarkdown` in ParcCore builds a note page
from the Easel and the note Markdown writer does the rest.

Stickies as CSV (in Export Selection when the pick has stickies, and in the •••
menu's Export list for the whole Easel) saves one Content column, a row per
sticky in reading order, as UTF-8 with a byte order mark so spreadsheets read
accents. `EaselSelectionExport` in ParcCore picks the objects and writes the
CSV.

## Templates

Seven starter boards built from everyday Easel objects: Brainstorm, Retro,
Kanban, Flowchart, Weekly Plan, Mind Map and Moodboard. The gallery opens
from the toolbar's Templates button, Templates… in the ••• menu and the Add
search, and its cards sit in the [empty Easel's welcome](easel-appearance.md#first-run),
under the key chips. Each card
shows the board drawn by the canvas itself, on the Easel's light or dark
paper. Arrow keys move between cards, Return or Space adds one and Escape
closes the panel. Cards lift and cast a shadow under the pointer or the keyboard
highlight and squish when pressed (see [Easel motion](easel-motion.md#controls)).

Adding a template is one undo step. It lands centred in the view above
everything already there, never off the board's top or left edge, and comes
in selected so it can be dragged straight away; a board bigger than the view
is zoomed to fit. Stickies sit inside their sections, so moving a section
carries them along, flowchart connectors are real connectors that follow
their shapes, and the Mind Map template is a real two-sided
[mind map](easel-mind-maps.md) ready for ⌘Return. `EaselTemplates` in ParcCore holds the
boards; `EaselTemplateGallery` is a self-contained view any surface can place.

## Timer

The timer button sits in the Easel's top-right chrome, before Undo. It opens a
small Notes-style panel with the countdown: − and + (or ↑ and ↓) change it a
minute at a time, ⇧ makes that five, up to 99:59. Start runs it, Space or
Return pauses and resumes, +1 min adds a minute while it runs or is paused
(it never takes time away mid-run) and Reset goes back to the set length.
While it runs or is paused the chrome button shows the time left in the
accent colour, so the panel can stay closed. The digits roll as they change
(up when time is added, down as it counts), Start and Pause cross-fade, and
pausing blinks the clock. At 00:00 the button shakes and glows in three soft
pulses (a single soft fade with Reduce Motion), a quiet "Time's up" toast
appears and VoiceOver announces it.

There is one timer per Easel, shared by every tab showing it. It lives only
while Parc runs and is never saved in the Easel. The countdown rules are
`EaselCountdown` in ParcCore.

## Checks

`tests/EaselBoardFeaturesTests.swift` is a windowless suite over the ParcCore
board logic: find order, visibility, matching, replacement across rich text
runs, per-object and per-table refusals, the find session's replace and
refresh rules, viewport focus, object links, history names, caps and
recording against a temporary store, selection export scope and the sticky
CSV, and that every template is a valid Easel. Build it with every `Sources/ParcCore` file
plus `tests/Support/TestFailure.swift` and run the binary. The views are
checked by compiling only.
