# Rotate and flip

Easel objects can be turned to any angle and mirrored left to right or top to
bottom. This guide covers which objects turn, every way to do it, how a turned
object behaves afterwards and how it is saved. It sits beside the
[Easel editing contract](easels.md), the Notes look
([appearance](easel-appearance.md)) and the [motion rules](easel-motion.md).

## What turns and what flips

| Object | Rotates | Flips |
| --- | --- | --- |
| Shapes (rectangles, ellipses and the shape library) | Yes | Yes, text stays readable |
| Text | Yes | No |
| Images | Yes | Yes |
| Drawings, highlights and washi tape | Yes | Yes |
| Stamps | Yes | Yes |
| Stickies, sections, connectors, tables, code blocks, links, captured webpage cards and live webpages | No | No |

Stickies, sections, connectors and tables stay upright as in other whiteboards.
Live webpages and captured cards are real native pages that can't be drawn at
an angle, so they stay upright too. Locked objects refuse rotation and flips
like every other change. A group or a selection of several objects turns and
flips as one; the members that can't turn stay where they are.

`EaselRotation` in `Sources/ParcCore/EaselTransform.swift` owns these rules.
Kinds it doesn't list stay upright and unflipped, so a new kind turns only once
it is added there.

## Turning with the pointer

A selection that holds something turnable has a rotate zone just outside each
corner. Hovering there shows the rotate cursor, a curved double arrow that
faces away from that corner. Dragging turns the selection around its centre:

- in 15° steps, so a single object lands on 0°, 15°, 30° and so on, with a
  light haptic tick as each new step clicks in;
- freely while ⌘ is held (⌘ already means "no snapping" for alignment guides);
- with a small angle badge beside the pointer, the same pill as the text size
  badge, showing the object's new angle (or, for several objects, how far they
  have turned).

A press without a three-point drag changes nothing. The resize handles sit on
the corners and win over the rotate zone, which starts just beyond them. The
whole turn is one Undo step named "Rotate objects".

## Keys, menus and VoiceOver

| Action | Keys | Also in |
| --- | --- | --- |
| Rotate 1° left / right | ⌥← / ⌥→ | |
| Rotate 15° left / right | ⇧⌥← / ⇧⌥→ | VoiceOver actions "Rotate left 15°" and "Rotate right 15°" |
| Rotate 90° left / right | | Right-click menu |
| Flip horizontal | ⇧H | Right-click menu, VoiceOver action |
| Flip vertical | ⇧V | Right-click menu, VoiceOver action |

Other whiteboards rotate with ⌘⌥↑/↓, but those are Parc's Previous and Next
Tab chords, so Easels use Option with the left and right arrows instead: left
turns counter-clockwise, right turns clockwise, and Shift takes the bigger step
just as it nudges further. The keys work while the canvas or one of its object
stops has the keyboard. ⇧H and ⇧V come from the Easel key map in
`EaselTool.swift`. After a VoiceOver turn, the new angle is announced.

Every route calls the same canvas commands, `rotateSelection(by:)` and
`flipSelection(horizontal:)`, which the floating selection toolbar can call
too. Each is one Undo step, keeps the selection and moves anything stuck to a
turned object along with it.

## How a turn works

An object keeps its upright frame; `rotation` turns it clockwise around the
frame's centre and the flips mirror it inside its own frame, flip first and
turn second. One transform per object, applied around the whole drawing in
the canvas, carries every kind, so image, PDF and Copy as Image exports match
the canvas. HTML exports wrap each object's SVG in the same `rotate` and
`scale` steps.

Flipping a turned object mirrors it on screen: Flip Horizontal mirrors it
across a vertical line, so its angle changes sign as well. Flipping several
objects mirrors each one and swaps their places across the selection's centre.
Text in such a selection moves to its mirrored place and angle but keeps its
letters readable. A flipped shape mirrors its outline and keeps its text
readable at the mirrored spot.

Turning several objects swings each member's centre around the selection's
centre and adds the turn to its own angle. Connector lines in the selection
swing with them, and highlights or stamps stuck to a turned object ride along.

## Living with a turned object

- **Clicks and selection boxes** use the turned outline: the empty corners of a
  turned square don't catch clicks, and a selection box only catches what it
  actually touches.
- **Selection chrome** follows the turn: the outline and the corner handles sit
  on the turned corners of a single object. Several objects keep an upright
  box, which turns with them while you drag.
- **Resizing** a single turned object works along its own sides: the opposite
  corner or edge stays put on screen, Option resizes around the centre and
  images keep their shape. Dragging a handle past the opposite edge mirrors
  shapes, images and drawings, and keeps text readable. Alignment guides don't
  snap while a turned object is being resized.
- **Guides, align, distribute and tidy** use the turned bounding box, as do the
  floating toolbar's placement, the VoiceOver frames and export bounds.
- **Editing text** on a turned object straightens it while you type, so the
  caret, selection, spelling marks and input methods line up exactly with the
  native text view. It turns back when you finish. Flips stay on while you
  type.

## Saved format

`rotation` holds degrees clockwise between −180 and 180 with two decimals;
`flipHorizontal` and `flipVertical` are `true` or absent. All three are left
out of the file for an upright, unflipped object, so older Easels open and draw
exactly as before. Stray values on objects that can't turn or flip are ignored
when drawing.

## Checks

`swift test --filter EaselTransformTests` covers the transform
maths, the kind rules, turned hit tests and selection boxes, turned resizing,
group turns and flips, the drag's snapping, the selection chrome and the SVG
output. The canvas glue is compile-checked with the app.
