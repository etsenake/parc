# Stacked split panes

A split's main row holds up to four slots in the group's orientation. Any slot
can hold a stack of two or more panes running the other way: in a side-by-side
split a column can be divided top and bottom, and in a top-and-bottom split a
row can be divided left and right. Stacks never nest further, and a split never
holds more than four panes in all.

[Split groups](split-groups.md) owns the flat split contracts. This guide owns
the stack model, its saved form and how every edit keeps stacks consistent.

## Shape and reading order

Reading order is slot order, then order within each slot's stack, so pane 1 is
always the top-left pane. A split's ordered pane list is kept in reading order,
which is why numbered and adjacent focus, the [tab switcher](tab-switcher.md),
sidebar rows and every membership check keep using that list unchanged.

A stack always has two or more panes, and a stacked split always has two or
more slots. An edit that leaves a stack of one turns that pane into an ordinary
slot. An edit that leaves one stacked slot on its own turns the split into a
flat split running the stack's way, which looks the same.

A split without a stack is a flat split and takes exactly the code paths it
took before stacks existed. Only a split that actually holds a stack takes the
stacked paths below.

## Starting a stack

Split This Pane adds a pane inside the focused pane's slot: below it in a
side-by-side split, or to its right in a top-and-bottom split. It is a View menu
item and a command search result, with Control–Shift–Backslash as its default
shortcut. Settings → Shortcuts can change it, and it shares Add Split View's Use
Both priority. No other Parc command and none of Chromium's own key tables use
that chord. Someone who already saved it on another command keeps it there, and
Split This Pane starts with no shortcut.

In a split, each pane's split-button menu also offers Add Above This Pane and
Add Below This Pane in a side-by-side split, or Add Left of This Pane and Add
Right of This Pane in a top-and-bottom split, after the main-row Add items.
Each opens the pending pane and command bar exactly like Add, inside the pane's
slot, and on a pane already in a stack it adds to that stack. The main-row Add
items keep adding a full-length pane, and a single page's menu is unchanged.

A pane in a stack also gets Move Up and Move Down, or Move Left and Move Right
in a top-and-bottom split, after the main-row Move items, which move its whole
slot. Every Move is disabled without a neighbour in its direction.

