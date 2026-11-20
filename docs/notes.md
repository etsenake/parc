# Local Notes

Notes are Markdown files on disk, opened in a native editor. Each Space's Profile
has a Notes folder, chosen in Settings like the Downloads location and
`~/Documents/Parc Notes` by default. New Note, New Note in Split View and the split
insertion bar create an `Untitled.md` file there and open it as a Today tab;
closing the tab archives it and keeps the file. File → Show Notes Folder reveals the
current Space's folder in Finder. Library → Easels & Notes lists that folder and
opens, renames or moves notes to the Trash; deleting a note first retires every
tab showing that file, in every Profile.

A note tab's address is its file's `file://` URL, and its title is the file name;
renaming a note moves every tab that shows it. The sidebar's URL pill shows the
file's name. A note's front-matter emoji icon is its tab icon in the sidebar,
Favorites, the folded Pinned peek, the tab switcher and the command bar; a local
image icon shows as a small rounded thumbnail, and anything else keeps the note
glyph. An open note's icon updates as it's edited, and other notes reread their
front matter off the main thread when their folder changes. Any regular Profile can open any
note file, so moving a tab to another Profile leaves the file where it is.
Parc appears in Finder's Open With list as an editor for Markdown and plain text.
Opening one from Finder or the Dock icon, dropping it on the sidebar, typing its
`file://` address, or following a link to one from a note or a page opens a note
tab instead of Chromium's file view; other file types still open in Chromium. A
page's link opens the note in the page's own tab, and Back returns to the page
just as it was ([note links](navigation.md#links-to-markdown-and-text-files)).
Dropping notes on the sidebar shows the insertion line and opens their new tabs
right there; a note that already has a tab just comes forward. A `#heading` or
block anchor in the address scrolls to that spot, and clicking a note reminder
opens its note the same way, always in a regular window.
Old `parc://note/<UUID>` tabs from the previous format show a short error, and the
old `Profiles/<id>/Notes/*.json` documents are not read or migrated.

Private windows deliberately offer no Notes, as explained in
[capture Library](capture-library.md#private-media-ownership): a Markdown file
opened while a private window is in front opens in a regular window. Cloud
sharing, collaboration and vendor services are excluded.

Embed blocks hold a live web page in the note's Profile, with its sign-ins, at a
height people drag to taste. The first click on a page already reaches it and
moves the keyboard into it; Escape or the check mark returns to the note.
Scrolling that starts over a page scrolls the page and carries on into the note
once the page hits its edge. The pages nap after four hours out of sight, follow the tab
between windows and ask before leaving, like an Easel's pages ([embedded pages](embedded-pages.md#live-embeds-in-notes)).

PDF blocks (`/pdf`, a dropped or pasted PDF file, a pasted `.pdf` link, or Turn
Into on a file row) read the PDF right in the note with PDFKit: pages scroll
inside the viewer at fit width, and scrolling hands over to the note at the first
or last page. On hover a page indicator with previous and next, zoom out, fit
width and zoom in floats at the bottom, and the corner toolbar offers alignment,
caption, Full Screen (also Space or ⌘↩ on the selected block), Download, View
Original (a Parc tab), Replace and Delete. The side bars resize it like an image,
the height follows the first page, links inside open in Parc, a password-locked
PDF asks for its password in place, and plain-text notes show it as a file row.

## How the editor is built

Notes are a native block editor in the spirit of Notion, drawn entirely in AppKit.
Every block is its own view, so blocks can be selected, dragged, coloured and
animated one at a time:

- `NotePageSession` (ParcCore) holds the page as a tree of `NoteBlock`s with
  inline `NoteText`, the selection and the undo history. Editing operations live
  in `NotePageEditing.swift`; every user action is one undo step that restores
  the selection, and typing coalesces per block.
- `NoteMarkdown` reads and writes the file; [the Notes file format](notes-format.md)
  describes the Markdown on disk. `NotePlainText` handles `.txt`.
- `NoteFileSession` owns one file for every editor showing it, in every window.
- `NotePageViewController` hosts `NotePageEditor`, which routes keys, the
  clipboard, drops and focus. Its canvas (`NotePageCanvasView`) lays blocks out,
  creates views only near the visible area, draws callout and colour boxes and
  animates structural changes.
- Overlays (the format bar, slash menu, block menu, pickers, find bar and link
  cards) are views inside the page, never separate windows, so the text keeps
  focus and input methods keep working.

## Blocks

Text, headings 1–6 (the menus offer 1–4), bulleted, numbered and to-do lists,
toggles and toggle headings, quotes, callouts with an emoji icon, dividers, code
with syntax highlighting for 39 languages, equations typeset natively from TeX
(including chemistry with `\ce`, numbering that runs through the whole note,
and `\label` with `\eqref` or `\ref` that link up in the editor and in HTML and
PDF exports), simple tables, images, video, audio, files, inline PDFs,
bookmarks with a cached preview card, embeds, links to other notes, columns (two
to five), a table of contents and a breadcrumb (`/bread`). The breadcrumb shows
where the note lives, from the Notes folder (or the home folder or disk for notes
elsewhere) down to the note's own icon and title, keeps up when the note moves
or is renamed, and each folder in it opens that folder in Easels & Notes, where
New Note creates notes right there. Inline text can be bold, italic, underlined,
struck, code, a link, coloured or highlighted in Notion's nine colours, and can
hold note mentions, dates and reminders, link mentions and inline equations.

Code blocks in Mermaid draw their diagram, as in Notion. The code block's toolbar
and the block menu's View switch between Code, Preview and Split. Preview is the
default, and clicking the drawing or moving the caret into it shows the code
above it until you leave. The diagram redraws 0.3 seconds after you stop typing.
A broken diagram keeps its last good drawing, shows Mermaid's message below it
and underlines the line it names. Parc runs the bundled Mermaid (see
[its provenance](../Resources/NoteMermaid/PROVENANCE.md)) in one windowless
WebKit view that never touches the network, gets a transparent vector PDF back
and caches it by source, appearance and page font. Diagrams use the note's ink,
Notion's palette and the page font, redraw when the appearance changes, and
scroll sideways when wider than the page. The file keeps a plain
```` ```mermaid ```` fence, so GitHub still draws it; HTML exports embed the SVG
for light and dark, and PDF exports print the drawing as vectors.

Hovering an image shows alignment, caption, replace, download, Quick Look and a
`•••` menu with Crop Image, Mask, Alt Text, Full Screen, View Original and Delete;
the block menu offers the first three too. Cropping shows the whole picture
behind a frame with corner and edge handles, thirds guides and aspect presets
(Shift keeps the ratio); Save or Return keeps it, as does clicking elsewhere,
and Escape cancels. Masks clip the picture to a rounded rectangle, circle,
squircle, arch, diamond, hexagon, star or heart, and the square shapes keep the
crop square. Neither touches the file itself, and full screen, HTML and PDF
exports show both. Alt text is what VoiceOver reads for the image and lives in
the Markdown `![alt](…)`; when an image has some, an ALT badge in its corner
shows it on hover.

Any text block can hold nested blocks, as in Notion: paragraphs, headings, list
items, to-dos, toggles, quotes and callouts, plus columns. Tab on a line after a
paragraph nests it there, Shift-Tab takes the lines after it along as its
children, and dragging a block right of a paragraph or heading drops it inside.
Plain headings always show their children; only toggles fold. Lists, quotes,
callouts and toggles save their nesting the usual Markdown way, and text blocks
save theirs in an [indent fence](notes-format.md#nested-blocks-under-text).
Plain-text notes stay flat, since a `.txt` file can't keep levels.

## Writing

Notion's Markdown shortcuts work as you type: `# ` through `###### `, `- `, `* `,
`1. `, `[] `, `> ` (toggle), `" ` (quote), ```` ``` ```` plus a language,
`---` (divider), `$$` (equation), and inline `**bold**`, `*italic*`,
`` `code` ``, `~strike~` or `~~strike~~`, `==highlight==` and `$math$`. Typing
`->`, `<-`, `<->`, `=>`, `>=`, `<=` or `--` gives →, ←, ↔, ⇒, ≥, ≤ or an em
dash, except in code and equations. One ⌘Z undoes a shortcut back to the
characters you typed. `/` opens the block menu,
`@` or `[[` mentions a note or a date, and `:` plus two letters suggests emoji.
`@Jan 3 → Jan 5`, `@Jan 3 - 5` or `@3-5pm` makes a range, and a month and day
without a year mean the nearest one. Clicking a date opens its picker: a
calendar that shades ranges, End date and Include time switches, a Format page
(relative, full, short or numeric dates and a 12 or 24 hour clock), a time zone
search and a Remind list (at the time, or 5 minutes to 2 days before; for a
whole day, 9 AM on the day or up to a week before). Dates say Today, Tomorrow
or Yesterday while they can and switch to the full date as days pass.
Reminders are blue, turn red on their day or once they've rung, and are local
notifications that follow the note through renames and moves and disappear
when it's trashed.

Custom emoji live with the notes folder. The emoji picker's `+` takes an image
(chosen, dropped or pasted, scaled to 280 px) and a name, and Save adds it and
uses it right away. Custom emoji get their own section in the picker, show up
first in `:` suggestions, complete when you type `:name:`, and work inline, as
page icons and as callout icons. The section's Edit button, a right-click or
Delete on a highlighted one opens it to rename or delete; a renamed emoji keeps
answering to its old name in notes that use it, and a deleted one turns back
into its `:name:` text. The icon picker's Upload tab can also add an upload to
the folder's emoji. Open notes, tab icons and menus update at once
([format](notes-format.md#custom-emoji)).

Return, Backspace, Delete and Tab follow Notion's rules: lists continue, an empty
item outdents and then becomes text, Backspace at the start of a block turns it
into text, then outdents, then merges. Notion's keyboard shortcuts apply inside a
note, including ⌥⌘0–9 to turn blocks into other types, ⌘D to duplicate, ⇧⌘↑/↓
to move, ⌘↩ to tick a to-do or open a toggle, ⌥⌘T for all toggles, ⇧⌘H to repeat
the last colour and ⌘/ for the block menu. While a note is focused, the Format
menu routes to the note and its shortcuts follow the note's keys.

## Selecting and formatting

Selecting text, with the pointer or the keyboard, floats a format bar above it:
Turn into, Link, bold, italic, underline, strikethrough, code, equation, colour
and mention. ⌘K opens the link editor, which also finds notes to link, and
hovering a link shows a card to open, copy, edit or remove it.

Selections cross blocks like one page. Dragging from the margin, or pressing
Escape, selects whole blocks, which can then be moved, coloured, duplicated,
deleted or copied together. With several sibling blocks selected, Turn into also
offers 2 to 5 columns and lays them out side by side in order. Hovering a block reveals `+` (add below, ⌥ for
above) and a grip; clicking the grip opens a searchable action menu (Delete,
Duplicate, Turn into, Colour, Copy link to block, Move to another note, and kind
specific items), and dragging it moves blocks anywhere, including beside a block
to make columns, while the page scrolls along.

Copying writes the note's own block format, Markdown, HTML and plain text, so a
paste keeps its structure in Parc, Mail, Pages or Google Docs. Pasting HTML from
web pages and documents makes real blocks, a lone URL offers mention, bookmark or
embed, and pasted or dropped images and files are copied into an `Attachments`
folder beside the note in the background, linking to the original until the copy
lands so a note never saves a broken reference.

Empty image blocks and the cover picker have an Unsplash tab: search, scroll the
grid and click a photo. Parc tells Unsplash about the download, copies the photo
into `Attachments` and credits the photographer with links to them and to
Unsplash, under the image (beside its caption) or on the cover when you hover it,
and in HTML and PDF exports. An image's Replace button offers Upload or Unsplash.
The tab appears only when Parc has an Unsplash access key: the
`NoteUnsplash.builtInAccessKey` constant, or the `NoteUnsplashAccessKey` user
default.

## The page

A note can have a cover (twelve built-in covers, an upload, a link or an
Unsplash photo, with reposition), an emoji or image icon, front-matter properties (text, number,
checkbox, date and tags), and one of four fonts: Nunito, EB Garamond, Space Mono
or ParcWide. The menu at the top right of a note offers Small Text, Full Width,
Lock Note, Copy as Markdown, Copy Link, export (Markdown, HTML and PDF), Show in
Finder, Note History and Move to Trash, with a word count and reading time.
Note History keeps versions through macOS file versions and restores one as a
single undo step, and File › Print prints the real page.

Under the title, "3 backlinks" counts the notes that link to or mention this
one: Markdown links to its file, page links and note mentions, from the Space's
Notes folder and every other folder Parc has opened notes from. Clicking it
opens a list of those notes with their icon and the sentence around the link;
picking one opens it at the linking section. The menu's Backlinks item shows the
list inline under the title instead (Expanded) or hides it (Off), saved in the
note's front matter. The index reads files off the main thread and follows
folder changes, so counts update as other notes are edited. Renaming or moving a
note, in Parc or in Finder (recognised by the file's identity), keeps its count
steady and rewrites the links to it in other notes, changing only the link in
files that aren't open.

⌘F finds and replaces across the whole note, including its title, captions and
table cells; inside a focused live embed it searches that page instead. `.txt`
notes show only the title and plain text, and Save a Markdown Copy writes a `.md`
twin beside them.

## Files and saving

Edits save automatically 0.6 seconds after you stop typing, and at least every
five seconds while you keep going, with an atomic, coordinated write off the main
thread that keeps the file's encoding, byte-order mark, line endings and final
newline (a character the old encoding can't hold switches the file to UTF-8). A
file you only read is never rewritten, and an edit you undo writes nothing, so
opening a README leaves it byte for byte the same. Binary files and files over
20 MB don't open as notes. Changing the title renames the file,
and a name that's taken shows an error without losing what you typed.

The file is watched for changes from other apps. Without local edits the note
reloads in place and the caret stays put; with them, autosave pauses and the page
offers Keep mine or Use the file's version, and taking the file's version can be
undone.
A deleted file keeps its text in memory until you close it or it saves again. A
failed save shows Retry and blocks closing, and quitting flushes every note.

## Look and motion

Notes sit on the Notes paper over the Space theme and take light or dark from the
Space. Ink is Parc's indigo, and selection, block washes and drop lines can take
the Space's colour. Menus are Parc's opaque cards with continuous corners; every
clickable control shows the pointing hand.

Menus and toolbars pop open (scale 0.95 to 1 with a short fade) and close
quickly, highlights glide on a short spring, blocks fade and rise when inserted,
slide when moved and settle when dropped, toggle triangles rotate, to-dos pop
when ticked, and the drag ghost lifts. Typing, caret movement and scrolling never
animate. Reduce Motion turns slides and scales into short fades. Notes make no
sounds and no haptics.

## Checks

`scripts/test-notes.sh` runs the note tab tests and `scripts/test-notes-editor.sh`,
which builds every windowless suite in `tests/NotesEditor/`: the model and
editing rules, the Markdown codec (including generated round-trip pages), files
and folders, HTML, syntax, math, emoji, the canvas layout, selection, menus and
clipboard. Pass a suite name to run one. Views are checked by compiling and by
offscreen renders, never in a window.
