# Easel block equations

A Block equation is an Easel object that holds TeX and shows it typeset. It uses
the Notes math code itself: `NoteMathRenderer` typesets it (macros, `\ce`
chemistry and the rest behave as in a note), and `NoteEquationEditorView` is the
editor, in a floating panel under the object. Numbering, `\label`, `\eqref` and
`\ref` are page-level features of notes; on an Easel each equation stands alone.

## Inserting and editing

Code ▾ in the toolbar, the ⌘/ quick actions and the empty-object path
(`placeEmptyObject(.equation)`) place an empty equation at the middle of the
visible area, selected, with its TeX editor already open. Double-clicking an
equation, or pressing Return while it is selected, reopens the editor. Typing
retypesets live and keeps the equation's chosen size and centre. Escape, ⌘Return,
Done or a click anywhere else closes the editor; the placement and every edit
since belong to one Undo step. An equation left empty is removed, like empty
text. The editor's own ⌘Z undoes typing inside the field.

A typo shows the way a note shows one: the panel underlines the spot and says what
is wrong, and the object shows a warning with the TeX until it is fixed. While a
typo is on screen the frame keeps its last size.

## Size, ink and turns

The frame is the typeset size plus 14 points of padding, saved as the object's
frame. Resizing scales the equation and always keeps its shape, at any zoom,
because it is drawn as vectors in `drawObject`. Retyping refits the frame around
the same centre at the same scale. Ink is the object's colour: Automatic follows
the Easel's light or dark ink, and the selection toolbar's colour control sets a
palette ink. Block equations can be turned but not mirrored, grouped, locked,
placed in sections and sent to pages like any object. They cannot hold a link.

## Selection toolbar, menus and clipboard

The selection toolbar has colour and the ••• menu with Edit TeX and Copy TeX; the
context menu has the same two rows. Copying the object writes the TeX as plain
text next to the private object data and the image. Pasting that TeX as text
makes ordinary text.

## Accessibility

VoiceOver reads what Notes reads (`NoteEquationSpeech`): "Equation: the TeX",
"Equation that won't typeset: the TeX. the problem" or "Empty equation". Activate
is Edit TeX, and Copy TeX is an action.

## Exports

PDF, PNG and Copy as Image draw the same vectors. HTML and SVG exports write the
glyph outlines as filled paths (`EaselVectorEquation`), grouped by colour, scaled
with the frame and following the page's ink in light and dark. A typo exports its
TeX as muted monospaced text; an empty equation exports nothing.

## Saved format

An equation keeps its TeX in `text`, its ink in `color` and its place in `frame`.
It never carries an image, rich text, a link or a poster.