The stacked commands are unavailable on a single unsplit page, where Add Split
View and the pane menu's Add items start a split instead, at four panes, while
an Add is pending and wherever
[split commands are refused](split-navigation.md#interaction-and-ownership).

## Saving and older builds

A flat split saves exactly the bytes it always did. Its stacks entry is absent,
not empty.

A stacked split adds one `stacks` entry: how many consecutive reading-order
panes share each slot, the slot weights along the main row, and each slot's
weights within its stack (a lone pane's is just one). Its pane weights stay a
valid flat row: one positive weight per pane, summing to one, each pane taking
its slot's share times its share within the stack. The session `version` stays 1.

An older Parc reads a stacked split as that flat row, shows every pane side by
side and drops the stacking the next time it saves. It never refuses the file.

Reading never makes a session unreadable because of stacks. Stacks that don't
match the pane list are dropped and the split loads flat from its pane weights:
wrong counts, a stack of one, a single slot, a third level, missing, zero,
negative or malformed weights, or weights whose flat row wouldn't itself be
valid. Whole-session validation never sees them. Valid
stacks whose weights don't sum to one are normalised, and the flat row is
rebuilt from them.

## Edits

| Edit | What happens to stacks |
|---|---|
| Insert into a stack | The new pane goes before or after a given pane inside that pane's slot, making a stack when the slot had one pane. It takes an average share of the stack. Refused at four panes and on a single unsplit page. |
| Main-row insert | Add Left or Right (Top or Bottom in a top-and-bottom split) adds a full-length slot at the edge of the pane's whole slot, and a main-row drop at a slot edge does the same; one inside a stack, or one that would change a stacked split's orientation, is refused. Command bar Open in Split View and Favorites joining add the slot right after the focused pane's slot. Link opens in a split, Peek's Split button and Add all keep adding to the main row as before. |
| Remove | Separate, Close, cross-Space and cross-Profile moves, membership transfer and legacy Favorite cleanup take the pane out of its stack, which keeps the slot's share and collapses as above. One survivor dissolves the split as before. The focus successor is the pane now at the old reading-order index. |
| Replace | Keeps the slot, the stack position and the weights. |
| Move | Moving along the main row moves the pane's whole slot. Moving across reorders the pane within its stack and needs a stack neighbour. Panes in a flat split move exactly as before. |
| Convert | Flips the group orientation and keeps every stack, so stacks stay perpendicular and reading order doesn't change. |
| Expand | Gives the focused pane the largest share on both levels. |
| Make All Equal | Evens the slots, then each stack. |
| Divider pair | A main-row divider resizes only its two slots and a stack divider only its two panes; each pair keeps its combined share. A flat-row resize can't be applied to a stacked split. |
| Reopen and Undo | A whole group comes back in its full stacked shape. A single pane rejoins the slot that holds its old stack mates, re-forming the stack; otherwise it returns as its own slot beside the panes it sat next to. |
| Copy, duplicate, archive | Copies and archive records carry the stacks. Stacks count panes rather than naming them, so fresh pane identities need no remapping. |
| Window projection | A window showing only some panes keeps the stacks that survive and drops to flat when the subset breaks one. |
| Rebuild from a new pane list | Any edit that rebuilds a split from a new ordered list carries the old stacking over: consecutive panes from the same old slot stay stacked and new panes become their own slots. |

### Arc import

[Browser import](browser-import.md) keeps an Arc split's nested split as a stack
when it runs the other way, holds only tabs and the whole split has four panes
or fewer. A nested split running the same way joins the main row. A deeper nest
or a split over four panes flattens into one row, with any tabs past the fourth
imported as loose tabs, so no tab is dropped.

## Layout and dividers

A stacked split lays its slots out along the main row the way a flat split lays
out panes, then lays each stack out across its slot the same way: 10-point gaps,
the 220-point minimum on both axes, deficits taken from the other panes on the
same level, lengths rounded at the window's scale and edges aligned to whole
points. Panes in one stack share their slot's edges, and live window resizing
uses the same geometry. The main row and each stack are judged on their own
against the [tight-window rule](split-groups.md#divider-pair-sizing): a stack too
short for its panes' minimums shares its slot evenly while the main row keeps
its room, and the split never grows past the page area.

There is one divider between each pair of reading-order neighbours. A main-row
divider spans the whole split and a stack divider spans only its slot. Each
moves only its two neighbours on its own level, keeping their combined share,
and double-click evens that pair. Centre snapping and its haptic, the pane input
lock, the content-resize reason, the 0.2-second evening motion, grips, hover and
cursor work as in [split groups](split-groups.md#divider-pair-sizing), with each
divider's grip and cursor following its own direction. A side-by-side divider's
53-point top exclusion counts from the top of the panes it separates, so a
divider between two lower panes stays clear of their headers. A top-and-bottom
divider's 8-point end inset applies within its slot.

Widen and Narrow step the focused pane's whole slot along the main row with the
flat [step rules](split-groups.md#keyboard-and-voiceover-resizing), measured
against the main row. Make All Equal is offered until both levels are even.
Every divider edit and command commits one stacked edit through the store's
stacked resize; a flat row is never saved over a stacked split.

## VoiceOver and pictures

VoiceOver walks the panes in reading order with a splitter between neighbours,
numbered in that order. A stack splitter reports its position as a percentage
of its own slot, with limits that keep both of its panes at the minimum, steps
within the slot and names it: "Split View Divider 2, inside column 1" in a
side-by-side split, or "inside row 1" in a top-and-bottom one. Main-row
splitters keep the flat label. Announcements follow the flat rules, including
the 0.3-second settle and silence during a drag or live resize.

The Favorites tile and the [tab switcher](tab-switcher.md) thumbnail draw the
stacked shape: slots along the split's direction, each stack divided the other
way, at even sizes like their flat pictures. The sidebar row strip is unchanged.

## Pending panes and drops

A pending Add pane renders where its commit would put it: a pending pane in a
stack appears inside its slot at its stack position, and a pending main-row pane
beside a stack appears as its own full-length slot. An Add that would change a
stacked split's direction is unavailable and never opens a pending pane.

Tab, link and cross-window drops on a split use the
[pane-drop bands](split-groups.md#pane-drop-target-regions). A pane's main-row
edges add a full-length slot beside the pane's whole slot, so a pane inside a
stack offers the same slot insertion as its stack's outer edges. Its other two
edges insert the dropped page inside its slot, above or below it in a
side-by-side split and left or right of it in a top-and-bottom one: they start
a stack on a lone pane and grow an existing stack beside that pane. At four
panes those edges replace the pane instead, as the centre does.

The preview reserves room inside that one slot: the slot's panes make way for
the incoming pane at its stack position and share, its outline grows from a line
at the pane's edge, dividers hide, and the drag's placeholder card takes the
incoming pane's in-slot shape. The motion, haptics and proposal stability
match a main-row reservation.

## Model and store entry points

`BrowserSplitLayout.stacks` holds the shape; `slots`, `position(of:)`,
`paneID(slot:index:)`, `slotRange(_:)`, `slotBoundaries` and
`mainRowInsertionIndex(after:)` read it in reading order. `arrange(_:)` is the
one place a slot list becomes a canonical split, and `restack(from:)` carries an
old split's stacking onto a new pane list.

Pure edits return a new layout: `insertingIntoStack(_:besidePaneAt:after:)`,
`removePane(at:)`, `movingSlot(of:by:)`, `movingWithinStack(_:by:)`,
`transposed()`, `expanded(focusing:)`, `equalized()`, `resizingSlots(_:)`,
`resizingStack(_:factors:)` and `resizingDivider(_:inSlot:leadingShare:)`.

`SplitPaneOperation` names the menu's stacked rows: `stackBefore` and
`stackAfter` add, `stackPrevious` and `stackNext` move within a stack.
`isEnabled(index:count:layout:)` reads the pane's slot, so it agrees with the
store's slot and stack moves. `SplitPaneInsertion(paneID:operation:state:)`
hands the two adds to the stacking initialiser, and the window's split commands
carry them as `.add`, with `.moveInStack` for the moves.

The store commits them through the existing validated transactions:
`SplitDropTarget.stack(_:after:)` for drops and `SplitPaneInsertion(paneID:stackingAfter:state:)`
with `insertSplitPane` for a new pane in a stack; `moveSplitPane` and
`moveSplitPaneWithinStack`; `flipSplitOrientation` and `setSplitLayout`; and
`resizeSplit(expected:resized:)` for Expand, Make All Equal and either kind of
divider, which accepts only a change of weights.

`SplitStackGeometry` holds the windowless layout maths: flat and stacked pane
frames, the even sharing in a tight page area, divider rects and regions in
reading order, and splitter values and labels. `ParcSplitView.configure(orientation:factors:stacks:)` takes a
split's stacks, and the view commits a `SplitStackResize` through
`prepareStackedSplitResize`, which applies `BrowserSplitLayout.resized(by:)`.
`SplitPaneInsertion.previewLayout` gives the pending pane's shape from the same
transaction the store commits, so a new stacked insertion only has to create its
request.

`SplitDropGeometry.proposal` takes the split's slot sizes and proposes
`.stack(_:after:)` for a stacking edge, and `.insert` at a slot boundary for a
main-row edge. A drop reservation holding a stack target lays the split out with
`BrowserSplitStacks.reservingStack(besidePane:after:)`, reading a flat split as
`BrowserSplitStacks.flat(_:)`, and its `incomingPaneSize` follows the target.

## Checks

`tests/SplitStacksTests.swift` (in `scripts/test.sh`) is windowless. It pins the
flat bytes against the previous format, round-trips stacked splits, reads them
as an older build would, loads corrupt stacks flat, and covers every edit above
through the model and the store, including reopen, Undo, copies, Favorites,
window projections, drops and Arc import. `tests/SplitStackLayoutTests.swift`
(also windowless, in `scripts/test.sh`) covers the stacked frames, divider rects
and regions, tight page areas, splitter values and labels, the layout commands,
pending-pane previews and reserved drop shapes. `scripts/test-split-drop-geometry.sh`
pins every drop band, corner and four-pane fallback on flat and stacked splits,
and the original, external and cross-window drop suites commit stack drops. `tests/SplitStackCommandsTests.swift` (windowless, in
`scripts/test.sh`) checks command enabling against the store's moves, Split
This Pane's targets, previews and commits, and reading order after each.
`tests/SidebarRows/split_stack_commands_check.py` pins the View command, its
shortcut, the shared availability gate and the pane menu wiring, and
`SplitPaneMenuTests` asserts the stacked rows and their artwork. The divider,
snap and Favorites tile suites listed in
[split groups](split-groups.md#source-and-validation) also cover stacked
dividers and pictures, alongside flat splits unchanged.
