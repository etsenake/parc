# Easel text

How text sizes and aligns on an Easel. The editing contract (families and
sizes, rich text, clipboard, typed markdown and native Undo) lives in
[Easels](easels.md#object-wide-text-styles); `EaselTextSizing` in ParcCore owns
the rules below and their windowless tests.

## Point text and area text

A click with the text tool, a double-click on empty canvas and Add text make
**point text**: an auto-width box that widens as you type and wraps only at your
own line breaks until it reaches a comfortable limit of 36 ems of the object's
base size (at least 560 and at most 4,000 points), where it starts wrapping. Its
height always hugs the words. Left-aligned point text grows to the right,
centred text grows from its middle and right-aligned text keeps its right edge.
The box follows typing live, including while an input method is composing.

A drag with the text tool makes **area text** with the dragged width; it wraps
and grows taller as you type. Every text object saved before point text existed
opens as area text with its width and height unchanged, and pasted or dropped
text arrives as area text.

A selected text object shows a width handle in the middle of its left and right
sides, even when it is a single short line. Dragging one sets a fixed width and
turns point text into area text; the text re-wraps and the box hugs its height
while you drag. Double-clicking a width handle returns the text to auto width
in one Undo step. Text has no top or bottom handles, because its height follows
the words. Mixed selections keep every handle and resize as before.

## Alignment

Text, shapes and stickies align their whole text left, centre or right. Shapes
start centred; text and stickies start on the left. There is no justify. While
editing, Format → Text → Align Left, Center and Right change the whole object
too, so one alignment always covers every paragraph.

The alignment is stored once on the object's text style (`alignment`) and never
in its rich-text runs: the editor shows it on every paragraph and strips it
again when it saves, and copying text out of an aligned object leaves the
alignment behind. Text saved without an alignment keeps whatever paragraph
alignment its runs already carried, such as centred lines pasted from another
app, so older Easels look the same. Changing the alignment is one Undo step; while
editing it joins the editor's own Undo history like the text fill does.
