# Easel tools and navigation

An Easel works like a whiteboard: pick a tool, then click or drag on the
canvas. The toolbar under the title, single-letter keys, panning and zooming all
share one tool model, so a key, a toolbar click and a VoiceOver action always
reach the same place. The canvas's look lives in [appearance](easel-appearance.md),
editing and data safety in [Easels](easels.md), and pinch feedback in
[motion](easel-motion.md).

## The toolbar

The toolbar is a Notes format-bar card centred under the title. Its slots come
in this order, with a hairline between groups:

| Group | Slots |
| --- | --- |
| Navigation | Select, Hand |
| Objects | Sticky note, Shapes ▾, Connector ▾ (elbow, curved, straight), Text, Section, Table |
| Tools | Draw ▾ (marker, highlighter, washi tape, eraser), Stamp |
| Inserts | Add image, Add link, Add webpage, Code block, Add Mermaid diagram, Templates |
| View | Zoom percentage ▾ |

A slot whose tool isn't ready yet stays off the toolbar and its key does
nothing, so the bar never shows a button that can't do its job. Each tool
reports that through `EaselTool.isAvailable` (templates appear when a templates owner sets the toolbar's hook). Buttons use the Notes states:
secondary ink at rest, hover and pressed washes, and the checked fill for the
current tool or an open picker. Every button shows the pointing hand, and its
tooltip shows the name and key, such as “Sticky note S”.

Variant buttons (shapes, connectors, draw) carry a small chevron. A click picks
the variant used last; clicking the current tool again, or its chevron, opens
a Notes menu of variants with their keys. VoiceOver's Show Menu opens it too.
With Full Keyboard Access on, Tab reaches each button and Space presses it.
The toolbar scrolls sideways when the window is narrower than it. Undo, Redo
and Easel Options stay on the title row.

## Placing objects

While a sticky, shape or section tool is armed, a dashed ghost of the object
follows the pointer. A click drops the object at its default size centred on
the click, and a new sticky is ready for typing straight away. A drag sizes the
object instead: Shift keeps it square or circular and Option draws from the
centre. With Text, a click starts text that widens as you type and a drag sets
the width it wraps at; with Table, a drag picks rows and columns over a live
grid and a click drops a 3 × 3 table; a code block lands where you click,
ready to type. Stickies aren't drag-sized, so a sticky drag drops it where the
pointer is released. Dragging a button from the toolbar onto the canvas drops
that object there.

Connectors need a drag from start to end (a click alone draws nothing); Shift
snaps the line to 45° steps. Straight connectors save no routing, elbow and
curved ones save theirs. Ends are free for now: the canvas asks
`connectorEnd(near:excluding:)` for each end, which is where snapping to
shapes plugs in.

Return places the armed object at the centre of the view, so tools work from
the keyboard and VoiceOver as well as the pointer. Each placement is one Undo
step and selects the new object; new text starts editing straight away.

Stickies, shapes, text, sections, tables and code blocks go back to Select
after one placement (Parc's choice where FigJam's behaviour isn't documented).
The marker, highlighter, washi tape, eraser, connectors, stamps and the hand
stay armed until V, Escape or another tool. Escape first finishes text editing,
then cancels a drag in progress, then clears the selection, then leaves an
armed tool; in a note's Easel block the next Escape returns to the note.

## Keys

Single keys act only while the canvas or one of its objects has keyboard focus,
never while text is being edited, in a field or inside an embedded page, and
never with Command, Control or Option held. Parc's own shortcuts always need
one of those modifiers, so the two never collide. Letters follow the character
the layout types; on non-Latin layouts they fall back to the key's position.

| Key | Action | Key | Action |
| --- | --- | --- | --- |
| V | Select | H | Hand |
| Space (hold) | Temporary hand | S | Sticky note |
| R | Rectangle | O | Ellipse |
| X or ⇧L | Elbow connector | L | Straight connector |
| T | Text | ⇧S | Section |
| ⇧T | Table | ` | Code block |
| ] / [ | Bring to front / send to back | M | Marker |
| Return | Place the armed object | | |
| Arrows | Nudge, or pan with nothing selected | Escape | Leave the armed tool |
| ⇧1 | Zoom to fit | ⇧2 | Zoom to selection |
| ⇧0 or ⌘0 | Zoom to 100% | ⌘= / ⌘− | Zoom in / out |
| = or ⇧+ | Zoom in | − or ⇧− | Zoom out |

The map also holds ⇧M highlighter, W washi tape, ⇧⌫ eraser and E stamp
([stamps](easel-stamps.md)). ⇧H and ⇧V flip the
selection, and ⌥← / ⌥→ turn it ([rotate and flip](easel-rotation.md)).

The key map is one table in `EaselKeyCommands.bindings`; other features add
their command with a single line there. Command chords go through the canvas's
one `performKeyEquivalent(with:)` override and take effect only while the
canvas has focus, so ⌘=, ⌘− and ⌘0 zoom the Easel there and keep zooming web
pages everywhere else. ⇧1, ⇧2 and ⇧0 match the number keys by position, so
they work on layouts with symbols on that row; the zoom chords fall back to a
key's position only when it types a non-Latin character, so ⇧⌘? on German
layouts stays the Help search.

## Quick actions

⌘/ opens a search card under the toolbar, styled like the Notes slash menu.
Type what you want by name, such as sticky, ellipse, connector, pen or zoom,
and press Return or click it. Objects arm their tool, so the ghost follows the
pointer and a click (or Return) drops one; tools switch; Add image, link and
webpage open their usual pickers; view commands zoom. The last three you ran
from the card sit at the top under Recent. ⌘/ opens only while the canvas has
keyboard focus in an Easel tab; Parc has no other ⌘/ shortcut.

## Navigation

The hand tool and a held Space pan by dragging, with an open hand that closes
while dragging. Trackpad scrolling and the mouse wheel keep panning, Shift with
the wheel pans sideways, and the arrow keys pan by 48 points (240 with Shift)
when nothing is selected, whichever tool is armed.

Pinch zooms as before. ⌘ with the wheel zooms around the pointer; one wheel
event never more than doubles or halves the zoom. A trackpad ⌘-scroll zoom
stops when the fingers lift, like a pinch, and a scroll's glide keeps panning
even if ⌘ goes down before it ends. Zoom in and Zoom out step
through 25, 33, 50, 75, 100, 150, 200, 300 and 400% within the Easel's range
(33–400%; the capture editor also reaches below 25% by halving). Zoom to fit
shows every object and Zoom to selection the selected ones, each with a
48-point margin. The right-click menu offers Zoom to selection on objects and
Zoom to fit on the empty canvas.

The zoom button shows the current percentage and opens a Notes menu with a
field for a typed percentage, Zoom in, Zoom out, Zoom to fit, Zoom to selection
(dimmed with nothing selected) and 50%, 100% and 200%. Programmatic zoom
glides for a quarter second, eases out and is instant under Reduce Motion; a
pinch or click stops it. Zoom never saves into the document and plays no
haptics; the pinch's 100% pulse is unchanged.

A Recenter chip appears at the bottom of the canvas once nothing in the Easel
is anywhere near the view, and zooms back to fit everything (never past 100%).
An Easel that opens with content beyond the window starts zoomed to fit,
capped at 100%; smaller Easels open at 100% from the top left as before.

## Cursors

Select shows the arrow, the hand tool and Space the open and closed hands,
the marker, highlighter and washi tape a pen, the eraser a soft round disc
([drawing](easel-drawing.md#eraser)), and every other creation tool a crosshair. Resize and
endpoint cursors appear only with Select.

## Where it lives and how to check it

`Sources/ParcCore/EaselTool.swift` holds the tools, keys, placement geometry
and zoom maths; `EaselCanvasView+Tools.swift` the canvas gestures, panning,
zooming, ghost and cursors; `EaselToolPalette.swift` the toolbar and its menus;
`EaselQuickActions.swift` the ⌘/ card. Objects with their own insert code
(stickies, sections, shapes, text, tables, code blocks) plug into the
`ownerPlacement` switch, one line per tool, and everything else uses the
generic placement.
In a note's Easel block the keys, panning and zooming work the same, without a
toolbar. The capture editor keeps its own buttons and ignores tool letters, but
Space panning and the zoom keys work there too.

`scripts/test-notes-editor.sh EaselToolTests` checks every key, layout
fallbacks, tool behaviour, placement and connector geometry, zoom steps,
fitting, the wheel limits and ⌘-scroll glide routing without opening a window.
