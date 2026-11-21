# Easel stickies and sections

Sticky notes and sections are the board objects of an Easel. They follow the
[Easel editing contract](easels.md), the Notes look
([appearance](easel-appearance.md)) and the [tools](easel-tools.md) that place
them. The geometry lives in `EaselBoardObjects` (ParcCore); the canvas owns
drawing in `EaselCanvasView+Stickies.swift` and `EaselCanvasView+Sections.swift`.

## Placing a sticky

S arms the sticky tool. A click drops a 220 point square centred on the
pointer; a drag drops it where the drag ends, since stickies aren't
drag-sized. The new sticky is selected and already editing, so typing goes
straight in. It takes the remembered sticky colour. Quick create (⌘Return
next to a sticky) makes a blank one with the same colour, width and scale.

## Typing in a sticky

Stickies use the same text editor as text objects and shapes
(`beginEditing`). Double-click a sticky, or press Return with one selected,
to edit it; a double-click puts the caret where you clicked. The editor sits
in the sticky's padded text box (`EaselBoardObjects.stickyTextBox`) and types
from the top in the sticky's own text style, alignment and formatting.

The sticky grows taller as the text wraps and shrinks back to its square as
text goes, never below its minimum, easing to each new height on the settle
spring (instantly under Reduce Motion). The height refit rides in the same text
commit as the typing, so one Undo takes back a whole editing session's
typing and growth together. While an input method is composing, the editor
keeps its frame and nothing is saved until the composition lands. Emptying a
sticky keeps it on the board; Escape finishes editing.

Stickies scale as a whole (see below). Their text is stored at the regular
size and shown through `EaselStickyText.presented`, which multiplies every
font and spacing by the sticky's scale; typing saves back through
`EaselStickyText.stored`, which divides it out again. The text margin (the
sticky's padding plus the text inset and line padding) scales too, and the
editor, the drawn text, the height refit and HTML export all take their insets
from `EaselTextLayout.inset(scale:)` and `fragmentPadding(scale:)`, so a big
sticky stays roomy and grows exactly as far as its text. Format bar sizes and
size steps read and change the unscaled size, so making text larger in a
doubled sticky shows the doubled larger size.

## Sticky size

The selection toolbar's wide toggle switches selected stickies between a
square and a 440 point wide sheet, keeping the top-left corner and rewrapping
the text. A side handle widens a sticky between one and four squares. A corner
handle scales the whole sticky, paper, padding and text together, between a
quarter and eight times; top and bottom handles are hidden, since the height
always follows the text. Stickies never rotate or flip.

## Sections

⇧S arms the section tool. A click drops a 640 by 480 section centred on the
pointer and a drag sizes it (at least 120 by 80). Create Section, from the
selection toolbar or the context menu, wraps the selection with 48 points of
room. New sections are named Section, then Section 2 and so on.

A section contains whatever lies entirely inside it, including smaller
sections. Sections paint behind other objects, nested ones above their
parents. Moving a section carries its contents; resizing it changes only
what it contains. A click inside a section's empty area starts a marquee, and
a short click selects the section. Carrying objects over a section they would
join lights up its tray, and dropping them in flashes its border once.

### Title

The title tab sits above the section's top-left corner (inside it when there
is no room above) and keeps a readable size when zoomed out. Double-click the
tab, press Return with the section selected, or choose Rename Section to edit
the title in place. Return or clicking away saves, Escape cancels. Titles are
one line of at most 120 characters; an empty title goes back to the next free
default name. Locked sections can't be renamed.

### Hidden contents

Hide Contents (toolbar, context menu or VoiceOver action) tucks everything
inside away and shows a count such as "3 objects hidden" in the middle.
Hidden objects aren't drawn, selected, found, marqueed, chosen by Select All
or exported. Show Contents brings them back. Hiding is saved with the board.

### Locks

Lock All locks the section and everything in it. Lock Background Only locks
just the section, so its contents stay editable while the section stops
moving and lets clicks pass through. Unlock Section unlocks the section and
its contents. Locked objects show the lock badge described in
[arranging](easel-arranging.md).

### Deleting

Delete removes a section with its unlocked contents. Delete Section Only
(⌘⌫ with a section selected, or the menu) removes just the section and leaves
its contents where they are. Each is one Undo step.

## Saving and export

Stickies save their frame, fill, text and an optional `textStyle.textScale`;
sections save their title in `text` and `contentsHidden` only when true.
PDF, PNG and Copy as Image draw through the canvas. HTML export draws sticky
paper and text at the same padding and scale, and sections with their title
tab and border, leaving hidden contents out.
