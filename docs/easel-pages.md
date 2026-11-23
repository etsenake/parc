# Easel pages

An Easel can hold several pages, each its own board with its own objects,
like tabs inside one document. A new Easel has one page and looks exactly as
Easels always have; pages appear only once someone adds a second one. This
guide covers the page switcher, how objects belong to pages, moving objects
between pages, links, find, exports and the saved format. It sits beside the
[Easel editing contract](easels.md) and follows the Notes look
([appearance](easel-appearance.md)) and motion rules ([motion](easel-motion.md)).

## The page switcher

The title row's chrome starts with the current page's name and a small
chevron. Clicking it, or pressing Space on it from the keyboard, opens the
page list in the Notes floating panel, with the same rows, highlight plate,
spring motion and pointing hand as the Notes page menu. Every page has a row
with a page icon, its name and how many objects it holds; the page you're on
shows a check mark and its name in the checked ink. Under the pages, after a
separator, sit **New Page** and **New Divider**.

- **Switching.** Clicking a page, or Return on the highlighted row, shows that
  page and closes the list.
- **Adding.** New Page adds a page right after the current one, named "Page"
  plus the next free number, switches to it and opens its name for typing.
- **Renaming.** Double-click a row, choose Rename from its menu or press
  ⇧Return. The name edits in place; Return or Tab keeps it, Escape puts the
  old name back. Names are one line of up to 100 characters; a blank name is
  refused with a beep.
- **Reordering.** Drag a row up or down; a line in the checked ink shows where
  it will land. ⌥↑ and ⌥↓ move the highlighted page, as do Move Up and Move
  Down in its menu.
- **Row menu.** Hovering a row shows a ••• button; it, a right-click or → opens
  Rename, Duplicate (⌘D), Copy Link to Page, Move Up, Move Down and Delete
  Page. Dividers offer Move Up, Move Down and Delete Divider.
- **Duplicating.** The copy lands right after the original as "<name> copy"
  (then "copy 2" and so on) and becomes the current page.
- **Deleting.** Delete Page… removes the page and everything on it. A page
  with objects asks first in the Parc dialog, saying how many objects go with
  it; an empty page or a divider goes straight away. ⌫ deletes the
  highlighted page from the keyboard. The last real page can't be deleted.

Up and down arrows move through the rows, Home and End jump to the ends and
Escape closes the list (or cancels a rename). VoiceOver reads the list as
"Pages", each page as a button with its name and "Current page" plus its
object count, and offers Rename, Duplicate, Copy Link to Page, Move Up, Move
Down and Delete as actions on each page. Closing the list returns the keyboard
to the canvas.

### Dividers

A page named "-" with nothing on it is a divider: a hairline in the list that
groups pages. New Divider adds one after the current page, and
renaming an empty page to "-" turns it into one. Dividers can be dragged,
moved and deleted but never opened, and nothing can be moved onto one; a page
that holds objects can't be renamed to "-". Every Easel keeps at least one
real page.

## Switching pages from the keyboard

Page Up and Page Down show the previous and next page while the canvas has the
keyboard and nothing is being edited, skipping dividers; at either end they
beep. They only act when the Easel has two or more real pages, so on a
one-page Easel they still scroll the canvas as before. Parc uses neither key
anywhere else, and they keep the Tab, arrow and command chords exactly as
they were. The switcher's tooltip names them.

Switching ends any text editing, clears the selection and leaves an entered
group, then VoiceOver announces the page's name. The new page slides 24 points
in from the direction of travel while the old one cross-fades away; boards with
live pages and Reduce Motion fade only.

## One page at a time

The canvas shows only the current page. Everything that reads the board reads
that page: drawing, hit testing, the marquee, Select All, alignment guides,
connectors and their magnets, sections and their contents, mind maps, quick
create, paste and duplicate, the selection toolbar, accessibility stops and
the empty-Easel key chips. A section therefore only holds objects on its own
page, and a collapsed section never hides anything elsewhere.

