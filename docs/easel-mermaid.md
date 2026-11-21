# Mermaid diagrams on Easels

Paste Mermaid text onto an Easel and it becomes objects you can keep editing:
shapes with their labels inside, arrows connected to those shapes, and sections
for subgraphs. Flowcharts (`flowchart` or `graph`) and ER diagrams
(`erDiagram`) work. It's the same text a note's Mermaid code block draws
([Notes](notes.md)). A note draws a picture of the diagram; an Easel turns it
into real objects. This guide sits beside the
[Easel editing contract](easels.md) and the [board features](easel-board-features.md).

## Getting a diagram in

**Paste.** ⌘V, Edit → Paste or the canvas menu's Paste turns the clipboard's
plain text into a diagram when it reads as Mermaid. The text can be bare or
fenced in a ```` ```mermaid ```` block (a `~~~` fence or a fence with no
language works too). The diagram lands centred in the view, or from the top left
of the view when it's bigger than the view. It arrives as one undo step, "Add
Mermaid diagram", with every new object selected, and VoiceOver announces what
arrived. A diagram past the limits below shows "That's a big one…" in the
Easel's status line and adds nothing; it doesn't fall back to a wall of text.
Copied Easel objects still paste as themselves, and Paste as Plain Text always
pastes the source as text. Text with a Mermaid mistake, or that isn't Mermaid,
pastes exactly as it did before. Mermaid copied from a code editor that also
puts rich text on the clipboard still becomes a diagram. A selected table cell
takes pasted text as its own, Mermaid or not.

**Add Mermaid diagram.** The toolbar's Mermaid button and the ⌘/ quick actions
([tools](easel-tools.md)) open the "Add a Mermaid diagram" sheet: a Parc dialog
with a code field in the Notes code font. It starts filled in when the
clipboard already holds Mermaid. Under the field a line shows what you'll get
("Flowchart · 6 shapes, 7 arrows, 2 sections") or the first problem, with its
line number; it updates as you type, a moment after you stop on very long
sources. Add (⌘↩) is on only while the text reads as Mermaid; Cancel or Escape
closes the sheet. Return starts a new line and Tab indents four spaces. Smart
quotes, dashes and text replacement are off, so `-->` stays an arrow.

The capture editor's canvas takes neither: pastes there stay annotation text.

## What Parc reads

### Flowcharts

The header gives the direction: `TB` or `TD` (the default) runs down, `BT` up,
`LR` right and `RL` left. Statements end at a new line or `;`. `%%` comments,
`%%{init: …}%%` directives and `---` front matter are skipped.

| Mermaid | Easel object |
| --- | --- |
| `A`, `A[text]` | rectangle |
| `A(text)`, `A([text])` | rounded rectangle (the stadium too) |
| `A[[text]]` | predefined process |
| `A[(text)]` | cylinder |
| `A((text))` | circle, kept round |
| `A(((text)))` | circle with a thicker outline |
| `A>text]` | chevron |
| `A{text}` | diamond |
| `A{{text}}` | hexagon |
| `A[/text/]`, `A[\text\]` | right- and left-leaning parallelograms |
| `A[/text\]` | trapezoid |
| `A[\text/]` | trapezoid flipped upside down |
| `A(-text-)` | ellipse |
| `A@{ shape: …, label: … }` | the matching flowchart shape: `doc`, `docs`, `cyl`, `h-cyl`, `sl-rect`, `win-pane`, `notch-rect`, `tri`, `flip-tri`, `cross-circ`, `text` and their aliases; unknown names fall back to a rectangle |

| Link | Arrow |
| --- | --- |
| `-->` | arrow with the Easel's default head |
| `---` | line with no heads |
| `-.->`, `-.-` | dashed arrow or line |
| `==>`, `===` | thick (6 pt) arrow or line |
| `--o`, `--x`, `<-->`, `o--o`, `x--x` | circle heads, bar heads (Easels have no cross head), two-way arrows |
| `~~~` | no arrow; it only spaces the layout |

Extra dashes, dots or equals signs (`--->`, `-..->`) stretch a link across more
ranks, up to six. Labels come from `-->|text|` and `-- text -->` (dotted and thick forms
too). Chains (`A --> B --> C`) make one arrow per hop, and `&` links every pair
(`A & B --> C`). Quoted labels may hold brackets. Markdown strings in backticks
keep their line breaks and lose the emphasis marks, `<br>` starts a new line,
entity codes such as `#quot;` and `#9829;` are decoded, and Font Awesome icons
(`fa:fa-car`) are dropped. When a node is defined twice, the last definition
wins. Edge IDs (`e1@-->`) and their `e1@{ animate: true }` lines are accepted
and ignored.

