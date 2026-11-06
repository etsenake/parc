import Foundation

///
/// menu gives each Type Travel item an `arcTypeTravelIcon` SF Symbol and, for
///
/// 1.170's `MainMenu.nib`, read into `ASE2.TypeTravelCandidate.MenuItemInfo`).
/// Commands are keyed by their selector, so a toggled title (Hide Toolbar,
/// Exit Reader, Close Settings) keeps its icon.
enum CommandBarCommandPresentation {
    static func symbol(commandID: String, title: String, group: String = "") -> String {
        if let symbol = symbol(forCommandID: commandID) { return symbol }
        if title.hasPrefix("Go to") && title.contains("Sidebar Item") { return "arrow.right" }
        return groupSymbols[group] ?? "arrow.right.circle"
    }

    static func symbol(forCommandID commandID: String) -> String? { commandSymbols[selectorName(commandID)] }

    ///
    static func title(commandID: String, title: String) -> String { commandTitles[selectorName(commandID)] ?? title }

    /// `share:` and `share` name the same command.
    static func selectorName(_ commandID: String) -> String { String(commandID.prefix { $0 != ":" }) }

    private static let commandTitles = ["sharePage": "Share URL"]

    ///
    ///
    /// template image.
    private static let commandSymbols: [String: String] = [
        "about": "book.closed", "settings": "gearshape" /* Parc */, "setAsDefaultBrowser": "heart",
        "importFromBrowser": "arrow.turn.right.down", "quitMenu": "hand.wave",
        "newTab": "add-tab", "focusAddress": "magnifyingglass" /* Parc */, "newWindow": "plus.rectangle",
        "newIncognitoWindow": "macwindow.on.rectangle", "newBlankWindow": "macwindow.on.rectangle",
        "createSpace": "plus.rectangle.portrait", "newProfile": "person.fill", "createNote": "note.text",
        "createNoteInSplit": "note.text", "createEasel": "scribble.variable", "exportNotes": "arrow.down.doc",
        "closeWindow": "xmark.circle", "closeTab": "archivebox", "restoreTab": "arrow.uturn.backward",
        "sharePage": "square.and.arrow.up", "capturePage": "camera", "captureVisiblePage": "camera",
        "captureFullPage": "newspaper", "savePage": "square.and.arrow.down", "printPage": "printer",
        "copyCurrentURL": "doc.on.doc", "copyCurrentURLAsMarkdown": "doc.on.doc", "copyCurrentURLAsQuote": "quote.bubble",
        "pasteAsPlainText": "list.clipboard",
        "find": "magnifyingglass", "findAndReplace": "magnifyingglass", "findNext": "arrow.right",
        "findPrevious": "arrow.left", "useSelectionForFind": "magnifyingglass", "jumpToSelection": "arrow.turn.right.down",
        "toggleSidebar": "sidebar.left", "toggleArcToolbar": "rectangle.topthird.inset.filled", "focusSidebar": "sidebar.left",
        "stopLoading": "xmark.circle" /* Parc */, "reload": "arrow.clockwise", "forceReload": "arrow.clockwise",
        "clearCookiesAndRefresh": "trash", "clearCacheAndRefresh": "trash", "clearBrowsingData": "trash" /* Parc */,
        "split": "square.split.2x1", "closeSplitPane": "xmark.square", "separateSplitPane": "scissors",
        "expandSplitPane": "arrow.up.left.and.arrow.down.right",
        "firstSplitPane": "square.split.2x1", "secondSplitPane": "square.split.2x1", // Parc
        "thirdSplitPane": "square.split.2x1", "fourthSplitPane": "square.split.2x1", // Parc
        "actualSize": "magnifyingglass", "zoomIn": "plus.magnifyingglass", "zoomOut": "minus.magnifyingglass",
        "toggleReaderMode": "newspaper" /* Parc */, "castPage": "rectangle.portrait.and.arrow.right.fill",
        "viewSource": "curlybraces", "developerTools": "hammer.fill", "inspectElements": "scope",
        "javaScriptConsole": "terminal", "networkInspector": "wifi", "toggleScriptPermission": "curlybraces" /* Parc */,
        "toggleDeveloperMode": "hammer.fill", "captureRenderingMetrics": "flag" /* Parc */,
        "toggleFairPlayIdentity": "safari" /* Parc */,
        "checkAutoArchive": "archivebox" /* Parc */, "toggleFullScreen": "arrow.up.left.and.arrow.down.right", "exit": "escape",
        "createFolder": "folder", "togglePin": "pin", "duplicateCurrentItem": "plus.square.on.square",
        "revealCurrentTabInSidebar": "arrow.left.circle", "openInCurrentSpace": "macwindow.on.rectangle" /* Parc */,
        "resetTab": "arrow.backward.to.line" /* Parc */, "clearToday": "bubbles.and.sparkles",
        "resetVisibleSavedTabs": "arrow.backward.to.line", "renameCurrentItem": "character.cursor.ibeam",
        "collapseAllFolders": "chevron.right", "expandAllFolders": "chevron.down", // Parc
        "nextTab": "arrow.right", "previousTab": "arrow.left", "cycleTabForward": "arrow.right", "cycleTabBackward": "arrow.left",
        "cycleToNextRecentTab": "arrow.right", "cycleToPreviousRecentTab": "arrow.left", // Parc
        "goBack": "arrow.backward", "goForward": "arrow.right", "history": "book", "archive": "archivebox",
        "clearArchive": "archivebox", "manageExtensions": "puzzlepiece", "addExtension": "plus.circle",
        "openSpaceManager": "rectangle.portrait.on.rectangle.portrait", "editTheme": "paintbrush.pointed.fill",
        "renameFocusedSpace": "character.cursor.ibeam", "changeSpaceProfile": "person.fill",
        "nextSpace": "arrow.right.to.line", "previousSpace": "arrow.left.to.line",
        "viewLibrary": "archivebox", "downloads": "arrow.down.circle", "captureLibrary": "photo.on.rectangle.angled",
        "showDocuments": "scribble.variable", "showEssentialShortcuts": "keyboard",
        "performMiniaturize": "arrow.down.right.and.arrow.up.left", "performZoom": "arrow.up.left.and.arrow.down.right",
        "hide": "macwindow", "hideOtherApplications": "macwindow", "unhideAllApplications": "book",
        "goBackArrow": "arrow.backward", "goForwardArrow": "arrow.right",
        "nextSplitPane": "arrow.right", "previousSplitPane": "arrow.left", "openExtensions": "puzzlepiece", // Parc
    ]

    private static let groupSymbols: [String: String] = [
        "Spaces": "rectangle.portrait.on.rectangle.portrait", // Manage Spaces…
        "Tabs": "arrow.right",
        "Window": "macwindow",
    ]
}
