# Easel code blocks

Code blocks put a snippet on the board as its own object: a card in the Notes
code style with the language named in its header and the code below in Space
Mono, highlighted by the same lexer and colours as Notes' code blocks, so the
39 Notes languages plus Plain Text read the same in both places, in light and
dark.

## Making one

A new code block starts with four empty lines in the language you used last,
and in TypeScript until you pick another. The code block tool places one with
`placeCodeBlock(in:)`: centred on a click, or as wide as a drag (at least 160
points); `insertCodeBlock(at:)` drops one in the middle of the view (or at a
point) for an insert menu. Either way the block is selected and you are typing
in it straight away, and adding it is one Undo step. The last language lives in the user defaults, so it carries over
between Easels and launches.

⌘Return while typing in a block adds an empty block of the same width and
language just below it, skipping past anything already there, and starts
editing it (`insertCodeBlockBelow(_:)`, which the canvas's shared ⌘Return
quick-create calls for a selected block). Quick-created code blocks get no
connector, unlike shapes; FigJam doesn't document one either, and a chain of
snippets reads fine without arrows.

## Editing

Double-click a block, press Return with it selected, or use the VoiceOver Edit
code action to type in it. Editing is a plain-text editor laid exactly over the
card, so text never jumps between the drawn and the live block:

- Tab indents (a whole selection of lines indents together), Shift-Tab
  outdents, and Delete removes a whole indent step.
- Return starts a new line at the same indentation, one level deeper after an
  opening bracket or colon, and splits a bracket pair onto its own lines.
- Typing a closing bracket on an indented blank line steps it back out.
- Esc stops editing and leaves the block selected; a second Esc deselects.
- Typed markdown, smart quotes, dashes, spelling correction and link detection
  never touch code.

Indent width follows the Notes rules for the language (four spaces for Python,
Swift, Go and friends, two elsewhere, tabs for Makefiles, and whatever the code
already uses). Native Undo steps through the edits while typing; afterwards the
whole edit is one Easel Undo step, like text.

## Size

Blocks resize by width only. The side handles and corners change the width and
the height always follows the number of lines, including long lines that wrap at
the card's edge; the top and bottom handles are hidden. A block can't be narrower
than 160 points. In a group transform code blocks keep their place in the group
and still take their height from their lines.

## Language and copy

The header always names the language. With code blocks selected, the floating
toolbar leads with a language menu listing every language, the current one
checked (Mixed when the selection disagrees); choosing one relabels every
selected unlocked block in one Undo step (`setCodeLanguage(_:for:)`). A selected
or edited block also shows Copy in its header's top-right corner, which puts the
code on the clipboard with trailing blank lines trimmed and briefly says
Copied!. VoiceOver reads the block as "Code block, TypeScript" and offers Edit
code, Copy code and Change language actions. Locked blocks can be copied but not
edited or relabelled.

⌘F finds text inside code blocks too, lighting up each match in the code, and
Replace rewrites the code and re-measures the block so its height still follows
its lines.

Connectors attach to a code block's outline like any other object. Blocks have
no line numbers or theme switch: FigJam doesn't document either, and the Notes
colours already read well on light and dark paper.

## Export

PDF, PNG and Copy as Image draw the card through the canvas drawing switch.
HTML exports draw it as SVG: the card, its language label and every highlighted
run as positioned text, with the card and syntax colours as CSS variables for
both light and dark, so the export follows the reader's appearance. Run
positions come from the same text layout the canvas uses, so wrapping matches.

## Saved format

A code block is an object of kind `code` with its code in `text` and an optional
`language` holding the Notes language id (`typescript`, `python`, …). No
language means Plain Text. A language Parc doesn't know yet still opens and
shows as plain text with its saved name. Validation refuses a language on any
other kind, a malformed one (lower-case letters, digits and hyphens, at most 32)
and rich text on a code block, so a damaged file is rejected whole. The frame's
height is the header, one 22-point line per visual line and the bottom padding.

## Code

- `Sources/ParcCore/EaselCodeBlock.swift`: defaults, language rules, sizing,
  placement, the width-only settle and the SVG card.
- `Sources/ParcApp/EaselCanvasCodeBlockViews.swift`: style, text layout and
  export runs, the editor and the header bar.
- `Sources/ParcApp/EaselCanvasView+CodeBlocks.swift`: drawing, creation,
  editing, language, copy and resize on the canvas.
- `tests/EaselCodeBlockTests.swift`: windowless model, validation, geometry and
  SVG checks (`bash scripts/test-easels.sh` runs it with the other Easel suites).
