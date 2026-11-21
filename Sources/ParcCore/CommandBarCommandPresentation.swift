import Foundation

package enum CommandBarCommandPresentation {
    package static func symbol(commandID: String, title: String, group: String = "") -> String {
        if let symbol = symbol(forCommandID: commandID) { return symbol }
        if title.hasPrefix("Go to") && title.contains("Sidebar Item") { return "arrow.right" }
        return groupSymbols[group] ?? "arrow.right.circle"
    }

    package static func symbol(forCommandID commandID: String) -> String? { commandSymbols[selectorName(commandID)] }

    package static func title(commandID: String, title: String) -> String { commandTitles[selectorName(commandID)] ?? title }

    package static func selectorName(_ commandID: String) -> String { String(commandID.prefix { $0 != ":" }) }

    private static let commandTitles = ["sharePage": "Share URL"]

    private static let commandSymbols: [String: String] = [
        "about": "book.closed", "settings": "gearshape", "setAsDefaultBrowser": "heart",
        "importFromBrowser": "arrow.turn.right.down", "checkForUpdates": "arrow.down.circle",
        "quitMenu": "hand.wave",
        "newTab": "add-tab", "focusAddress": "magnifyingglass", "newWindow": "plus.rectangle",
        "newIncognitoWindow": "macwindow.on.rectangle", "newBlankWindow": "macwindow.on.rectangle",
        "createSpace": "plus.rectangle.portrait", "createNote": "parc.note",
        "createNoteInSplit": "note.text", "createEasel": "parc.easel", "showNotesFolder": "folder",
        "closeWindow": "xmark.circle", "closeTab": "archivebox", "restoreTab": "arrow.uturn.backward",
        "sharePage": "square.and.arrow.up", "capturePage": "camera", "captureVisiblePage": "camera",
        "captureFullPage": "newspaper", "savePage": "square.and.arrow.down", "printPage": "printer",
        "copyCurrentURL": "doc.on.doc", "copyCurrentURLAsMarkdown": "doc.on.doc", "copyCurrentURLAsQuote": "quote.bubble",
        "pasteAsPlainText": "list.clipboard",
        "find": "magnifyingglass", "findAndReplace": "magnifyingglass", "findNext": "arrow.right",
        "findPrevious": "arrow.left", "useSelectionForFind": "magnifyingglass", "jumpToSelection": "arrow.turn.right.down",
        "toggleSidebar": "sidebar.left", "toggleShowToolbar": "rectangle.topthird.inset.filled", "focusSidebar": "sidebar.left",
        "adjustWindowFrame": "macwindow",
        "stopLoading": "xmark.circle", "reload": "arrow.clockwise", "forceReload": "arrow.clockwise",
        "clearCookiesAndRefresh": "trash", "clearCacheAndRefresh": "trash", "clearBrowsingData": "trash",
        "split": "square.split.2x1", "splitThisPane": "square.split.2x2", "closeSplitPane": "xmark.square",
        "separateSplitPane": "scissors",
        "expandSplitPane": "arrow.up.left.and.arrow.down.right",
        "widenSplitPane": "arrow.left.and.right", "narrowSplitPane": "arrow.right.and.line.vertical.and.arrow.left",
        "equalizeSplitPanes": "equal.square",
        "firstSplitPane": "square.split.2x1", "secondSplitPane": "square.split.2x1",
        "thirdSplitPane": "square.split.2x1", "fourthSplitPane": "square.split.2x1",
        "actualSize": "magnifyingglass", "zoomIn": "plus.magnifyingglass", "zoomOut": "minus.magnifyingglass",
        "toggleReaderMode": "newspaper", "castPage": "rectangle.portrait.and.arrow.right.fill",
        "viewSource": "curlybraces", "developerTools": "hammer.fill", "inspectElements": "scope",
        "javaScriptConsole": "terminal", "networkInspector": "wifi", "toggleScriptPermission": "curlybraces",
        "toggleDeveloperMode": "hammer.fill", "captureRenderingMetrics": "flag",
        "toggleFairPlayIdentity": "safari",
        "checkAutoArchive": "archivebox", "toggleFullScreen": "arrow.up.left.and.arrow.down.right", "exit": "escape",
        "createFolder": "folder", "togglePin": "pin", "duplicateCurrentItem": "plus.square.on.square",
        "revealCurrentTabInSidebar": "arrow.left.circle", "openInCurrentSpace": "macwindow.on.rectangle",
        "resetTab": "arrow.backward.to.line", "clearToday": "bubbles.and.sparkles",
        "resetVisibleSavedTabs": "arrow.backward.to.line", "renameCurrentItem": "character.cursor.ibeam",
        "collapseAllFolders": "chevron.right", "expandAllFolders": "chevron.down",
        "togglePinnedSection": "pin", "toggleCollapsedPinnedIcons": "eye.slash",
        "nextTab": "arrow.right", "previousTab": "arrow.left", "cycleTabForward": "arrow.right", "cycleTabBackward": "arrow.left",
        "cycleToNextRecentTab": "arrow.right", "cycleToPreviousRecentTab": "arrow.left",
        "goBack": "arrow.backward", "goForward": "arrow.right", "history": "book", "archive": "archivebox",
        "clearArchive": "archivebox", "manageExtensions": "puzzlepiece", "addExtension": "plus.circle",
        "openSpaceManager": "rectangle.portrait.on.rectangle.portrait", "editTheme": "paintbrush.pointed.fill",
        "renameFocusedSpace": "character.cursor.ibeam",
        "nextSpace": "arrow.right.to.line", "previousSpace": "arrow.left.to.line",
        "viewLibrary": "archivebox", "downloads": "arrow.down.circle", "captureLibrary": "photo.on.rectangle.angled",
        "showDocuments": "scribble.variable", "showEssentialShortcuts": "keyboard", "showReleaseNotes": "clock",
        "performMiniaturize": "arrow.down.right.and.arrow.up.left", "performZoom": "arrow.up.left.and.arrow.down.right",
        "hide": "macwindow", "hideOtherApplications": "macwindow", "unhideAllApplications": "book",
        "goBackArrow": "arrow.backward", "goForwardArrow": "arrow.right",
        "nextSplitPane": "arrow.right", "previousSplitPane": "arrow.left", "openExtensions": "puzzlepiece",
    ]

    private static let groupSymbols: [String: String] = [
        "Spaces": "rectangle.portrait.on.rectangle.portrait",
        "Tabs": "arrow.right",
        "Window": "macwindow",
    ]
}
