# Arranging Easel objects

How people select, line up, stack, group, lock, duplicate and move objects
between Easels, and the right-click menu that gathers those commands. The
pure rules live in `EaselArrange` and `EaselChords` in ParcCore; the canvas
commands, clicks and menu live in the `EaselCanvasView+Arrange`,
`+Clipboard` and `+ContextMenu` extensions. Text editing, the selection
toolbar and export stay in the [Easels guide](easels.md).

## Selecting

A click selects the topmost unlocked object under the pointer and Shift-click
adds or removes it. Clicking any member of a group selects the group (its
unlocked members), and Shift-click adds or removes it as a whole.
Double-clicking a member enters the group and selects just that member: from
there clicks pick single
members, a dashed outline shows which group is open, and double-clicking a
member again does its usual thing (edits text, opens a link). Return on a
selected group enters it with all its members selected; Shift-Return selects
the whole group again from any of its members. Clicking empty canvas, Escape
or selecting something outside the group leaves it.

A marquee catches anything it touches, skips locked objects, and widens to
whole groups (minus any locked members) unless the group is open. Select All
(⌘A) skips locked objects too, and leaves out contents a section is hiding.

Undo and Redo select what the step brings back or changes, such as a moved
object or a restored deletion, leaving out connectors and stuck-on objects
that only followed along; a single member of a group comes back with its
group open. A step that only removes objects or restacks them leaves the
selection as it is.

## Locking

⇧⌘L locks the selection; on a selection that is all locked it unlocks. A
locked object can't be moved, resized, nudged, edited, deleted, cut, grouped,
aligned or restacked, takes no new connector ends and offers no quick-create
dots. Parc's decision for plain clicks: they pass straight through a locked
object to whatever is under it, so a locked background image or section lets
people click, double-click (new text) and marquee on top of it. Shift-click
still selects a locked object, which is how people pick locked objects to
unlock. Locked objects can still be copied and duplicated, and the copies
stay locked.

A small lock badge sits in the top-right corner of a locked object while the
pointer is over it or it is selected (just outside the corner on tiny
objects). Clicking the badge offers **Unlock** (or **Unlock Group**). Sections
build their Lock All and Lock Background Only on the same lock.

## Lining up and spreading out

With two or more movable objects selected, **Align and Distribute** in the
right-click menu (and the selection toolbar) lines them up to the
selection's bounds: left, center or right edges, and top, middle or bottom.
Distribute needs three or more and leaves equal gaps between neighbours,
ordered by their centres, keeping the outermost two in place. **Tidy Up**
takes three or more objects (connectors and sections sit it out) and deals
them into an even grid with 24-point gaps, starting at the selection's top
left. It keeps reading order: objects whose centres share a row stay in that
row, rows run top to bottom, and the widest row sets the column count. A
messy pile, where the objects overlap more than they cover, becomes a square
grid instead.

A whole group moves as one block for every arrangement command, while the
members of an open group move one by one. Locked objects don't move and don't
count towards the edges. Arrows connected to objects and objects stuck to
another object follow their target through the dependents pipeline rather than
moving on their own. Rotated objects arrange by the box around their turned
outline. Every arrangement is one Undo step.

## Layer order

