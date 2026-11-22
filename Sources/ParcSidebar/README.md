# ParcSidebar

ParcSidebar builds the AppKit sidebar, including Favorites, Pinned and Today,
folders and split rows, Space paging, previews and the sidebar's page controls.
It also provides the Space manager and theme editor. The browser window hosts
these surfaces and owns live tabs, renderer content, window-level layout and
transactions that act on the original browser context. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Start in the source

[SidebarView.swift](SidebarView.swift) holds `SidebarView`, the tab rows and
the selection and accessibility entry points. [FavoriteTile.swift](FavoriteTile.swift)
owns the Favorites tiles. [SidebarItemDrag.swift](SidebarItemDrag.swift)
handles sidebar move sessions, and [SplitDragView.swift](SplitDragView.swift)
presents split rows and their drag surfaces.

[SidebarMotionController.swift](SidebarMotionController.swift) animates the
sidebar, [SidebarResizeRegion.swift](SidebarResizeRegion.swift) handles the
width gesture, and [SidebarSpacePaging.swift](SidebarSpacePaging.swift) tracks
Space swipes. [SidebarPreviewController.swift](SidebarPreviewController.swift)
coordinates preview requests and [SidebarPreviewCard.swift](SidebarPreviewCard.swift)
displays the result.

[SpaceManagerView.swift](SpaceManagerView.swift) provides the Spaces page
with a sidebar in each card. [SpaceCreationView.swift](SpaceCreationView.swift)
holds the new Space controls and [SpaceThemeEditorView.swift](SpaceThemeEditorView.swift)
holds the theme editor. [SidebarLibraryEntry.swift](SidebarLibraryEntry.swift)
mounts the Library button and its flyout. [NavigationControls.swift](NavigationControls.swift)
holds the navigation buttons and history menu, [ExtensionControls.swift](ExtensionControls.swift)
holds the extension controls, and [MiniPlayerView.swift](MiniPlayerView.swift)
holds the sidebar media deck.

## Imports and host API

`ParcCore` supplies browser and Space models, sidebar transactions and theme
values. `ParcEngine` supplies native navigation, media and Profile removal.
`ParcKit` supplies shared controls and theme rendering. `ParcNotes` and
`ParcEasels` supply document preview support. `ParcLibrary` supplies Library
tiles, flyout models and the Spaces-page contract. `ParcCommandBar` supplies
the site color adjustment used on the Space creation card.

The app shell constructs and updates `SidebarView`. Its browser-window
callbacks supply:

- Drop, copy, transfer, selection, archive, close and deletion operations,
  including the original-item validation that precedes them.
- Tab activation, close, reset, icon reset, live and saved favicon requests and
  mute. Favorites have their own pointer, activate, rename and close handlers,
  and a handler to dismiss their empty state.
- Split availability, presented-content checks, split creation and drag,
  separation, close, row commands, title editing and appearance changes.
- Space selection, creation, rename, icon and theme editing, management menus,
  paging theme, and selection and folder moves into an existing or new Space.
  Folder handlers cover disclosure, peeks, copy links, creation, rename, icon,
  deletion and duplication, including the empty-folder check. The shell also
  supplies selection duplication, title-edit completion, reveal for editing,
  outline invalidation, Pinned section changes and the single-Space header
  preference.
- Address, new tab, navigation, reload options, blocked content, Settings,
  Library entry and flyout actions, download file lookup and Library hover.
  Plus menu actions include new Space, folder, Easel, Note and split, opening
  Note files, and checking whether creation and splitting are available.
- Sidebar toggle, preview and preview preference changes, Clear Today and its
  availability, page menus, payments, capture menu and active state, and
  preparing to share the tab. Banner handlers cover archive education,
  relinquishing focus, What's New, dismissal, restart and automatic updates.
  [BrowserWindowController+Sidebar.swift](../Parc/BrowserWindowController+Sidebar.swift),
  [BrowserWindowController+Spaces.swift](../Parc/BrowserWindowController+Spaces.swift),
  [BrowserWindowController+ChromeLayout.swift](../Parc/BrowserWindowController+ChromeLayout.swift),
  [BrowserWindowController+PinnedSection.swift](../Parc/BrowserWindowController+PinnedSection.swift),
  [BrowserWindowController.swift](../Parc/BrowserWindowController.swift)

The browser window also provides the preview source, permission, offers and
action dispatch, recent rows, pictures, document updates, favicons,
presentation changes and Settings action to `SidebarPreviewController`.
It supplies hover regions and changes to `SidebarHoverTracker` and pan and
double-click actions to `SidebarResizeRegionView`. The window configures
`SpaceManagerView` with the card sidebars, menus, current Space, owner check,
create, close and reorder actions. For the card sidebar it supplies management
validity and cancellation and handles Space name-edit completion. For
`SpaceCreationView` it supplies name and sharing changes, icon and theme
choices, create and cancel.
[BrowserWindowController+Sidebar.swift](../Parc/BrowserWindowController+Sidebar.swift),
[BrowserWindowController.swift](../Parc/BrowserWindowController.swift),
[BrowserWindowController+Spaces.swift](../Parc/BrowserWindowController+Spaces.swift)

