# Parc app shell

This is the Swift/AppKit application library that connects the feature libraries
to browser windows and the engine. It owns application and window lifetimes,
menus, page presentation, splits, Peek and the start page. The libraries below
it own browser state and persistence, shared controls and feature views. The
executable entry point lives in [ParcMain](../ParcMain/README.md). How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Where to start

- [ParcLaunch.swift](ParcLaunch.swift) creates the application and delegate,
  prepares the browser, and enters the engine's main loop.
  [ParcApplication.swift](ParcApplication.swift) supplies the native application
  subclass. [AppDelegate.swift](AppDelegate.swift) handles the menus, startup,
  window restoration, Profiles, app-open events, onboarding and shutdown.
- [BrowserWindowController.swift](BrowserWindowController.swift) owns one
  window's views and native window client. Its feature extensions wire
  [the sidebar](BrowserWindowController+Sidebar.swift),
  [the command bar](BrowserWindowController+CommandBar.swift),
  [navigation and the Library](BrowserWindowController+Navigation.swift),
  [page lifetimes](BrowserWindowController+PageLifecycle.swift) and
  [transfers between windows](BrowserWindowController+PageTransfers.swift).
- [BrowserPane.swift](BrowserPane.swift) hosts page content.
  [ParcSplitView.swift](ParcSplitView.swift) lays out panes and dividers.
  [BrowserWindowController+Splits.swift](BrowserWindowController+Splits.swift)
  connects the layout to the window's split commands and store.
- [PeekController.swift](PeekController.swift) presents temporary web and
  document cards. [BrowserWindowController+Peek.swift](BrowserWindowController+Peek.swift)
  handles their lifetime and promotion. [StartPageView.swift](StartPageView.swift)
  is the empty Space's surface, wired by
  [BrowserWindowController+StartPage.swift](BrowserWindowController+StartPage.swift).
- [BrowserPopupWindow.swift](BrowserPopupWindow.swift),
  [SiteControlCenter.swift](SiteControlCenter.swift) and
  [PageCaptureController.swift](PageCaptureController.swift) are entry points for
  auxiliary windows, site controls and page capture.
- [SoftwareUpdater.swift](SoftwareUpdater.swift) integrates Sparkle.
  [SoftwareUpdateBanner.swift](SoftwareUpdateBanner.swift) owns the update
  banner state. [ApplicationTermination.swift](ApplicationTermination.swift)
  coordinates quit and [ApplicationRestart.swift](ApplicationRestart.swift)
  handles the browser-import restart helper.

## Dependencies and connections

[Package.swift](../../Package.swift) puts `Parc` above `ParcCore`, `ParcEngine`,
`ParcKit`, `ParcNotes`, `ParcEasels`, `ParcLibrary`, `ParcCommandBar`,
`ParcSidebar`, `ParcSettings` and `ParcOnboarding`. The shell also imports
Sparkle. It exposes `ParcLaunch.run()` to the executable and supplies the
concrete clients and actions that lower layers call.

[AppDelegate.prepare()](AppDelegate.swift) makes the app-wide connections.

- `BrowserStore` gets `sidebarBannerOccupied`, `requestPageRetirement`,
  `prepareLocalDocumentRelocation` and `relocateLocalDocuments` so it can
  coordinate with update banners, live pages and open documents.
- `LiveShortcutToolTip` gets its `binder` and `resolver`.
  `TooltipController` gets `commandShortcut`, `eventChord` and
  `symbolicChord`. `KeyboardShortcuts.onDiscoveryChange` posts the tooltip
  change notification when discovery changes.
- `NoteBlockViewFactory.boards` gets `NoteEaselProvider` so a Note can host an
  Easel block. `EaselCanvasView` gets `selectionToolbarFactory`,
  `textCompletionFactory` for slash, mention and emoji completion,
  `mermaidSheetFactory`, `menuPresenterFactory`, `equationEditorFactory` and
  `stampPanelsFactory`. Its `highlightRecorder` and `highlightRecall` use
  the Notes color recents.
- `PCNativeBrowserApplication.setApplicationClient` registers the delegate
  for native app events. After the engine starts, `ImportedExtensionFailures.present`
  and `ImportedBrowserDataFailures.present` route reports to the front browser
  window. During AppKit launch, `NoteCoverSupply.install()` supplies new-note
  covers and `NoteReminderCenter.onOpenNote` routes reminder clicks to the
  Note or Easel owner.

Window-level connections live beside the features that use them.

- [Notes and Easels](BrowserWindowController+NotesAndEasels.swift) implements
  [EaselWindowActions](../ParcEasels/EaselEditorViewController.swift), which
  extends [NoteWindowActions](../ParcNotes/NoteFormatBar.swift). Editors use those
  actions to ask the window to navigate or update its chrome. The same
  extension wires Notes editor callbacks for opening links and files,
  updating tab titles, showing toasts and handling document removal.
- [Navigation](BrowserWindowController+Navigation.swift) passes
  `SpaceManagerView` as the Library's [LibrarySpacesPage](../ParcLibrary/LibraryView.swift) and wires the Library
  callbacks for documents, links, downloads, archive restore and previews.
- [Sidebar moves](BrowserWindowController+SidebarMoves.swift) implements
  [SidebarMoveOwner](../ParcSidebar/SidebarItemDrag.swift) for drag sessions. [Sidebar wiring](BrowserWindowController+Sidebar.swift)
  connects the feature view to window commands. [Command bar wiring](BrowserWindowController+CommandBar.swift)
  connects suggestions and submissions to navigation and window actions.
- [AppDelegate.settingsActions](AppDelegate.swift) supplies
  `canReplayOnboarding`, `replayOnboarding` and `adjustWindowFrame` to
  `SettingsWindow`. The delegate also handles onboarding's completion,
  cancellation, reveal and import-restart callbacks for first launch and replay.
- [BrowserWindowController](BrowserWindowController.swift) is the native
  window and page client. [ExternalSplitDropHost](ExternalSplitDropView.swift)
  connects native and local content drops to split admission.

## Checks and guides

[ParcTests](../../tests/ParcTests/README.md) imports the app library directly.
Its `Windows`, `LinkRouting` and `Presentation` folders are starting points
for shell changes. Run from the repository root:

```sh
swift test
swift test --filter SoftwareUpdateBannerTests
```

See [window lifetimes](../../docs/windows-lifecycle.md),
[split groups](../../docs/split-groups.md), [Peek](../../docs/peek.md),
[the start page](../../docs/start-page.md),
[page capture](../../docs/page-capture.md) and
[software updates](../../docs/software-update.md) for the behavior behind
these entry points.
