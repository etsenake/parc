# Mind maps on Easels

A mind map is a tree of ordinary Easel objects: text, shapes or stickies as
nodes, joined by curved connectors that Parc lays out for you. Every node stays
the object it is, so it takes the same text styles, colours, links, stamps and
export as anything else on the board. This guide sits beside the
[Easel editing contract](easels.md), [connectors](easel-connectors.md) and the
[tools](easel-tools.md).

## Starting a map

- **Shapes menu.** The toolbar's shapes menu ends with **Mind map**.
- **Quick actions.** ⌘/ lists **Mind map** under Add.
- **Canvas menu.** Right-click empty canvas for **Add Mind Map Here**, which
  centres the root on the click.
- **From text.** Right-click a text object (or use its VoiceOver actions) for
  **Make Mind Map**. The text becomes the root and gets two children.

A new map is a root ("Big idea", heading size) with two children ("A thought"
and "Another thought"), all point text that hugs its words. It arrives as one
undo step with the root's text selected, so typing replaces it. Only text starts
a map; a shape or sticky joins one as a node. Mind maps aren't offered in the
capture editor's fixed canvas.

## Growing it

With a node selected or being edited:

| Keys | What happens |
| --- | --- |
| ⌘Return | Adds a child and starts editing it |
| ⇧⌘Return | Adds a sibling right below the node (on the root it adds a child) |
| Tab | Moves the node under the sibling above it |
| ⇧Tab | Moves the node up a level, right after its old parent |
| Delete | Removes the node with everything under it |

⌘Return and ⇧⌘Return go through the canvas's shared chord path
([tools](easel-tools.md)). On a mind-map node they win over quick create; on
any other sticky or shape ⌘Return still quick-creates. Neither does anything
while an input method is still composing. Tab and ⇧Tab work while
editing a node too, and editing carries on in the moved node; Tab on the first
sibling, or ⇧Tab on a first-level node, beeps and changes nothing.

A new child copies its nearest sibling (or its parent when it's the first):
same kind, colour, text style, shape, fill and outline. Children of the root
come back to body size. It starts empty; letting go of an empty text node
removes it, just like new text elsewhere. Pressing ⌘Return or ⇧⌘Return on a
node you left empty puts the new node in its place.

**+ buttons.** A node under the pointer, or the selected node, shows the
quick-create dot on the side its children grow from (the root shows one on each
side), plus its collapse button. They stay while the pointer heads out to them.
Hover turns the dot into a plus; a click adds a child on that side and starts
editing, with no need to select the node first. Nodes that are mind-map nodes
show these instead of the quick-create dots.

**Dropping.** Drag a node and a drop indicator follows: a dashed curve to a
slot between siblings, or a ring around a node when the pointer is over it. Let
go to reorder or reparent there. Dragging any text, shape or sticky onto a node
attaches it as that node's last child, so an existing map's root brings its
whole map along. A node can't drop into its own subtree. Let go away from any
slot and the node glides back into the tree.

Each change is one undo step, named for what it did ("Add child", "Move topic
in", "Move topic", "Attach to mind map", "Collapse branch").

## Layout

Layout is pure ParcCore (`EaselMindMap`), tested in
`tests/ParcCoreTests/Easels/EaselMindMapTests.swift`. It's a tidy tree: children stack in a column
beside their parent, centred on it, in their current top-to-bottom order.

- The root's children sit 72 points out; deeper levels 48 points; siblings
  16 points apart. Each subtree reserves its full height, so nothing overlaps.
- Maps grow to the right. Adding on the root's left side (its left + button,
  or dropping on its left half) makes a two-sided map; left subtrees grow left.
  New root children go to the right until the left side has fewer.
- The root never moves for layout. Moving the root moves the whole map, while
  you drag too; a map pushed past the canvas's top or left edge shifts back in.
- Layout runs as part of the commit pipeline (`EaselDependents.settle`), so a
  map re-lays itself after any structural change, a text edit that changes a
  node's size, a resize or a style change. Drag previews skip it so a node can
  wander until you let go.

## Branches

Branches are curved connectors with no arrowheads that leave the parent's side
and arrive at the child's facing side. Each first-level branch steps to the
next Notes colour (orange, yellow, green, blue, purple, pink, red, brown, gray)
not already used under the root, and children inherit their branch's colour,
width and dash. Deeper branches are 2 points wide. Restyle a branch with the
connector controls and its future children follow the new style.

Branches belong to the map: Parc adds one for each child and removes those
whose child has gone. Deleting a branch by itself splits the map, turning its
child into the root of a map of its own that keeps its children.

## Collapsing

**Collapse Branch** (canvas menu, VoiceOver action, or the small minus under a
selected node's + button) hides everything under a node. A collapsed node shows
a count chip on its growing side with the number of hidden nodes; click it, or
choose **Expand Branch**, to show them again. Adding a child to a collapsed
node expands it. Hidden nodes and their branches are left out of the canvas,
hit testing, find, the marquee and every export, through the same hidden set
that collapsed sections use (`EaselBoardObjects.hiddenIDs`). The root can't
collapse.

## Copies, deletes and export

- Duplicate, copy and paste keep links inside the copied set, so a copied map
  is its own map. A copied node whose parent wasn't copied becomes the root of
  its copied children, and a lone copied leaf becomes a plain object.
- Delete, cut and the eraser remove a node's subtree and branches with it, in
  the same step.
- PNG, PDF and Copy as Image draw nodes and branches as the objects they are.
  SVG and HTML export them through the existing text, shape, sticky and
  connector cases. Collapsed subtrees stay out of every export.

## Accessibility

Each node's VoiceOver actions include Add child, Add sibling, Move in, Move out
and Collapse branch or Expand branch where they apply; plain text offers Make
mind map. The + buttons, minus and count chip show the pointing hand. Every
command posts a layout change so VoiceOver follows the new node.

## Saved format

Nodes and branches carry an optional `mindMap` field, left out of the file when
unused:

- `parent`: the parent node's ID. A root has an empty link (`{}`).
- `side`: `left` on a first-level node placed left of the root; absent means
  right. Only first-level nodes save it.
- `collapsed`: `true` on a node whose subtree is hidden.

Branches save `mindMap` with only `parent`. The map's root is found by walking
parents, so there's no separate root ID to drift out of step. Validation
refuses a link on objects that can't be nodes (anything but text, shapes,
stickies and branch connectors), a node that is its own parent, a side on a
root and a branch without a parent or with `side` or `collapsed`. Parc repairs
the rest on the next change: links to missing parents and parent loops turn
into roots, and branches are rebuilt from the links.