The window wires the theme editor's preview, commit or merge, dismissal,
appearance, tooltip theme and preset page callbacks as appropriate to the
editor's context. Onboarding supplies preview, commit and appearance callbacks
to the same `SpaceThemeEditorView`. The browser window also supplies the
original-target checks, commit and finish actions for `FavoriteRenameDialog`
and `SidebarGroupIconPicker`, plus the picker's failure handler.
[BrowserWindowController+Rendering.swift](../Parc/BrowserWindowController+Rendering.swift),
[BrowserWindowController+Spaces.swift](../Parc/BrowserWindowController+Spaces.swift),
[BrowserWindowController+SidebarActions.swift](../Parc/BrowserWindowController+SidebarActions.swift),
[OnboardingWindow.swift](../ParcOnboarding/OnboardingWindow.swift)

`BrowserWindowController` conforms to `SidebarMoveOwner` and supplies move
validation, cross-window eligibility, proposal and commit to `SidebarMoveSession`.
It supplies split validation and commit to `SidebarSplitDrag`. Sidebar rows
implement `SplitDropCardSource` for the app's drop view and
`SidebarDeferredAccessibilityActions` for deferred row actions.
[BrowserWindowController+SidebarMoves.swift](../Parc/BrowserWindowController+SidebarMoves.swift),
[BrowserWindowController+Splits.swift](../Parc/BrowserWindowController+Splits.swift),
[SplitDropView.swift](../Parc/SplitDropView.swift)

The shell supplies navigation activation, history presentation, history
selection, row actions and history lifetime checks. It wires extension
execution, context menus, pin changes and toolbar width changes, address
popover lifetime callbacks, and Mini Player item validity and reveal actions.
Popup chrome supplies its row action and navigation preparation. Site Control
Center subclasses `SidebarPlusMenuWindow` and supplies its key-loss action.
The window supplies undo validation and actions to the sidebar undo APIs.
Settings supplies sheet completion to `SidebarPreviewSettingsSheet` and
uses `ProfileRemovalController`. Settings and the browser window both supply
owner validity, an explanation for blocked moves, and a completion handler
to `SpaceSharingConfirmation`. Startup uses `SidebarRescue` to open the store.
[BrowserWindowController+Navigation.swift](../Parc/BrowserWindowController+Navigation.swift),
[BrowserWindowController+NoteVisits.swift](../Parc/BrowserWindowController+NoteVisits.swift),
[BrowserWindowController+Toolbars.swift](../Parc/BrowserWindowController+Toolbars.swift),
[BrowserToolbar.swift](../Parc/BrowserToolbar.swift),
[BrowserWindowController+MediaAndCapture.swift](../Parc/BrowserWindowController+MediaAndCapture.swift),
[PopupChromeView.swift](../Parc/PopupChromeView.swift),
[SiteControlCenter.swift](../Parc/SiteControlCenter.swift),
[FolderUndoManager.swift](FolderUndoManager.swift), [CloseUndo.swift](CloseUndo.swift),
[SidebarRescue.swift](SidebarRescue.swift),
[SettingsWindow.swift](../ParcSettings/SettingsWindow.swift)

## Tests

[Sidebar](../../tests/ParcTests/Sidebar) covers rows, menus, motion, previews,
selection, sizing and Space cards. Related coverage is in
[Capture](../../tests/ParcTests/Capture) for Library integration,
[CommandBar](../../tests/ParcTests/CommandBar) for keyboard integration,
[Data](../../tests/ParcTests/Data) for browser state and Profile removal,
[Notes](../../tests/ParcTests/Notes) for document interactions,
[Presentation](../../tests/ParcTests/Presentation) for theme and chrome, and
[Windows](../../tests/ParcTests/Windows) for window integration. From the
repository root, run `swift test --filter SidebarResizeRegionTestsGesturesTests`
for the resize gestures suite, or `swift test` for all suites.

## Behavior guides

- [Sidebar motion](../../docs/sidebar-motion.md), [resizing](../../docs/sidebar-resize.md), [selection](../../docs/sidebar-selection.md) and [accessibility](../../docs/sidebar-accessibility.md)
- [Previews](../../docs/sidebar-previews.md), [saved tabs](../../docs/saved-tabs.md) and [folder moves](../../docs/folder-moves.md)
- [Space management](../../docs/space-management.md), [theme editing](../../docs/space-theme-editor.md) and [Mini Player](../../docs/media-mini-player.md)
