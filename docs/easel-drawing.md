# Easel drawing

The Draw tools put ink, highlights and tape on an Easel the way a pen, a
highlighter and a roll of washi tape would, plus an eraser that lifts whole
strokes. They stay armed until V, Esc or another tool, so several strokes in a
row need no extra clicks. Tool keys, arming and the Draw menu live in
[tools and navigation](easel-tools.md); this guide owns how strokes behave,
look, stick and export.

| Tool | Key | What it does |
| --- | --- | --- |
| Marker | M | Freehand ink in the palette colours, thin, medium or thick |
| Highlighter | ⇧M | Wide translucent strokes in highlight colours that deepen where they overlap |
| Washi tape | W | Drag to lay a straight strip of patterned tape |
| Eraser | ⇧Delete | Click or drag over drawings to lift each stroke it touches |

## Strokes

While you draw, pointer samples closer than one screen point to the last one
are skipped, and the live stroke is drawn through the midpoints of its samples
with quadratic curves that end at the pointer, so smoothing never trails
behind. On release the stroke gets one light smoothing pass that keeps both
ends where the pen was, then a simplification that keeps it within about half
a screen point of what was drawn. Bunched samples are dropped first and long
strokes simplify in 512-point windows, so the work grows only with the
stroke's length. The saved points are drawn with the same midpoint curves on
the canvas and in every export. While you drag, only the newest bit of the
stroke is repainted, so long strokes stay as quick as short ones.

A click without a drag leaves a dot with the marker or highlighter; tape needs
a short drag. New strokes aren't selected, so the selection outline never
covers fresh ink, and Esc during a stroke cancels it and puts the previous
selection back. Each stroke is one Undo step.

Holding Shift draws a straight line from where the stroke started to the
pointer. Within five degrees of level, upright or a diagonal it settles exactly
on that angle; anywhere else it keeps the angle you drew. Shift can come and go
mid-stroke: the freehand path is recorded the whole time, so letting go returns
to it. Washi tape is always straight, and Shift snaps it to 45 degree steps.

Two-point drawings (Shift lines and tape) resize lengthwise: their handles keep
the line's angle and change its length. Every other drawing scales
proportionally. Stroke width never scales with a resize; the width presets stay
true.

## Highlighter

Highlights use the highlight palette (light variants of the Notes colours,
yellow by default) at the highlighter's translucency and width presets, from
the [palette and widths](easel-appearance.md#ink-and-saved-colours). On light
paper a highlight multiplies with whatever is under it, so text and pictures
stay crisp and two overlapping strokes deepen like real ink. On dark paper,
where multiplying would vanish into the page, it paints normally so it still
glows. One stroke never darkens where it crosses itself. Exports carry the same
rule on the path itself (`mix-blend-mode` and `stroke-opacity` in its own style),
so a standalone SVG multiplies and stays translucent without the HTML wrapper;
a small embedded rule only switches the blend to normal on dark screens.

## Washi tape

Tape comes in seven original designs: Stripes (the default), Polka dots, Grid,
Zigzag, Gingham, Confetti and Kraft. Each is a small tile of rectangles, dots
and polygons in Notes colours, described once in ParcCore so the canvas, PDF,
PNG and HTML all show the same pattern. A strip is 28 points tall, 90% opaque
with a soft shadow and a lighter top edge, and both ends are torn. The tear is
seeded by the strip's ID, so every strip tears its own way and keeps it.

In exports each tape gets a pattern id and a clip id made from a per-export counter plus its item id, so repeated ids or two Easels on one page never collide.

The stroke colour retints a design: a palette colour swaps the design's colour
family, a custom colour becomes the tape itself, and Default keeps each
design's own colours. Tape keeps its colours in dark mode, like a sticker or a
photo does. The selection toolbar's pattern control changes the selected strips
in one Undo step and becomes the pattern for the next strip.

## Sticking to objects

A highlight or strip of tape sticks to the topmost object under most of it:
more than half of 48 points spread along the stroke must land on that object.
Stickies, shapes, text, images, captured pages and links can hold them.
Sections, drawings, connectors and locked objects can't: a locked object is
treated as background, so deleting a locked backdrop never takes the board's
highlights with it. Marker doodles never stick, so a doodle stays where you
drew it.

When you move, resize or rotate an object, everything stuck to it follows
exactly: a resize stretches stuck drawings with it, a rotation swings them
around the object's centre, and other stuck objects keep their size and turn
with it. When an object changes size on its own, like a sticky growing as you
type, stuck things stay pinned to its top-left corner instead of stretching.
This runs in the Easel's dependents pipeline after sections carry
their contents and before connectors reroute, so anything already moved by the
same edit, dragged along or carried by its section, isn't moved twice, and
connectors attached to a follower reroute with it. Chains (tape on a stamp on a
sticky) follow link by link, objects stuck to each other settle in one pass, and
a highlight stuck to something that no longer exists stays put.

Dragging a highlight or strip on its own picks what it sticks to again, or
unsticks it on empty paper; dragging it together with its object keeps them
together. Deleting an object deletes everything stuck to it, whole chains
included.

## Eraser

The eraser lifts whole strokes: marker doodles, highlights and tape, never
other objects or locked drawings. It reaches nine points around the pointer at
any zoom and shows a soft round cursor. Strokes it touches fade while you drag
and poof away together on release as one Undo step; Esc puts them back. Tape is
caught across its full rectangle, flat torn ends included. A short tapering
trail follows the pointer and fades within a third of a second; with Reduce
Motion there is no trail.

Erasing whole strokes rather than splitting them is deliberate: it keeps every
drawing one object with one Undo step and matches what people expect from a
whiteboard eraser.

## Saved format

Drawings are `freehand` objects. New strokes save their `brush` (marker,
highlighter or washi tape), and that is what draws them through the smooth
midpoint curves. Doodles saved before brushes existed have no `brush` and keep
drawing, exporting and resizing as the straight segments between their saved
points, so an older Easel looks exactly as it did. `pattern` names a tape design
and is absent for Stripes; `attachedTo` names the object a drawing sticks to.
All three are optional.

## Code and checks

- `Sources/ParcCore/EaselDrawing.swift`: sampling, smoothing, simplification,
  straight lines, eraser hits, attachment choice and the attachments step of
  `EaselDependents`.
- `Sources/ParcCore/EaselWashi.swift`: tape designs, torn outlines and placement.
- `Sources/ParcCore/EaselDrawingExport.swift`: SVG and HTML for every brush.
- `Sources/ParcEasels/EaselCanvasView+Brushes.swift`: drawing, strokes, the eraser
  and the pattern command.
- `swift test --filter EaselFreehandDrawingTests` runs the windowless
  suite.
