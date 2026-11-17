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

The store commits them through the existing validated transactions:
`SplitDropTarget.stack(_:after:)` for drops and `SplitPaneInsertion(paneID:stackingAfter:state:)`
with `insertSplitPane` for a new pane in a stack; `moveSplitPane` and
`moveSplitPaneWithinStack`; `flipSplitOrientation` and `setSplitLayout`; and
`resizeSplit(expected:resized:)` for Expand, Make All Equal and either kind of
divider, which accepts only a change of weights.

## Checks

`tests/SplitStacksTests.swift` (in `scripts/test.sh`) is windowless. It pins the
flat bytes against the previous format, round-trips stacked splits, reads them
as an older build would, loads corrupt stacks flat, and covers every edit above
through the model and the store, including reopen, Undo, copies, Favorites,
window projections, drops and Arc import. The existing split suites listed in
[split groups](split-groups.md#source-and-validation) cover flat splits unchanged.
