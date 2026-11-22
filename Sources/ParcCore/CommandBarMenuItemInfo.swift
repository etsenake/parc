import Foundation

package struct CommandBarMenuItemInfo: Equatable, Sendable {
    let triggers: [String]
    var bump: Double? = nil

    init(triggers: [String], bump: Double? = nil) {
        self.triggers = triggers
        self.bump = bump
    }

    static func info(forMenuCommand id: String) -> CommandBarMenuItemInfo? { table[id] }

    package static func candidateBump(forMenuCommand id: String) -> Double? { table[id]?.bump }

    static let bumpWeight = 0.06
    package static func rankingBump(_ bump: Double?) -> Double { (bump ?? 0) * bumpWeight }

    static func searchText(forMenuCommand id: String) -> String {
        table[id]?.triggers.joined(separator: " ") ?? ""
    }

    private static let table: [String: CommandBarMenuItemInfo] = [
        "actualSize:": .init(triggers: ["Reset Zoom"]),
        "adjustWindowFrame:": .init(triggers: ["Window Frame", "Frame Thickness", "Border", "Crank", "Thinner Frame", "Thicker Frame"]),
        "addExtension:": .init(triggers: ["Install Extensions", "Extension Store", "Plugins", "Chrome Extensions", "Chrome Store"]),
        "archive:": .init(triggers: ["Archive"]),
        "captureFullPage:": .init(triggers: ["Full Page Capture", "Capture Entire Page", "Screenshot Full Page", "Capture Full Page", "Screenshot"]),
        "captureLibrary:": .init(triggers: ["Screenshots", "Captures", "Videos", "Media"]),
        "capturePage:": .init(triggers: ["Capture", "Screenshot", "Snapshot", "Cut Out"]),
        "checkForUpdates:": .init(triggers: ["Download", "Update", "Check for Updates"]),
        "clearArchive:": .init(triggers: ["Clear Archive", "Delete Archive"]),
        "clearCacheAndRefresh:": .init(triggers: ["Clear Cache"]),
        "clearCookiesAndRefresh:": .init(triggers: ["Clear Cookies"]),
        "clearToday:": .init(triggers: ["Close Unpinned Tabs", "Clear Tabs", "Clear Today"]),
        "closeSplitPane:": .init(triggers: ["Close Split View"]),
        "closeTab:": .init(triggers: ["Exit Tab", "Unload", "Deselect", "Close"]),
        "closeWindow:": .init(triggers: ["Exit Window"]),
        "createEasel:": .init(triggers: ["Mood Board"]),
        "createNote:": .init(triggers: ["Create Note", "Note", "Scratchpad"]),
        "createNoteInSplit:": .init(triggers: ["Create Note in Split View", "Note Split", "Scratchpad Split"], bump: 0.9),
        "createSpace:": .init(triggers: ["Create New Space"]),
        "cycleToNextRecentTab:": .init(triggers: ["Toggle Tabs", "Switch tabs", "Recent tabs"]),
        "cycleToPreviousRecentTab:": .init(triggers: ["Toggle Tabs", "Switch tabs", "Recent tabs"]),
        "developerTools:": .init(triggers: ["Developer Tools", "Debug Tools", "Devtools"]),
        "downloads:": .init(triggers: ["Downloads"]),
        "editTheme:": .init(triggers: ["Theme", "Edit Theme", "Edit Space Theme"]),
        "exit:": .init(triggers: ["Exit", "Exit Modal", "Exit Full Screen"]),
        "expandSplitPane:": .init(triggers: ["Expand", "Expand Split View", "Maximize"]),
        "equalizeSplitPanes:": .init(triggers: ["Equalize Split View", "Even Split", "Equal Panes", "Reset Split View", "Balance Split View"]),
        "find:": .init(triggers: ["Find in Page"]),
        "findNext:": .init(triggers: ["Next"]),
        "findPrevious:": .init(triggers: ["Previous"]),
        "focusSidebar:": .init(triggers: [], bump: 0.5),
        "forceReload:": .init(triggers: ["Force Reload", "Force Refresh"]),
        "goBack:": .init(triggers: ["Go Back", "Back", "Navigate Back"]),
        "goForward:": .init(triggers: ["Go Forward", "Forward", "Navigate Forward"]),
        "hide:": .init(triggers: ["Hide Parc"]),
        "hideOtherApplications:": .init(triggers: ["Hide Others"]),
        "history:": .init(triggers: ["Show History", "History"]),
        "importFromBrowser:": .init(triggers: ["Import Bookmarks", "Import Settings", "Import Logins", "Import Passwords", "Transfer Bookmarks", "Transfer Settings", "Transfer Logins", "Transfer Passwords", "Bookmarks"]),
        "inspectElements:": .init(triggers: ["Inspect Element"]),
        "javaScriptConsole:": .init(triggers: ["Toggle console", "Console", "Javascript Console", "JS console"]),
        "jumpToSelection:": .init(triggers: ["Jump to Selected", "Selection"]),
        "manageExtensions:": .init(triggers: ["Manage Extensions", "Extensions", "Plugins", "Chrome Extensions"]),
        "narrowSplitPane:": .init(triggers: ["Narrow Split View", "Shrink Split View", "Smaller Pane", "Shorter Pane"]),
        "networkInspector:": .init(triggers: ["Network Inspector"]),
        "newBlankWindow:": .init(triggers: ["Create Window"]),
        "newIncognitoWindow:": .init(triggers: ["Create Incognito Window", "New Private Window", "Incognito"]),
        "newWindow:": .init(triggers: ["Create Window", "Copy Window", "Duplicate Window"]),
        "nextSpace:": .init(triggers: ["Focus Next Space"]),
        "openSpaceManager:": .init(triggers: ["Space Management", "Organize", "Toggle Space Manager", "View Spaces"]),
        "pasteAsPlainText:": .init(triggers: ["Paste Without Formatting"]),
        "previousSpace:": .init(triggers: ["Focus Previous Space"]),
        "printPage:": .init(triggers: ["Print Page"]),
        "quitMenu:": .init(triggers: ["Quit App"]),
        "reload:": .init(triggers: ["Reload Page"]),
        "resetTab:": .init(triggers: ["Reset Tab"]),
        "restoreTab:": .init(triggers: ["Reopen Closed Tab"]),
        "revealCurrentTabInSidebar:": .init(triggers: ["Show Tab in Sidebar", "Reveal in Sidebar", "Go to Current Tab"]),
        "savePage:": .init(triggers: ["Save Page", "Save File"]),
        "separateSplitPane:": .init(triggers: ["Separate from split view", "separate tab"]),
        "setAsDefaultBrowser:": .init(triggers: ["Default Browser"]),
        "sharePage:": .init(triggers: ["Share"]),
        "showDocuments:": .init(triggers: ["Easels", "Notes"]),
        "showEssentialShortcuts:": .init(triggers: ["Essential Keyboard Shortcuts", "keyboard", "shortcuts"], bump: 0.1),
        "showNotesFolder:": .init(triggers: ["Show Notes Folder", "Reveal Notes", "Open Notes Folder"], bump: 1.5),
        "showReleaseNotes:": .init(triggers: ["Changelog", "Whats new", "What's new", "parc updates"]),
        "split:": .init(triggers: ["Add Split View", "Split View", "Create Split View Pane", "New Split View", "Split"]),
        "splitThisPane:": .init(triggers: ["Split Pane", "Stack Split View", "Add Pane Below", "Add Pane to the Right", "Divide Pane"]),
        "toggleShowToolbar:": .init(triggers: ["Toggle Hide Show Toolbar"]),
        "toggleCollapsedPinnedIcons:": .init(triggers: ["Pinned Icons", "Pinned Favicons", "Screen Sharing"]),
        "toggleDeveloperMode:": .init(triggers: ["Developer Mode", "Enable Developer Mode", "Disable Developer Mode"]),
        "toggleFairPlayIdentity:": .init(triggers: ["Safari Identity", "Chrome Identity", "FairPlay"]),
        "toggleFullScreen:": .init(triggers: ["Enter Full Screen", "Exit Full Screen", "Full Screen", "Toggle Full Screen"]),
        "togglePin:": .init(triggers: ["save"]),
        "togglePinnedSection:": .init(triggers: ["Pinned Section", "Pinned Tabs", "Fold Pinned", "Toggle Pinned"]),
        "toggleSidebar:": .init(triggers: ["Toggle Sidebar"], bump: 0.5),
        "useSelectionForFind:": .init(triggers: ["Find Selection", "Find Selected"]),
        "viewLibrary:": .init(triggers: ["Library"]),
        "viewSource:": .init(triggers: ["View Source"]),
        "widenSplitPane:": .init(triggers: ["Widen Split View", "Grow Split View", "Bigger Pane", "Taller Pane"]),
    ]
}
