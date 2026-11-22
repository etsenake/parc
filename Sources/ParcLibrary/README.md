# ParcLibrary

ParcLibrary builds the browser's Library and the controls for saving, editing
and reviewing captures and downloads. It presents Archive, Captures, Downloads,
Easels & Notes, and Spaces. The browser window owns live pages, runs navigation
and download actions, and mounts the capture overlay. The sidebar owns the
Library entry button and supplies the Spaces page. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Start in the source

[LibraryView.swift](LibraryView.swift) holds the `LibraryView` host and Archive
table. It handles category changes, search, selection, and requests to restore or
preview archived items. [LibraryRailTile.swift](LibraryRailTile.swift) holds the
category control. [DocumentsLibraryView.swift](DocumentsLibraryView.swift) and
[DocumentsLibraryCatalog.swift](DocumentsLibraryCatalog.swift) build the grid
and its catalog from local Notes and Easels.

[DownloadLibraryView.swift](DownloadLibraryView.swift) builds the download list
and `DownloadLibraryPreview` owns its file preview window.
[DownloadLibraryPreview.swift](DownloadLibraryPreview.swift)
`DownloadReviewController` holds the review UI for downloads that need a
decision. [DownloadReviewController.swift](DownloadReviewController.swift)
The entry flyout's catalog and presentation model live in
[LibraryFlyout.swift](LibraryFlyout.swift),
and [DownloadArrival.swift](DownloadArrival.swift) owns the arrival animation.

[CaptureLibraryView.swift](CaptureLibraryView.swift) builds the Captures grid.
[CaptureLibraryStore.swift](CaptureLibraryStore.swift) persists saved captures,
and [ExternalMediaLibrary.swift](ExternalMediaLibrary.swift) discovers media in
folders. [CaptureModeBar.swift](CaptureModeBar.swift) and
[CapturePaletteView.swift](CapturePaletteView.swift) build the capture controls.
[CaptureImageEditor.swift](CaptureImageEditor.swift) edits the captured image,
and [PortraitCapture.swift](PortraitCapture.swift) composes the Portrait frame.

## Imports and host API

`ParcCore` supplies the browser store and archive, download and document models.
`ParcEngine` supplies native values for capture state and download review.
`ParcKit` supplies shared controls and presentation. `ParcNotes` and
`ParcEasels` supply the document catalog and card content.

The main package entry point is `LibraryView`. The browser window provides the
store, Profile and optional private media context with its validity check. Its
callbacks handle closure and toasts, opening URLs, Archive ownership, restore
and preview, download loading, actions and file lookup, favicon requests,
category changes, leaving Spaces, width changes, and opening, creating,
renaming and deleting documents. `SpaceManagerView` in ParcSidebar conforms
to `LibrarySpacesPage`, which lets the host mount it, update its size and
context, and coordinate focus and dismissal.
[BrowserWindowController+Navigation.swift](../Parc/BrowserWindowController+Navigation.swift),
[BrowserWindowController+Spaces.swift](../Parc/BrowserWindowController+Spaces.swift),
[SpaceManagerView.swift](../ParcSidebar/SpaceManagerView.swift)

The sidebar's `SidebarLibraryEntry` subclasses the open
`TranslucentBoxOfThingsItem` and connects the action, badge changes, flyout hover,
expansion, scheduling and image loading, row rings and subtitles, accessibility
geometry, press and children callbacks, and lazy file and capture drag providers.
It also supplies flyout menu dispatch and thumbnail callbacks, and the file
preview's source rectangle, movement, open, copy, menu and close callbacks.
The browser window supplies capture deletion confirmation, folder-change
handling for `LibraryFlyoutFolderMonitor`, the arrival context for
`DownloadArrivalOwner`, and decision, link, refresh and close handling for
`DownloadReviewController`.
[BoxOfThingsIcon.swift](BoxOfThingsIcon.swift),
[SidebarLibraryEntry.swift](../ParcSidebar/SidebarLibraryEntry.swift),
[BrowserWindowController+Library.swift](../Parc/BrowserWindowController+Library.swift),
[BrowserWindowController+Downloads.swift](../Parc/BrowserWindowController+Downloads.swift)

The app shell's capture controller uses the package image, editor, palette, mode
bar, Portrait view and destination APIs. It supplies palette action, cancel
and size callbacks, mode selection, Portrait capture, cancel, preview and resize
callbacks, image-editor validity, apply and completion, and the result handling
for Messages sharing.
[PageCaptureController.swift](../Parc/PageCaptureController.swift)

## Tests

[Capture](../../tests/ParcTests/Capture) covers the Library categories, media
catalogs, file actions and capture presentation. [Sidebar](../../tests/ParcTests/Sidebar)
covers rail and Space card behavior. [Notes](../../tests/ParcTests/Notes) covers
the documents catalog, and [Easels](../../tests/ParcTests/Easels) covers capture
destinations that include Easels. Run a suite from the repository root with
`swift test --filter LibrarySpacesHostTests` or run all suites with `swift test`.

## Behavior guides

- [Archive and retention](../../docs/archive.md) and [archive previews](../../docs/archive-preview.md)
- [Downloads](../../docs/download-library.md) and [the Captures Library](../../docs/capture-library.md)
- [Page capture](../../docs/page-capture.md), [capture editing](../../docs/capture-editing.md) and [destinations](../../docs/capture-destinations.md)
- [Easels & Notes cards](../../docs/documents-library-grid.md) and [Space management](../../docs/space-management.md)
