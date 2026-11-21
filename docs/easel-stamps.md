# Easel stamps

Stamps are small stickers for reacting on a board: eight original vector
designs, any emoji, or an SF Symbol icon. They sit beside the
[Easel editing contract](easels.md), follow the [tools](easel-tools.md) rules
and use the Notes look ([appearance](easel-appearance.md)) and motion rules
([motion](easel-motion.md)).

## The stamp tool

E (or the toolbar's Stamp button, or Quick actions) arms the stamp tool and
opens the stamp wheel at the pointer. If the pointer isn't over the canvas, it
opens in the middle of the view; from the toolbar it opens under the button.
The wheel always fits inside the visible canvas.

- The ring holds the eight designs, starting at the top and running clockwise:
  thumbs up, heart, plus one, star, smiley, question, dot, thumbs down.
- The centre shows up to three recent emoji or icons, plus a + button.
- + or E again opens the full picker. It has two tabs: Emoji, which is the
  Notes emoji picker, and Icons, a searchable list of diagram icons grouped
  into Systems, Devices, People and more.
- On the wheel, 1–8 pick a ring stamp, the arrow keys move around it, Return
  or Space picks the highlighted one, and Escape closes it. VoiceOver reads
  each slot as a button.

Picking a face closes the wheel, and the pointer becomes that stamp. The tool
stays armed until V, Escape or another tool, so you can keep stamping. The
last face you picked is remembered across Easels.

## Stamping

A click stamps at the pointer, with a slight random tilt of 3–10° either way.
Hold the click and the stamp grows through four sizes (64, 96, 136 and 184
points), one step every 0.3 seconds, and it follows the pointer until you let
go. With Reduce Motion on it jumps between sizes without the smooth grow.
Return stamps the middle of the view.

⌘Return with the stamp tool armed stamps every selected object, lining stamps
up from its top-right corner (turned objects get them on their turned corner).
If a stamp is selected, the object under it gets the new one, so pressing
⌘Return again keeps adding to the same object. All the stamps from one press
are one undo step, as is each click.

## Sticking to objects

A stamp sticks (`attachedTo`) to the topmost object under its centre that can
hold one: not connectors, other stamps, doodles, sections or locked objects.
Landing on a stamp passes it through to what that stamp sticks to. Stuck
stamps move and turn with their object, and deleting the object deletes
its stamps. Dragging a stamp somewhere else re-sticks it to whatever it lands
on, or frees it on bare board. Pasted and duplicated stamps stick to whatever
they land on. All of this runs through `EaselDependents.settle` and
`removing` ([drawing](easel-drawing.md)), which the canvas calls on every
commit.

## Faces and saving

Designs save as `stamp`, emoji as `text`, and icons as `text` with an `icon:`
prefix plus a `color`. Icons recolour like any other object, from the
selection toolbar's style button or the right-click colours, palette colours
included, and export that colour (palette ones follow light and dark). Emoji go through `EaselStampFace(emoji:)`, which accepts
exactly one emoji, either one that looks like emoji by default or one followed
by the emoji selector (U+FE0F). It adds the selector to bare text-style forms
such as ❤ and refuses anything else, so a bad pick never reaches the document
and can't block saving. Saved files must already hold the tidy form.

The Emoji tab is the Notes picker including its custom emoji section, with `+`
and Edit, from the Notes folder's emoji library (the first notes folder that has
any). A custom emoji stamps like any emoji and is saved by name as its
`:name:` text. It draws from the library's picture, so renaming keeps working
through the library's aliases; if the emoji is deleted, the stamp shows its
`:name:` text instead and keeps the name. PNG, PDF and Copy as Image use the
canvas drawing; HTML and SVG export embed the picture, or the text when it is
gone.

## Drawing and export

`EaselStampArtwork` caches each design's layers, emoji measurements and SF
Symbol images, including the placeholder for missing symbols. See-through
layers are bounded to the stamp's own rim. PDF, PNG and Copy as Image reuse the
canvas drawing; HTML and SVG export use `EaselVectorExport`.

## Where it lives and how to check it

- Model and pure logic: `Sources/ParcCore/EaselStamps.swift` and the face in
  `EaselStore.swift`.
- Artwork: `Sources/ParcApp/EaselStampArtwork.swift`.
- Tool, press and ⌘Return: `Sources/ParcApp/EaselCanvasView+Stamps.swift`.
- Wheel and picker: `Sources/ParcApp/EaselStampPanels.swift`, installed through
  `EaselCanvasView.stampPanelsFactory`.
- Tests: `scripts/test-notes-editor.sh EaselStampTests` and
  `EaselStampArtworkTests`, both windowless. Wheel and picker code is
  compile-only.