Each page remembers where you were looking (scroll position and zoom) for as
long as the Easel stays open. The first visit to a page fits its contents at
up to 100%, or starts at the top left when the page is empty.

Live webpages and captures on other pages stay attached to the Easel's window,
hidden and unable to take input. Returning to their page reuses them without a
reload, and Command-W can close the Easel from any page with the usual webpage
close confirmation when needed.

## Moving objects to another page

Right-click a selection and choose **Move to Page**, then a page or **New
Page**. The objects land on the destination page at the same spot, on top of
what's already there, and that page opens with them selected. Locked objects
stay put. What else travels:

- Stamps, highlights and washi stuck to a moved object follow it.
- A section brings everything inside it.
- A mind-map node brings its whole branch; the branch line to a parent left
  behind is cut and the moved node becomes its own map.
- A connector goes along when both of its ends move. When only one end moves,
  the connector stays and that end lets go, staying exactly where it was.
- Grouped objects that move without the rest of their group form a new group
  of their own; a group member left alone is ungrouped.

## Undo

Adding, renaming, reordering, duplicating and deleting pages, and Move to
Page, are each one undo step on the Easel's shared history. When an undo or
redo changes a page you're not looking at, the canvas switches to that page so
the change is visible; undoing a page you're on falls back to the nearest
real page.

## Links

**Copy Link to Page** in the switcher's row menu, and on the canvas's
right-click menu, copies the page's address: the Easel's `parc://easel/…`
address with `#page-` and the page's ID. Opening it opens the Easel on that
page, or says the page isn't there anymore. Links to single objects
([board features](easel-board-features.md)) open the page the object is on
before selecting it.

## Find

⌘F searches every page. Matches run page by page in the switcher's order,
then in reading order within each page, and the count covers the whole Easel.
Stepping to a match on another page switches to that page first. Highlights
only draw for the page on screen. Replace and Replace All work across every
page.

## Exports and previews

- **Image** (Export → Image…, ⇧⌘S, Copy as Image) is the current page.
- **PDF** has one PDF page per Easel page that holds objects, each sized to
  its own contents and listed by name in the PDF's outline. Live webpages
  show their live snapshot on the current page and their saved card elsewhere.
- **HTML** keeps the title, then one section per page with the page's name as
  a heading over its own drawing. An Easel without pages exports exactly as
  before.
- **Thumbnails, Easel blocks in notes and previews** show page one.

Dividers and empty pages are left out of exports, unless every page is empty.

## Sending captures and images

A capture or webpage image sent to an Easel lands below what's on the page that
Easel is showing in the window, or on page one when it isn't open there. The
Easel then opens on that page with the new card selected and scrolled into
view, the way an object link reveals its object.

## Saved format

The document gets an optional `pages` list, each entry an `id` and a `name`,
and each object an optional `page` ID. Both are left out of the file until a
second page exists, so older Easels and Easels with one page are unchanged.
An object without a `page` belongs to the first page, which keeps hand-edited
files working. So that this never shifts when pages are reordered or the
first page is deleted, adding the second page tags every existing object with
page one's ID, and every object made afterwards gets its page's ID. When
deletions leave a single page still called "Page 1", the fields are dropped
again.

Validation refuses a page list that's empty or longer than 100 pages,
repeated page IDs, blank or multi-line names over 100 characters, objects on a
page that doesn't exist and a list made only of dividers.

## Code

`EaselPages` in ParcCore owns the model: membership, views of one page,
merging a page's edits back, validation and the pure page operations (add,
rename, move, duplicate with fresh IDs and remapped connector, attachment,
group and mind-map references, delete with contents, and Move to Page). It
has its own suite, `tests/ParcCoreTests/Easels/EaselPagesTests.swift`.
`EaselPageSession` gives the canvas a session whose document is the current
page and whose edits merge back into the whole Easel, so every canvas feature
sees one page without knowing pages exist. `EaselCanvasView+Pages.swift`
holds the canvas commands, Move to Page, page links and the multi-page PDF,
and `EaselPageSwitcher.swift` the switcher button and list.