Bring to Front (`]`), Bring Forward (⌘]), Send Backward (⌘[) and Send to Back
(`[`) restack the selection. Forward and Backward step over the next object
the selection actually overlaps, so a click always shows a change when one
is possible, and a whole group moves through the stack together, keeping its
own order. Highlights, washi tape and anything else stuck to an object move
with it and stay just above it. Restacking renumbers the layer order from the
bottom, which keeps it free of ties and safe from overflow however many times
people restack.

## Grouping

⌘G groups two or more unlocked objects. Groups are one level deep: grouping
objects that already belong to groups moves them all into the new group, and
a group left with a single member dissolves. ⇧⌘G ungroups (⌘Delete does too);
ungrouping from any member frees the whole group. Duplicating a member inside
an open group adds the copy to that group, while duplicating or pasting a
whole group makes a new group of its own.

## Duplicating and dragging

⌘D duplicates the selection 24 points down and to the right with the copies
selected. Move the copies and press ⌘D again and the next copies repeat that
same step, so a row or a diagonal builds itself. Option-dragging an object
leaves the original where it was and drags a copy, which also becomes the step
⌘D repeats; Escape halfway removes the copy and selects the original again.
Holding Shift while dragging keeps the move on its stronger direction,
horizontal or vertical.

Arrow keys nudge the selection by one point, or ten with Shift. A run of
nudges on the same selection is one Undo step, so holding an arrow key and
pressing ⌘Z puts everything back where the run started.

Duplicating or copying an object brings along whatever is stuck to it. Copies
get fresh IDs. Group membership, connector ends, sticky-on targets and
manual bends are remapped inside the copied set; links to objects that weren't
copied are dropped, so a copied connector keeps its last route as free ends.

## Clipboard

⌘C, ⌘X and ⌘V copy, cut and paste any objects with their styles, text and
pictures. Copy writes a private, versioned Easel payload carrying the objects
and the bytes of their pictures, so pasting works within an Easel, between
Easels and across Profiles (pictures are imported into the receiving Easel).
Alongside it go fallbacks for other apps: the picture itself for a single
image, otherwise a PNG of the selection on the Easel's own paper, RTF of the
selection's text and plain text with link addresses. Cut copies first and
deletes only after the copy succeeded; locked objects are never cut.

Pasted Easel objects land centred under the pointer when it is over the
canvas, stepping 24 points for each repeat at the same spot. Without the
pointer, a paste into the same Easel sits 24 points from the originals
(stepping further each time), lands exactly in place after a cut, and
otherwise goes to the middle of the view. Paste Here on empty canvas puts
copied Easel objects at the click point, and Paste as Plain Text there makes a
text object from the words alone at the click; Paste and Paste as Plain Text
in an object's menu land at the click the same way. Images, links, rich text
and diagrams from other apps keep their usual landing spot.

## Keyboard chords

Command chords go through the canvas's single `performKeyEquivalent(with:)`
and the `EaselChords` table: ⌘D duplicate, ⌘G group, ⇧⌘G and ⌘Delete
ungroup, ⇧⌘L lock, ⌘] and ⌘[ restack. The Easel wins when the canvas, one of
its object stops or its text editor has focus and the command applies to the
selection; otherwise the chord falls through to Parc, so with nothing
selected ⌘D still pins a tab, ⌘G finds the next match and ⌘[ goes back. In an
Easel block inside a note, the note steps aside while the block has focus, so
the Easel's chords win over the note's own (such as ⌘G for find). Easels
never take ⌘L, ⌘P, ⌘K, ⇧⌘K, ⇧⌘C or ⌘⌥↑/↓ (a test checks the table). Bare
`]` and `[` come from the tools key map. Other features add a chord with a
case in `EaselChordCommand`, a line in the table and a line in
`performChord`.

## Right-click menu

Right-click or Control-click opens a Notes floating menu at the pointer,
with the same rows, highlight, motion and keyboard handling as the Easel page
menu. VoiceOver's Show Menu opens it from the keyboard.

- **Objects:** Cut, Copy, Paste, Paste as Plain Text, Duplicate, Delete;
  Order ▸ (the four layer moves), Align and Distribute ▸ and Tidy Up for
  several objects, Group or Ungroup, Lock or Unlock, then section, shape and
  transform rows; Make Live or Back to Snapshot, Open Source and Copy Source
  URL for web objects, then text, link, media and other per-kind rows; Copy as
  Image (a PNG of the selection), Select All and zoom rows; Use Alignment
  Guides.
- **Empty canvas:** Paste Here and Paste as Plain Text at the click point,
  Select All with the zoom and board rows, and Use Alignment Guides.

Other features add rows without touching the menu code: each implements its
own slot from `EaselCanvasMenuSlots` (`sectionMenuRows`, `shapeMenuRows`,
`transformMenuRows`, `textMenuRows`, `linkMenuRows`, `mediaMenuRows`,
`zoomMenuRows` and friends) in an extension of the canvas, and `modeMenuRows`
can take over the whole menu while a mode such as image cropping is active.
Rows run through `guardedMenuAction`, which refuses to act once the window or
the selection has changed under an open menu.

## Checks

`bash scripts/test-notes-editor.sh EaselArrangeTests` runs the windowless
suite for alignment, distribution, Tidy Up, layer order, groups, locks,
duplicate remapping, the clipboard payload, paste placement, click and marquee
rules and the chord table; `NoteKeyEquivalentBoundaryTests` covers the note
stepping aside for an Easel block. `python3 tests/EaselArrangeCanvas/run.py`
builds a real canvas without a window (from the canvas bundle's file list in
`scripts/test-easels.sh`) and checks Option-drag undo and cancel, Select All,
group clicks and chord fall-through, including ⌘G going to an open find bar.