Subgraphs become sections titled with the subgraph's title or ID. They nest,
honour their own `direction`, and arrows to a subgraph's ID end on its section.
A node belongs to the first subgraph that mentions it, even when it was first
written outside it, as in Mermaid. An unclosed subgraph closes at the end.

`classDef`, `class`, `:::`, `style` and `linkStyle` (by index or `default`)
carry fills, outline and arrow colours, outline widths and dash arrays. Each
colour snaps to the nearest Easel palette colour (white, grey and automatic ink
for greys), so a styled diagram still reads in light and dark. Text colour and
other CSS are ignored, as are `click`, `accTitle` and `accDescr`.

### ER diagrams

Entities become rectangles listing their attributes under the name in bold,
left aligned: `type name`, then any `PK`, `FK` or `UK` keys, then a quoted comment
after a middle dot. Attribute blocks may span lines or sit on one line, and
`p[Person]` labels an entity. Relationships take symbols (`||--o{`, `}|..|{`)
or words (`1 to zero or more`, `only one optionally to one or many`) and
become arrows with crow's-foot heads at both ends: exactly one, zero or one,
zero or more, or one or more. Identifying relationships (`--`, `to`) are solid
and non-identifying ones (`..`, `optionally to`) dashed. The text after the
colon labels the arrow. `direction` works here too.

### Refusals

Sequence, class, state, Gantt, pie, mind map and every other Mermaid type are
refused by name, and paste falls back to plain text. Diagram keywords are
case-sensitive, as in Mermaid, so a list that starts with "Graph" stays text.
Syntax mistakes name their line ("Line 3: the label for C is missing its
closing bracket."). A diagram may hold up to 500 shapes, 1,000 links, 200
subgraphs and 100 attributes per entity from up to 400 KB of text. Parsing stops
as soon as a limit is passed, so a giant paste is refused at once. Labels are
cut at 2,000 characters, and the Easel's own 10,000-object limit and its
million-point canvas still apply. Parc also accepts `A->B` as an arrow, which
Mermaid itself refuses.

## Layout

The layout is layered, like Mermaid's own:

- Ranks follow the direction, with a back link reversed only for placement.
- Rank by rank, nodes are ordered to cut crossings (barycentres plus
  neighbour swaps).
- Long links stay straight through the ranks they skip.
- Link labels get room of their own between ranks.

Each node is sized so its label, measured in the Easel body font (Clean, 15
pt), fits inside that shape's text area: diamonds and circles grow, rectangles
stay compact. Very large diagrams spend fewer passes on ordering, and only the
shortest of a pathological pile of long links reserve room through the ranks
they skip. Each subgraph is laid out on its own and placed as one block with
a title band, so a section holds only its own shapes and never covers another.
The canvas's section rules then treat those contents as the section's.

Arrows connect to their shapes or sections at both ends and use elbow routing
([connectors](easel-connectors.md)). Links that run with the flow, in the
direction of the subgraph they sit in, leave and enter along it: bottom to top
in a `TD` diagram, for example. Back links and same-rank links leave the sides
to the connector. A self link runs from the right side to the top. Each
arrow's elbow route is worked out before the diagram lands, so it arrives
already bent around its shapes. Shapes and arrows are ordinary Easel objects
from then on: move, restyle, retype or delete them like any other. The source
isn't kept, so there's no round trip back to Mermaid.

## Code and checks

`EaselMermaid` in `Sources/ParcCore/EaselMermaid.swift` parses and refuses.
`EaselMermaidLayoutEngine` and `EaselMermaid.drawing` in
`Sources/ParcCore/EaselMermaidLayout.swift` lay the diagram out and build the
Easel items. `EaselCanvasView+Mermaid.swift` places them on the canvas and holds
the paste hook, and `EaselMermaidSheet.swift` is the insert sheet.
The canvas reaches the sheet through `EaselCanvasView.mermaidSheetFactory`,
set at launch, so the canvas test bundles that compile every `EaselCanvas*`
file don't need the sheet. `bash scripts/test-notes-editor.sh EaselMermaid`
runs the windowless suite. It covers parsing, styles, refusals, hostile input
(each case must finish quickly), layout direction, spacing, sections, cycles,
the mapping, routing and validation of every produced Easel. The sheet and
canvas code are checked by compiling only.
