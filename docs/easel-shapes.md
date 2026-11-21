# Easel shapes and text in shapes

Easels have 32 shapes in two families, matching the whiteboard staples people
expect. Basic: rectangle, rounded rectangle, circle, diamond, triangle,
upside-down triangle, pentagon, hexagon, octagon, star, plus, left, right, up and
down arrows, chevron and speech bubble. Flowchart: right- and left-leaning
parallelograms, trapezoid, manual input, cylinder, sideways cylinder, file,
folder, document, stack of documents, predefined process, internal storage,
shield, or and summing junction. Every shape holds text.

One platform-neutral geometry, `EaselShapeGeometry` in ParcCore, owns every
outline. Drawing, selection outlines, hit testing, image, PDF and Copy as Image
export (which reuse canvas drawing) and the HTML/SVG export (which writes the
same outline as SVG path data) all read it, so a shape looks and behaves the
same everywhere. `EaselPath` is the shared path type: moves, lines, quadratic
and cubic curves and closes, with exact bounds, SVG path data, point
containment under either fill rule and distance to the outline.

## Saved format and the original look

Rectangle-kind objects are the shape family: `shape` names the outline and an
absent value means a plain rectangle. Circles stay circle-kind objects, so an
older Parc still draws them round. An object without any of the newer style
fields keeps the original look exactly: a rectangle with five-point corners or
an ellipse, a 9% ink wash and a 2.5-point outline, with the original hit rules.

New shapes save explicit styles, so later default changes never restyle them.
Their outline takes the current ink; a palette ink brings its matching palette
fill, the automatic ink gives the blue pair, and a custom ink gets the neutral
fill. The outline is 2.5 points. Fill, opacity, outline width and dashes come
from the shared paint rules in [appearance](easel-appearance.md).

## Proportions

Outlines fill their whole frame and keep sensible proportions as frames
stretch:

- Rectangles keep five-point corners; rounded rectangles use a fifth of the
  shorter side, between 8 and 36 points.
- Pentagon and star are regular shapes stretched to the frame; the star's inner
  points sit at 0.382 of its radius, so its edges run straight through.
- Hexagons keep 60° sides until that would pass a quarter of the width, octagons
  keep 45° corner cuts and the plus uses arms a third of the shorter side.
- Block arrows use a shaft half the breadth and a head up to half the length;
  chevrons notch as deep as their point.
- Cylinder caps are 14% of the length, at most a quarter of the breadth; the
  front rim is an inner line, like the file's fold, the predefined process and
  internal storage bars, and the or and summing junction crosses.
- Documents end in a wave whose low point touches the frame; the stack offsets
  two pages behind the front one by up to ten points.
- The speech bubble's body is 78% of the height with its tail at the lower left;
  its corner radius never exceeds half the body, so short bubbles stay simple.

New shapes arrive at a size that suits them: 200 × 120 for boxes, 160 × 160 for
round and regular shapes, wide or tall frames for arrows and cylinders and 100 ×
100 for the small flowchart junctions. A shape placed without a frame lands in
the middle of the view and steps 24 points down and right while it would land
exactly on another object, so several placed in a row fan out.

## Text inside shapes

Shapes use the same rich text editor, object-wide styles, text rail and Undo as
text objects. Double-click a shape, press Return with it selected, or use
VoiceOver's Edit text to type in it. `EaselTextPlacement` in ParcCore decides,
per object kind, where text wraps, how it aligns, whether it centres vertically
or clips, whether an empty object retires and whether the frame grows with its
text; the canvas, the editor and HTML export all follow it.

- Each shape has its own text area, inset where the outline narrows: about 71%
  of a circle, the middle half of a diamond, the wide half of a triangle and
  the band across a star's arms.
- Text is centred both ways by default. A chosen alignment on the object's text
  style wins. Alignment is applied for display and stripped again before saving,
  so stored rich text stays clean and old files read the same.
- Shapes never grow with their text, and resizing a shape changes its text area,
  never its text size. Text that doesn't fit stops at the last whole line and
  shows a small accent chevron at the bottom of the text area; editing shows all
  of it, running below the shape. Exports leave the chevron out.
- Emptying a shape's text never deletes the shape. Only empty text objects
  retire at the end of editing.
- Text keeps its object styles (family, size and the content-hugging fill) and
  the text rail treats a selection of text objects and shapes as one.

## Changing a shape

`changeSelectedShapes(to:)` turns every unlocked selected shape into another
outline in one Undo step, keeping its frame, text and style; changing to a
circle makes a circle-kind object, and anything else a rectangle-kind one. The
object menu offers it as **Shape**, a submenu of every shape with its icon and a
check on the current one, which also reaches VoiceOver through the object's
menu action.

`insertShape(_:in:editing:)` adds one shape as a single Undo step, selected
afterwards, at the given frame or the default size in the middle of the view,
and can open its text right away. `selectedShapes` reports the shapes in the
selection for pickers and toolbars. These are the entry points for the
toolbar's shape tool, drag-to-size creation and quick create.

## Hit rules

Shapes in the original look keep the original rules. Every other shape:

- is solid when it has a visible fill or any text, and otherwise takes clicks
  only on a band around its outline, half the 30-point minimum target or half
  the outline width, whichever is wider, measured in screen points at any zoom;
- stays draggable anywhere in its frame while selected;
- keeps the 30-point minimum target when it is small;
- joins a marquee that overlaps it when solid, and only a marquee that touches
  its outline when unfilled, so a marquee inside a big empty shape picks the
  things inside it rather than the shape.

Hit tests map the point into the shape's own space, so rotated and flipped
shapes are hit where they are drawn.

## Rotation, flips and connectors

Rotation turns clockwise around the frame centre and flips mirror the outline
around it. Shape drawing stays upright and leaves turning and mirroring to the
single per-object transform the canvas and HTML export apply, which keeps text
readable inside flipped shapes. Canvas-space helpers serve the rest: `transform(for:)`,
`localPoint(_:in:)`, `visualBounds(of:)`, `outline(for:)`, and
`edgePoint(of:toward:)` and `anchorPoint(of:side:)`, which find where a ray from
the centre leaves the actual outline, so connectors meet a star or a cylinder
at its edge.

## Checks

`scripts/test-notes-editor.sh EaselShapeGeometry` is windowless. It covers every
shape across frames from one point to very long and thin (bounds, containment,
the text area inside the outline, inner lines, SVG data), path maths, rotation,
flips, transforms, hit bands at different zooms, marquee rules, edge points,
text placement and new-shape styles, including that every new shape saves as a
valid Easel.
