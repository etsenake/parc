# Easel board features

Board-wide tools that work across a whole Easel rather than on one object:
find and replace, links to a single object and Easel History. They sit beside
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
Each step glides the canvas to the match, keeping it clear of the bar, zooming
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
first keeps the current state as a snapshot, then brings back the old one as
a single undo step, so ⌘Z returns to where you were. ↑ and ↓ move through the
list and Return restores. A version whose pictures are missing can't be
previewed and won't restore, and the Easel stays as it was.

## Checks

`tests/EaselBoardFeaturesTests.swift` is a windowless suite over the ParcCore
board logic: find order, visibility, matching, replacement across rich text
runs, per-object and per-table refusals, the find session's replace and
refresh rules, viewport focus, object links, and history names, caps and
recording against a temporary store. Build it with every `Sources/ParcCore` file
plus `tests/Support/TestFailure.swift` and run the binary. The views are
checked by compiling only.
