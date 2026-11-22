# ParcCore

ParcCore holds Parc's state, the files that store it and the logic that decides
what the app does, with no AppKit and no engine. Windows, Spaces, tabs and
Profiles, the Notes and Easel document models and their file formats, history,
routing, import and the decision logic behind the command bar, sidebar, splits
and onboarding all live here as plain Swift types. Views, controls and anything
that needs a window or the browser engine belong in the app libraries above it.
It sits at the bottom of the [app architecture](../../docs/app-architecture.md),
so every other app library imports it, and it builds and tests faster than any
of them.

## Where to start

**Browser state.** [BrowserStore.swift](BrowserStore.swift) holds
`BrowserStore`, the observable owner of every window, Space, tab, folder,
Favorite and Profile, and the operations that change them. It saves state as
JSON in `session.json`, keeps history in an append-only `history.jsonl`, and works with
[SessionBackups.swift](SessionBackups.swift),
[ClosedItems.swift](ClosedItems.swift) and
[TabHistoryArchive.swift](TabHistoryArchive.swift) for backups, closed-tab
restoration and the automatic archive.

**Notes.** [NoteModel.swift](NoteModel.swift) defines the document model
(`NotePage`, `NoteBlock` and its kinds). [NoteFiles.swift](NoteFiles.swift)
and the `NoteFile…` files read, write, name, watch and reconcile note files on
disk, and [NoteLibrary.swift](NoteLibrary.swift) indexes a notes folder.
[NoteFolderPreferences.swift](NoteFolderPreferences.swift) stores each
Profile's notes folder. The `NoteMarkdown…` and `NoteHTML…` files convert to and
from Markdown and HTML, `NoteSyntax…` highlights code, `NoteMath…` parses
equations, `NoteSynced…` keeps synced blocks in step across notes and
`NoteBacklink…` maintains backlinks.

**Easels.** [EaselPageModel.swift](EaselPageModel.swift) and
[EaselBoardObjects.swift](EaselBoardObjects.swift) define boards and their
items, and [EaselStore.swift](EaselStore.swift) loads, saves and lists them.
Geometry and layout live in [EaselShapeGeometry.swift](EaselShapeGeometry.swift),
[EaselConnectorRouting.swift](EaselConnectorRouting.swift),
[EaselTransform.swift](EaselTransform.swift) and
[EaselTableLayout.swift](EaselTableLayout.swift);
[EaselHistory.swift](EaselHistory.swift) records undo;
[EaselMermaid.swift](EaselMermaid.swift) and
[EaselMermaidLayout.swift](EaselMermaidLayout.swift) turn Mermaid text into
items; and the `…Export` files write images, vectors, HTML and media.

**Feature logic.** The command bar's typed commands, actions and result text are
in the `CommandBar…` files. The `Sidebar…` files cover keyboard navigation,
hover, previews, resizing and moves; the `Split…` files cover split layout and
drops; `SpaceTheme…`, [SpaceManagement.swift](SpaceManagement.swift) and
[SpaceSharing.swift](SpaceSharing.swift) cover Spaces. Routing rules are in
[LinkRouting.swift](LinkRouting.swift), browser import in
[BrowserImport.swift](BrowserImport.swift),
[ArcSidebarImport.swift](ArcSidebarImport.swift) and the `Safari…` files,
updates in [AutomaticUpdate.swift](AutomaticUpdate.swift) and
[SoftwareUpdateSession.swift](SoftwareUpdateSession.swift), and onboarding's
draft and steps in the `Onboarding…` files. Files ending in `Skip` hold the
small decisions that let the app skip work that wouldn't change anything.

## What it offers the libraries above

Types and members other libraries use are `package`; a handful of value types
that public view classes name in their initializers are `public`. ParcCore
imports only system frameworks.

Where state needs something only the app can provide, ParcCore exposes a closure
that defaults to doing nothing:

- `BrowserStore.requestPageRetirement`, `sidebarBannerOccupied`,
  `prepareLocalDocumentRelocation` and `relocateLocalDocuments` let the store
  coordinate with live pages, the update banner and open documents.
  `AppDelegate` in Parc supplies them at launch.
- `NoteFiles.newNoteCover` picks a cover for a new note; ParcNotes supplies it
  in `NoteCoverSupply`.
- `EaselStore.onSessionCreated`, `onListed` and `onDocumentRemoved` report board
  sessions and listings; ParcEasels sets `onSessionCreated` for inline dates.
- `NoteFileEnvironment.now` is the clock note files read, so tests can fix the
  time.

## Tests

Tests live in [tests/ParcCoreTests](../../tests/ParcCoreTests/README.md), in
folders by feature area: Browser, Capture, CommandBar, Data, Easels, Engine,
Favorites, Notes, Presentation, Sidebar and Windows, with fixtures in Resources
and helpers in Support. Run them with `swift test --filter ParcCoreTests`, or
one suite with `swift test --filter <SuiteName>`. Logic that can be tested here
should be: it needs no view and no main actor. See the
[testing guide](../../docs/testing.md).

## Behaviour guides

- [Notes](../../docs/notes.md) and [the Notes file format](../../docs/notes-format.md)
- [Easels](../../docs/easels.md)
- [Saved tabs and Favorites](../../docs/saved-tabs.md),
  [closed-tab restoration](../../docs/reopen-closed-tabs.md) and
  [automatic archive](../../docs/archive.md)
- [Command bar](../../docs/command-bar.md), [split groups](../../docs/split-groups.md)
  and [Space management](../../docs/space-management.md)
- [Routing](../../docs/routing-interaction.md),
  [browser import](../../docs/browser-import.md),
  [software updates](../../docs/software-update.md) and
  [onboarding](../../docs/onboarding.md)
