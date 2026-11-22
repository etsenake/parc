# ParcNotes

ParcNotes is the Notes editor: the page view and its canvas, every kind of
block, selection, the format bar, slash and mention menus, find, media, math,
Mermaid and the web pages a note can embed. The document model, the file format
and the notes folder live in ParcCore; ParcNotes is the interface on top of
them. Easels are built on this editor in ParcEasels, which also draws the Easel
blocks that appear inside notes. In the
[app architecture](../../docs/app-architecture.md) it sits above ParcKit and
below every other feature library.

## Where to start

**The editor.** [NotePageViewController.swift](NotePageViewController.swift)
hosts one open note. [NotePageEditor.swift](NotePageEditor.swift) holds
`NotePageEditor`, which runs editing commands against the note's
`NotePageSession` from ParcCore (its blocks, undo and saving), and [NotePageCanvasView.swift](NotePageCanvasView.swift) lays the blocks
out, with measurement, layout and motion in the `NoteCanvas…` files. The page's
header, properties, backlinks and history are in
[NotePageHeaderView.swift](NotePageHeaderView.swift),
[NotePropertiesView.swift](NotePropertiesView.swift),
[NotePageBacklinks.swift](NotePageBacklinks.swift) and
[NotePageHistory.swift](NotePageHistory.swift).

**Blocks.** [NoteBlockView.swift](NoteBlockView.swift) is the base class of
every block view, and [NoteBlockViewFactory.swift](NoteBlockViewFactory.swift)
makes the right view for each block kind. Text is
[NoteTextBlockView.swift](NoteTextBlockView.swift) on
[NoteTextView.swift](NoteTextView.swift), with typing rules in
[NoteInputRules.swift](NoteInputRules.swift) and key handling in
[NoteKeyCommands.swift](NoteKeyCommands.swift). Other kinds have their own
`Note…BlockView.swift` file: code, table, columns, equation, media, PDF,
bookmark, button, synced and embed blocks among them.

**Selection and menus.** The `NoteSelection…` files track and draw the
selection and move it with the keyboard. The format bar is
[NoteFormatBar.swift](NoteFormatBar.swift) with its model and view;
[NoteSlashMenu.swift](NoteSlashMenu.swift),
[NoteMentionMenu.swift](NoteMentionMenu.swift),
[NoteBlockMenu.swift](NoteBlockMenu.swift) and
[NoteTurnIntoMenu.swift](NoteTurnIntoMenu.swift) are the menus.
[NoteFloatingPanel.swift](NoteFloatingPanel.swift) holds the floating panel and
`NoteMenuList`, the list other features reuse for their menus.
[NoteFindController.swift](NoteFindController.swift) is find and replace.

**Media, math and diagrams.** The `NoteMedia…` files import, crop, mask, zoom
and play images and video. [NoteMathRenderer.swift](NoteMathRenderer.swift) and
[NoteMathLayout.swift](NoteMathLayout.swift) draw equations, with editing in
the `NoteEquation…` files; [NoteMermaidRenderer.swift](NoteMermaidRenderer.swift)
draws Mermaid diagrams. Covers, emoji and custom emoji have their pickers in
[NoteCoverPicker.swift](NoteCoverPicker.swift),
[NoteEmojiPicker.swift](NoteEmojiPicker.swift) and
[NoteCustomEmojiEditor.swift](NoteCustomEmojiEditor.swift).

**Embedded web pages.** [EmbeddedPagePool.swift](EmbeddedPagePool.swift) owns
the live engine pages that embed and capture blocks show, and
[NoteEmbedPages.swift](NoteEmbedPages.swift) connects them to blocks;
[EmbeddedPageHeader.swift](EmbeddedPageHeader.swift) and
[EmbeddedPageAddressEditor.swift](EmbeddedPageAddressEditor.swift) are the
embed's header and address field. These files and the live-capture surfaces
are the only parts of ParcNotes that import ParcEngine.

**Look.** [NoteTheme.swift](NoteTheme.swift) holds the editor's colours, fonts
and motion settings.

## Imports and hooks

ParcNotes imports ParcCore for the document model and note files, ParcKit for
shared controls, tooltips and toasts, and ParcEngine for embedded pages. The
editor, its block views and `NoteMenuList` are `package` so ParcEasels and the
app can use them; `NoteBlockView`, `NoteCaptionedBlockView`, `NoteControlButton`
and the media views are `open` or `public` because ParcEasels and ParcLibrary
subclass or hold them.

ParcNotes declares these hooks for higher libraries to supply:

- `NoteBoardProviding`, with `NoteBoardHost` and `NoteBoardPages`, draws Easel
  blocks inside a note. ParcEasels implements it as `NoteEaselProvider`, and
  `AppDelegate` in Parc assigns it to `NoteBlockViewFactory.boards` at launch.
  Making an Easel block view with no provider is a programming error and stops
  with a precondition failure.
- `NoteWindowActions` is what the editor asks of its window, such as showing a
  document toast. ParcEasels extends it as `EaselWindowActions`, and Parc's
  `BrowserWindowController` conforms.
- `NotePageHostObserving` lets embed and media blocks hear when their page host
  changes; it stays inside ParcNotes.

## Tests

Tests live in [tests/ParcTests](../../tests/ParcTests/README.md), almost all in
the Notes folder, with some Easels and CommandBar suites that use the editor.
The model and file format are tested in
[tests/ParcCoreTests](../../tests/ParcCoreTests/README.md). Run one suite with
`swift test --filter <SuiteName>`, or everything with `swift test`. Build notes
over `IsolatedNoteFiles.make()` so a test never touches your real notes; see
the [testing guide](../../docs/testing.md).

## Behaviour guides

- [Notes](../../docs/notes.md) and [the Notes file format](../../docs/notes-format.md)
- [Embedded pages](../../docs/embedded-pages.md)
- [Capture editing](../../docs/capture-editing.md)
