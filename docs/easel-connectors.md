# Easel connectors and quick create

Connectors are Easel arrows that can hold on to other objects. An arrow with no
connections, routing or bends is the original free arrow and draws exactly as it
always did; the fields that make it a connector are optional and described in
[the saved format](easels.md#saved-format-for-board-objects). Geometry lives in
ParcCore (`EaselConnectorRouting.swift`) so the canvas, HTML/SVG export and PDF
draw the same route. The canvas side is `EaselCanvasView+Connectors.swift` and
`EaselCanvasView+QuickCreate.swift`.

## Attaching

Every object except another connector can take connector ends: stickies,
shapes, text, images, web items, drawings and sections. Locked objects take no
new ends, and connections made before an object was locked keep working.

- **Side magnets.** Each object has four magnets, top, right, bottom and left.
  On shapes they sit on the shape's own outline (a triangle's top magnet is its
  apex); on everything else they sit mid-way along the frame's edges. Rotated
  objects carry their magnets around with them.
- **Automatic side.** Dropping an end in the middle of a roomy object (at least
  72 points on screen each way) attaches it without a fixed side. The connector
  then leaves from whichever side faces the other end, and keeps choosing as
  things move.
- **Pinned point.** Holding Command while dropping an end pins it to the exact
  spot under the pointer, stored as a fraction of the object's frame so it
  follows resizes, rotation and flips. Straight and curved connectors start
  right at the pin; an elbow leaves from the outline straight out from it.
- **Both ends on one object.** Two automatic ends on the same object take the
  right and bottom sides, and an automatic end beside a fixed one takes the
  next side round, so a loop hops one corner instead of collapsing.

While an end is dragged, the object under the pointer (or within 18 points of
one of its magnets) shows its magnets; the one the end will take fills in, and
an automatic attachment outlines the whole object. Shift snaps a free end to
45° steps from the other end. Dragging an attached end onto empty paper frees it.

A connector with both ends attached doesn't drag on its own: move one of its
objects, or select it together with them. A connector with a free end drags
that end along while the attached end stays put. Deleting or cutting an object
frees the connectors attached to it right where they were: an elbow keeps its
last bends, and a curve keeps passing through its old middle.

## Routes

- **Straight** joins the two ends. Free legacy arrows keep every stored point.
- **Elbow** runs only across and down. Each attached end leaves its side
  perpendicular until it is 20 points clear of its object's box (further for
  rotated objects, whose magnets sit inside that box), and the path steers
  around both attached objects with that same 20-point margin, preferring fewer
  bends and a middle segment centred in the gap. Free elbows make a tidy Z
  through the middle. Routes never wander above or left of the canvas.
- **Curved** is a smooth cubic that leaves and arrives perpendicular to each
  side, with handles 40% of the distance between the ends (24 to 300 points).

Selecting a connector shows its two end handles (attached ends are filled) and,
for elbows, a handle on every segment long enough to grab. Dragging a middle
segment slides it sideways; dragging the first or last segment adds a bend so
the end stays attached. For curves, every span has a handle that adds a
pass-through point when dragged, and existing pass-through points can be dragged
around. Bends are stored as `waypoints` in canvas coordinates. When the attached
objects move, the bends stay and the ends re-square; a manual elbow that can no
longer leave its side cleanly falls back to the automatic route until it fits
again. Changing the connector type or choosing Reset Path clears the bends.

Each settled connector also stores its route in `points` (corners for elbows, a
smooth trace for curves) with a matching frame, so hit tests, marquee selection,
bounds and older readers see the real shape.

## Ends

Start and end heads are set separately: None, Line Arrow (the original open V),
Solid Arrow, Triangle (hollow), Diamond, Circle, Bar, and the crow's-foot set
One, Many, Exactly One, Zero or One, One or More and Zero or More. Heads grow with
the line (the original V is `10 + 2 × width` long) and filled heads trim the line
so dashes never poke through. Swap Ends flips them.

## Labels

Double-click a connector, press Return with it selected, or use Add a label in
the selection toolbar to type a label. Labels keep bold and strikethrough only,
Return adds rows, and the text is centred on the path. A label sits at
`labelPosition` along the route (half-way by default; double-clicking an empty
connector puts it where you clicked) and can be dragged along the path when the
line is long enough to give it room. The line hides behind a plain label; Label
Background fills a rounded pill in the connector's colour with white or dark
text, whichever reads better.

## Styles and memory

The selection toolbar offers the connector type, both heads (with Swap Ends),
and a line menu with Thin, Medium or Thick (1.5, 3 or 6 points), solid, dashed or
dotted, and Label Background; the shared colour control colours the line, its
heads and the label pill. The context menu's Connector submenu has Edit Label,
the type, both heads, Swap Ends and Reset Path, next to the shared colour and
line items. Each change is one Undo step. New connectors on an Easel take the
last heads and type used there, plus the colour, weight, dash and label
background remembered by the shared style memory, until Parc quits.

## Quick create

A single selected, unlocked sticky or shape shows a dot just outside each side;
hovering one turns it into a plus. Clicking makes the next object of the same
kind, size and style 40 points away in that direction and starts its text.
Shapes always get a connector from the source; stickies don't. Clicking the same
side again stacks the new object below or above the last one instead of
overlapping anything. Dragging a dot places the new object wherever it's dropped,
with a connector for stickies and shapes alike. Command-Return does the same as
clicking the right-hand dot, also while typing in the sticky or shape. The 40-point
gap is the same everywhere so rows and stacks line up.

## Keeping things together

`EaselDependents` runs after every canvas change: sections carry their
contents, stuck-on objects follow their targets, then connectors reroute to
whatever moved. Drag previews run the same pipeline, so connectors follow live;
a connector dragged together with both of its objects just slides along without
rerouting, and one drag reuses a single lookup of the board.
`EaselDependents.removing` takes everything stuck to the removed objects (and a
deleted section's contents unless ⌘Delete keeps them) and frees connectors that
pointed at them.

## Export

HTML and SVG export draw each connector from the same route, heads and label
geometry, with dashes, label pills and label text; PDF, PNG and Copy as Image
reuse the canvas drawing.

## Checks

`scripts/test-notes-editor.sh EaselConnectorRouting` runs the windowless suite:
magnets on outlines and rotated objects, pinned points, snapping, all three
routes (including same-side loops, objects facing away and overlapping objects),
manual bends, segment dragging, every head, labels, hit bands at every zoom,
path data, settling and the dependents pipeline.
