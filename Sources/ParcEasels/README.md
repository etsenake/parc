# ParcEasels

ParcEasels is the Easel editor: the infinite canvas, its tools, objects,
selection toolbar, panels, find, exports and the Easel blocks that appear
inside notes. Boards, their items, geometry, undo history and file storage are
models in ParcCore; ParcEasels draws and edits them, reusing the Notes editor
from ParcNotes for rich text, menus, media and equations. In the
[app architecture](../../docs/app-architecture.md) it sits above ParcNotes,
and ParcLibrary and ParcSidebar build on it.

## Where to start

**The editor and canvas.**
[EaselEditorViewController.swift](EaselEditorViewController.swift) hosts one
open Easel with its toolbar, page switcher and panels.
[EaselCanvasView.swift](EaselCanvasView.swift) is the canvas; each area of its
behaviour is an extension in its own `EaselCanvasView+….swift` file (tools,
text, stickies, sections, tables, connectors, images, video, Mermaid, mind
maps, rotation, stamps, the selection toolbar, clipboard, context menu and
exporting a selection). The `EaselCanvas…` files hold the pieces those
extensions share, such as hosted objects, shape rendering, media, feedback and
the canvas's page session. [EaselBoardViewport.swift](EaselBoardViewport.swift)
handles panning and zooming, and [EaselBoardKeys.swift](EaselBoardKeys.swift)
the board's key commands.

**Tools and panels.** [EaselToolPalette.swift](EaselToolPalette.swift) is the
toolbar of tools, [EaselShapePicker.swift](EaselShapePicker.swift),
[EaselColorPicker.swift](EaselColorPicker.swift),
[EaselTemplateGallery.swift](EaselTemplateGallery.swift) and
[EaselStampPanels.swift](EaselStampPanels.swift) are its pickers, and
[EaselSelectionToolbar.swift](EaselSelectionToolbar.swift) is the floating
toolbar over a selection. [EaselPanels.swift](EaselPanels.swift),
[EaselPageMenu.swift](EaselPageMenu.swift) and
[EaselPageSwitcher.swift](EaselPageSwitcher.swift) manage pages, and
[EaselFindController.swift](EaselFindController.swift) is find and replace.

**Text.** [EaselStickyText.swift](EaselStickyText.swift),
[EaselParagraphEditing.swift](EaselParagraphEditing.swift) and
[EaselRichTextCodec.swift](EaselRichTextCodec.swift) edit and store text on the
canvas, and [EaselInlineText.swift](EaselInlineText.swift) draws inline items
such as dates, emoji and page links inside it; the `Easel…Completion.swift` files complete slash commands, mentions and
emoji as you type.

**Media, web and exports.** [EaselMediaHost.swift](EaselMediaHost.swift) and
the `EaselImage…` files place and edit pictures and video;
[EaselWebObjects.swift](EaselWebObjects.swift) adds links and bookmark cards,
and [EaselBrowserObjects.swift](EaselBrowserObjects.swift) hosts the live
pages and captures on a board; [EaselDocumentExport.swift](EaselDocumentExport.swift),
[EaselImageExport.swift](EaselImageExport.swift) and
[EaselTableExport.swift](EaselTableExport.swift) write files.

**Easels in notes.** [NoteEaselBlockView.swift](NoteEaselBlockView.swift)
draws an Easel block in a note and holds `NoteEaselProvider`, and
[NoteEaselPages.swift](NoteEaselPages.swift) gives those blocks their live
pages.

## Imports and hooks

ParcEasels imports ParcCore for the board models and store, ParcNotes for the
editor pieces it reuses, ParcKit for shared controls and ParcEngine for live
pages. The editor, canvas and their presenters are `package` for ParcLibrary,
ParcSidebar and Parc.

It supplies the hooks ParcNotes declares: `NoteEaselProvider` implements
`NoteBoardProviding`, which Parc registers at launch, and
`EaselWindowActions` extends `NoteWindowActions` with what an Easel asks of its
window, which Parc's `BrowserWindowController` conforms to.

`EaselCanvasView` itself takes its presenters through static factories, so the
canvas can be built and tested without them. `AppDelegate` in Parc registers
them at launch: `selectionToolbarFactory`, `textCompletionFactory`,
`highlightRecorder` and `highlightRecall`, `mermaidSheetFactory`,
`menuPresenterFactory`, `equationEditorFactory` and `stampPanelsFactory`. Its
instance callbacks (`onExportImage`, `onError` and others) are set by the editor
that hosts it.

## Tests

Tests live in [tests/ParcTests](../../tests/ParcTests/README.md), mostly in the
Easels folder, with `TestEaselCanvas` in `tests/ParcTests/Support` building a
canvas for them. Board models, layout and exports are tested in
[tests/ParcCoreTests](../../tests/ParcCoreTests/README.md). Run one suite with
`swift test --filter EaselIdleSleepTests`, or everything with `swift test`. See
the [testing guide](../../docs/testing.md).

## Behaviour guides

- [Easels](../../docs/easels.md), [tools](../../docs/easel-tools.md),
  [text](../../docs/easel-text.md) and [shapes](../../docs/easel-shapes.md)
- [Connectors](../../docs/easel-connectors.md),
  [stickies and sections](../../docs/easel-stickies-sections.md),
  [tables](../../docs/easel-tables.md) and [Mermaid](../../docs/easel-mermaid.md)
- [Images](../../docs/easel-images.md), [live captures](../../docs/easel-live-captures.md),
  [pages](../../docs/easel-pages.md) and [rotation](../../docs/easel-rotation.md)
- [Arranging](../../docs/easel-arranging.md), [drawing](../../docs/easel-drawing.md),
  [stamps](../../docs/easel-stamps.md) and [appearance](../../docs/easel-appearance.md)
