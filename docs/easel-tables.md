# Easel tables

Tables are whiteboard grids that live on the Easel canvas next to stickies,
shapes and text. They borrow the Notes table look and keyboard habits, scaled
to a canvas you can zoom, and save inside the Easel file like every other
object. This guide owns how tables behave, how they save and the decisions
behind them; [Easels](easels.md) owns the canvas around them.

## Making a table

Press Shift-T (or pick Table in the toolbar), then drag on the canvas: a ghost
grid follows the pointer and a small "4 × 3" label shows the columns and rows
you'll get, up to 12 by 24 while dragging. A plain click makes a 3 × 3 table
centred on the click. The new table arrives with its first cell selected, so
typing fills it straight away. Like other placed objects, the tool goes back to
Select afterwards.

Pasting spreadsheet cells also makes a table; see [Data in and out](#data-in-and-out).

## Selecting and editing

- The first click selects the table as an object: drag it, resize it, delete it.
- A click on a cell of the selected table selects that cell. Drag across cells,
  or Shift-click or Command-click another cell, to select a block. Selections
  always grow to cover whole merged cells.
- A second click on the selected cell, a double-click, Return or just typing
  starts editing. Typing replaces the cell's text, the way spreadsheets work;
  Return and clicks keep it and put the caret where you'd expect.
- While editing, **Return makes a new line inside the cell**, matching
  whiteboard tables, and **Command-Return leaves the cell** with it selected.
- Tab and Shift-Tab move to the next or previous cell, selecting its text so
  you can type over it. Tab in the last cell adds a row. Inside a bulleted or
  numbered list, Tab indents the list instead.
- With cells selected, the arrow keys move the selection, Shift-arrows grow it,
  Delete clears the text (cell colours stay) and Escape goes back to the whole
  table; a second Escape deselects.
- More keys with cells selected: Option-Return adds a row below and
  Option-Shift-Return a column to the right; Option-arrows move the selected
  rows or columns; Option-[ and Option-] make the selected columns narrower or
  wider (add Shift for rows); Option-Space selects whole rows and
  Option-Shift-Space whole columns.

Cells use the full Easel text editor: bold, italic, underline, strikethrough,
links (Command-K), lists, headings, typed Markdown and inline images all work
inside a cell, with the same undo. Each cell edit is one undo step, as with
text objects. Without editing, Bold, Italic, Underline and Strikethrough in the
Format menu (Command-B, Command-I, Command-U) apply to every selected cell, or
the whole table when no cells are selected, and Bigger and Smaller step the
text size the same way.

A locked table can't be edited until it's unlocked, and its grips and bars
stay hidden.

## Rows and columns

Hovering a selected table shows its controls, drawn from the Notes table:

- `+` bars along the right and bottom edges add a column or a row at the end.
- `+` markers appear on the top edge between columns and on the left edge
  between rows; clicking one inserts a column or row right there.
- Grips sit on the top edge over the hovered column and on the left edge beside
  the hovered row. Click a grip to select the whole column or row,
  Shift-click another grip to extend, and drag a grip to move the selected
  columns or rows; an accent line shows where they'll land. Moves never split a
  merged cell: a drop inside one snaps to the nearest spot outside it, and
  Option-arrows hop over the whole merged block, as in Numbers. Duplicating
  works on whole merged blocks only.
- Drag a border between two columns or rows to resize it. Columns stop at 48
  points and rows never get shorter than their text. Borders hidden inside a
  merged cell can't be grabbed.
- Dragging the table's corners, or its right or bottom edge, resizes the whole
  grid proportionally with the same minimums; text never scales. The top and
  left edges belong to the grips and `+` markers.

Rows grow as you type. A row that was hugging its text shrinks back when you
delete some; a row you made taller by hand keeps its height.

Right-clicking a cell outside the current selection selects that cell first,
the way spreadsheets do. The context menu on a selected table offers Insert
Row Above and Below, Insert Column Left and Right, Duplicate Row or Column
(with whole rows or columns selected; Command-D does the same), Merge Cells
or Unmerge Cells, Clear Contents, Color, Delete Row or Column, Export Table as
CSV… and Convert to Stickies. New rows and columns copy a colour only when
every cell in that column or row already shares it, as in Notes.

Tables hold up to 100 columns, 100 rows and 10,000 cells in all; the add
controls beep once a table is full.

## Merging and colour

Merge Cells joins the selected block into one cell. **Every non-empty cell's
text is kept**, joined in reading order on separate lines, so a merge never
throws words away; the merged cell keeps the first cell's colour. Unmerge
Cells splits the block again and leaves the joined text in the first cell.

Color applies the Notes fills (Default, White or Black, then Gray through Red)
to the selected cells, or to every cell when only the table is selected. Fills
use the Easel palette, so a colour picked on light paper switches to its dark
variant on dark paper and back.

## Data in and out

- **Paste spreadsheet cells** from Numbers, Excel or Google Sheets onto the
  canvas to make a table. Parc reads the HTML table those apps put on the
  clipboard (keeping merged cells) when their plain text is tab-separated, so
  mail and web pages laid out with tables still paste as text. Otherwise it
  reads tab-separated text where every line has the same number of cells, then
  comma-separated text. Dropping or pasting a single `.csv` or `.tsv` file works
  too. A pasted table keeps the first 500 cells and 100 columns, columns get
  widths that fit their text, and a "Kept what fits" toast says when anything
  was left behind.
- **Paste into a table** with a cell selected and the cells fill from there,
  growing the table up to its limits (with the same toast if some cells don't
  fit). A single value fills every selected cell. Plain text and Easel text
  paste into the selected cell with their formatting.
- **Copy** with cells selected (or just the table) puts the block on the
  clipboard as an Easel table, an HTML table and tab-separated text, so it
  pastes as a table in another Easel and as cells in spreadsheets.
- **Export Table as CSV…** saves the selected block, or the whole table, as a
  UTF-8 CSV file named after the Easel, then shows the usual "Exported" toast.
- **Convert to Stickies** swaps the table for one sticky per filled cell, laid
  out in the table's rows and columns: each sticky is the usual square, grows
  taller for long text, and each row clears the tallest sticky above it. Cell
  colours carry over to the matching sticky colours, and uncoloured cells get
  the default sticky paper. Undo brings the table back.

Text that merely contains a tab, multi-line prose and indented code stay text.
Capture's image editor never turns a paste into a table. Find and replace
doesn't look inside table cells yet.

## Look

A table is a Notes-style card: the panel fill with a hairline outline, six-point
corners and hairline cell borders, readable on light and dark paper. Cell text
sits ten points in from the left and is top aligned, using the table's text
style (Clean body by default) and the automatic ink. Selected cells get the
accent outline, blocks of cells the Notes selection wash, and the grips, bars
and markers use the Notes table grip, hover and accent colours at screen size
whatever the zoom.

HTML exports draw tables as SVG with the same card, fills, grid lines and cell
text, following the viewer's light or dark preference. PDF, image export and
Copy as Image draw the canvas itself.

## Accessibility

VoiceOver reads a table as "Table" with its shape, for example "3 columns,
2 rows, 4 filled". Moving the cell selection announces the cell and its text.
Return or the Edit cells action starts editing the selected cell (the first
cell otherwise), and the context menu carries every table command, so nothing
needs the pointer.

## Saved format

A table is an object of kind `table` with an optional `table` field, left out
of every other object, so Easels saved before tables open unchanged:

- `columnWidths` and `rowHeights` in points; the object's frame matches their
  sums after every edit, and a frame stretched by another tool scales the grid
  to fit when shown.
- `cells`, row by row, each with optional `text`, `richText` (the same rich text
  format as text objects) and `fill` (`#RRGGBB`). Empty fields are left out.
- `merges`, each a top-left cell plus row and column spans; left out when there
  are none.

Validation refuses ragged grids, more than 100 rows or columns or 10,000
cells, cells over 64 KB of text, more than 1 MB of text per table, overlapping
or out-of-range merges, text hidden under a merge, bad fills, a grid on any
other kind of object and rich text on the table object itself.

The model and its operations live in `EaselTable.swift` (kept free of other
Easel code so lean test builds can compile it with `EaselStore.swift`),
geometry, sticky conversion and SVG in `EaselTableLayout.swift`, and parsing and
CSV in `EaselTableData.swift`, all in ParcCore. Drawing, editing and commands
live in `EaselCanvasView+Tables.swift`; the toast and the SVG text runs live in
`EaselTableExport.swift`, outside the canvas test bundles.

## Checks

`bash scripts/test-notes-editor.sh EaselTableTests` runs the windowless model
suite: limits, saving, validation, row and column edits, moves, merges,
navigation, pasting, sizing, layout, parsing CSV, TSV and HTML, CSV and HTML
export, SVG output and sticky conversion.
