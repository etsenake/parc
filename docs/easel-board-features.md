# Easel board features

Board-wide tools that work across a whole Easel rather than on one object:
find and replace. They sit beside the [Easel editing contract](easels.md) and
use the Notes look ([appearance](easel-appearance.md)) and motion rules
([motion](easel-motion.md)).

## Find and replace

⌘F opens the Notes find bar over the top right of the canvas, with the same
field, count, Match Case, previous and next arrows, Replace disclosure and
chips. ⌥⌘F opens it with Replace showing. The chords belong to the Easel while
the canvas, one of its object stops, an object being edited, the title or the
find bar has the keyboard; inside a live webpage on the canvas they stay with
that page, as in a note's embeds.

Finding runs as you type over every object that shows text: text objects,
stickies, shape text, connector labels, section titles, and the titles of link
and webpage cards. Matching ignores case and accents until Match Case is on.
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

Matches are highlighted on the canvas in the Notes find colours. Text objects
highlight the matched words themselves, with the current one outlined. Other
objects get a soft ring, and the current match's object a stronger ring and
wash. Highlights are drawing only: they never reach the document, exports or
the selection.

Replace changes the current match and moves to the next; Replace All (or
⌘Return in the replace field) changes every match and flashes the count. Each
is one undo step. A replacement takes the formatting of the first character it
replaces, never swallows an inline picture, and grows a text object to fit.
Locked objects and link or webpage card titles are found but never replaced,
so Replace All may change fewer than it found. Escape closes the bar and
selects the object of the last current match, ready for the keyboard.

The matching, reading order, replacement and viewport maths are pure ParcCore
code (`EaselFinder`, `EaselViewportFocus`). Adding a kind that shows text means
listing its text in `EaselFinder.searchableParts(of:)` and saying whether it is
replaceable; tables and code blocks join the same way once they exist.

## Checks

`tests/EaselBoardFeaturesTests.swift` is a windowless suite over the ParcCore
board logic: find order, matching, replacement across rich text runs, refusals
and viewport focus. Build it with every `Sources/ParcCore` file plus
`tests/Support/TestFailure.swift` and run the binary. The views are checked by
compiling only.
