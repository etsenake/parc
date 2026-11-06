import Foundation

///
/// document's creation URL, title and the sites whose engagement offers it.
///
struct CommandBarWebDocument: Hashable, Sendable {
    let title: String
    let url: String
    let domains: [String]

    static let catalog: [CommandBarWebDocument] = [
        .init(title: "Google Doc", url: "https://doc.new", domains: ["drive.google.com", "docs.google.com"]),
        .init(title: "Google Sheet", url: "https://sheet.new", domains: ["drive.google.com", "sheets.google.com"]),
        .init(title: "Google Slide", url: "https://slide.new", domains: ["drive.google.com", "slides.google.com"]),
        .init(title: "Figma Document", url: "https://figma.new", domains: ["figma.com", "www.figma.com"]),
        .init(title: "FigJam", url: "https://figjam.new", domains: ["figma.com"]),
        .init(title: "Notion Page", url: "https://notion.so/new", domains: ["notion.so", "www.notion.so"]),
        .init(title: "Repl", url: "https://replit.com/new", domains: ["replit.com"]),
        .init(title: "Google Meet", url: "https://meet.new", domains: ["meet.google.com"]),
        .init(title: "Linear Issue", url: "https://linear.app/new", domains: ["linear.app"]),
        .init(title: "Word Doc", url: "https://word.new", domains: ["microsoft365.com", "onedrive.live.com"]),
        .init(title: "Confluence Page", url: "https://make.page", domains: ["confluence.com"]),
    ]

    ///
    /// visit to one of them (or a subdomain) in the Profile's own history.
    static func available(visitedHosts: Set<String>) -> [CommandBarWebDocument] {
        catalog.filter { document in
            document.domains.contains { domain in
                visitedHosts.contains { $0 == domain || $0.hasSuffix("." + domain) }
            }
        }
    }
}

///
///
struct CommandBarTypedCommand: Hashable, Sendable {
    enum SplitEdge: Hashable, Sendable { case left, right, top, bottom }
    ///
    /// lists them: Account, General, Profiles, Shortcuts, Links, App Icon,
    ///
    enum SettingsPane: CaseIterable, Hashable, Sendable {
        case account, general, profiles, shortcuts, links, appIcon, advanced

        ///
        var title: String {
            switch self {
            case .account: return "Settings"
            case .general: return "Open General Preferences"
            case .profiles: return "Open Profile Preferences"
            case .shortcuts: return "Edit Keyboard Shortcuts"
            case .links: return "Open Link Preferences"
            case .appIcon: return "Open App Icon"
            case .advanced: return "Open Advanced Preferences"
            }
        }

        ///
        /// "arc card". Links' "mini browser", "little browser" and "little arc"
        ///
        var triggerPhrases: [String] {
            switch self {
            case .account: return ["membership card", "id card", "arc card", "parc card", "open account preferences"]
            case .general: return ["autofill", "credit cards", "general"]
            case .profiles: return ["profile"]
            case .shortcuts: return ["shortcuts", "open shortcuts", "edit keyboard shortcuts", "key bindings",
                                     "hotkeys", "keyboard shortcuts", "hot keys"]
            case .links: return []
            case .appIcon: return ["app icon", "custom app icon"]
            case .advanced: return ["advanced"]
            }
        }

        ///
        var bump: Double { self == .general ? 0.6 : 0.5 }
    }
    ///
    /// triggers in its MainMenu nib (`arcTypeTravelTitle`) but no binding ID.
    enum Appearance: CaseIterable, Hashable, Sendable {
        case light, dark, automatic

        var title: String {
            switch self {
            case .light: return "Switch to Light Mode"
            case .dark: return "Switch to Dark Mode"
            case .automatic: return "Switch to Automatic Appearance"
            }
        }
        var triggerPhrases: [String] {
            switch self {
            case .light: return ["Switch Light Mode", "Light Mode"]
            case .dark: return ["Switch Dark Mode", "Dark Mode", "Night Mode"]
            case .automatic: return ["Switch Automatic Mode", "Automatic Mode"]
            }
        }
        /// The menu item's selector, whose owner records the Undo step.
        var selectorName: String {
            switch self {
            case .light: return "setLightAppearance:"
            case .dark: return "setDarkAppearance:"
            case .automatic: return "setAutomaticAppearance:"
            }
        }
    }
    enum Kind: Hashable, Sendable {
        case undo(String), redo(String)
        /// Another Profile's Space carries that Profile's name for its row.
        case pinToSpace(UUID, name: String, profileName: String? = nil)
        case pinToNewFolder
        case replacePinWithCurrentPage
        case duplicateCurrentTab
        case convertSplit(toVertical: Bool)
        case addSplit(SplitEdge)
        ///
        ///
        case addVerticalSplit
        case newWebDocument(CommandBarWebDocument)
        case searchSettings
        case airTrafficControl
        case settingsPane(SettingsPane)
        case appearance(Appearance)
        ///
        /// File's Capture in Portrait Mode, with their MainMenu nib data.
        case copyAppInfo, revealAppData, capturePortrait
        /// Help → Troubleshooting → Open Task Manager: Chromium's task manager.
        case openTaskManager
    }

    let kind: Kind

    ///
    var candidateBump: Double? {
        switch kind {
        case .settingsPane(let pane): return pane.bump
        case .copyAppInfo, .revealAppData: return 0.1
        default: return nil
        }
    }

    var id: String {
        switch kind {
        case .undo: return "typed:undo"
        case .redo: return "typed:redo"
        case .pinToSpace(let id, _, _): return "typed:pin-to-space:" + id.uuidString
        case .pinToNewFolder: return "typed:pin-to-new-folder"
        case .replacePinWithCurrentPage: return "typed:replace-pin"
        case .duplicateCurrentTab: return "typed:duplicate-current-tab"
        case .convertSplit(let vertical): return vertical ? "typed:convert-vertical" : "typed:convert-horizontal"
        case .addSplit(let edge): return "typed:add-split:\(edge)"
        case .addVerticalSplit: return "typed:add-vertical-split"
        case .newWebDocument(let document): return "typed:new-document:" + document.url
        case .searchSettings: return "typed:search-settings"
        case .airTrafficControl: return "typed:air-traffic-control"
        case .settingsPane(let pane): return "typed:settings-pane:\(pane)"
        case .appearance(let appearance): return "typed:appearance:\(appearance)"
        case .copyAppInfo: return "typed:copy-app-info"
        case .revealAppData: return "typed:reveal-app-data"
        case .capturePortrait: return "typed:capture-portrait"
        case .openTaskManager: return "typed:open-task-manager"
        }
    }

    var title: String {
        switch kind {
        case .undo(let name): return "Undo " + name
        case .redo(let name): return "Redo " + name
        case .pinToSpace(_, let name, _): return "Pin to " + name
        case .pinToNewFolder: return "Pin to New Folder"
        case .replacePinWithCurrentPage: return "Replace Pin with Current Page"
        case .duplicateCurrentTab: return "Duplicate Current Tab"
        case .convertSplit(let vertical): return vertical ? "Convert to Vertical Split View" : "Convert to Horizontal Split View"
        case .addSplit(.left): return "Add Left Split"
        case .addSplit(.right): return "Add Right Split"
        case .addSplit(.top): return "Add Top Split"
        case .addSplit(.bottom): return "Add Bottom Split"
        case .addVerticalSplit: return "Add Vertical Split View"
        case .newWebDocument(let document): return "New " + document.title
        case .searchSettings: return "Search Settings"
        case .airTrafficControl: return "Air Traffic Control"
        case .settingsPane(let pane): return pane.title
        case .appearance(let appearance): return appearance.title
        case .copyAppInfo: return "Copy Parc Info"
        case .revealAppData: return "Reveal Parc Data"
        case .capturePortrait: return "Capture in Portrait Mode"
        case .openTaskManager: return "Open Task Manager"
        }
    }

    /// Another Profile's name beside its Space, as Focus on Space shows it.
    var detail: String {
        if case .pinToSpace(_, _, let profile?) = kind { return profile }
        return ""
    }

    var symbol: String {
        switch kind {
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .pinToSpace: return "pin"
        case .pinToNewFolder: return "folder.badge.plus"
        case .replacePinWithCurrentPage: return "pin"
        case .duplicateCurrentTab: return "plus.square.on.square"
        case .convertSplit(let vertical): return vertical ? "rectangle.split.2x1" : "rectangle.split.1x2"
        case .addSplit(.left), .addSplit(.right): return "rectangle.split.2x1"
        case .addSplit(.top), .addSplit(.bottom), .addVerticalSplit: return "rectangle.split.1x2"
        case .newWebDocument: return "doc.badge.plus"
        case .searchSettings: return "magnifyingglass"
        case .airTrafficControl: return "arrow.triangle.branch"
        case .settingsPane(.shortcuts): return "keyboard"
        case .settingsPane: return "gearshape"
        case .appearance(.light): return "sun.max"
        case .appearance(.dark): return "moon"
        case .appearance(.automatic): return "circle.lefthalf.filled"
        case .copyAppInfo, .revealAppData: return "list.clipboard"
        case .capturePortrait: return "camera.macro"
        case .openTaskManager: return "exclamationmark.triangle"
        }
    }

    ///
    /// action: Pin to [Space] "moves to Pinned", Pin to New Folder "creates a
    /// new list". Those words also find the command, as Parc's folder moves do.
    /// Phrases beside the title that find the command; triggers stay whole
    /// so an exact phrase ranks as an exact match.
    var searchPhrases: [String] {
        switch kind {
        case .pinToSpace(_, _, let profile): return ["move space"] + (profile.map { [$0] } ?? [])
        case .pinToNewFolder: return ["move folder create"]
        case .replacePinWithCurrentPage: return ["pinned tab url"]
        case .duplicateCurrentTab: return ["copy"]
        case .convertSplit, .addSplit, .addVerticalSplit: return ["split view pane"]
        case .newWebDocument: return ["create document"]
        case .searchSettings: return ["search engines"]
        case .airTrafficControl: return ["links routes route"]
        case .settingsPane(let pane): return pane.triggerPhrases
        case .appearance(let appearance): return appearance.triggerPhrases
        //
        case .copyAppInfo: return ["arc info"]
        case .revealAppData: return ["arc data"]
        case .capturePortrait: return ["Screenshot in Portrait Mode", "Capture Portrait", "Portrait Mode", "Screenshot"]
        case .openTaskManager: return ["Task", "Manager", "Task Manager", "Cpu", "Memory: RAM"]
        default: return []
        }
    }

    func matches(query: String) -> Bool {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        let text = ([title] + searchPhrases).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return !words.isEmpty && words.allSatisfy { text.contains($0) }
    }

    /// Texts ranking matches one by one: the title, each phrase, and the title
    /// with every phrase for queries that mix their words.
    var rankingTexts: [String] {
        searchPhrases.isEmpty ? [title] : [title] + searchPhrases + [([title] + searchPhrases).joined(separator: " ")]
    }

    /// A menu command's ranking texts beyond its titles: each trigger phrase.
    static func rankingPhrases(forMenuCommand id: String) -> [String] {
        (CommandBarMenuItemInfo.info(forMenuCommand: id)?.triggers ?? []) + (id == "createNote:" ? ["New Arc Note"] : [])
    }

    ///
    /// existing menu item (cases 17, 20 and 31). The menu bar keeps its own
    ///
    /// The menu item's own `arcTypeTravelTitle` (Share URL) comes from
    /// `CommandBarCommandPresentation`, the one source of those titles.
    static func commandBarTitle(forMenuCommand id: String, menuTitle: String) -> String {
        switch id {
        case "toggleSidebar:": return "Toggle Sidebar"
        case "resetTab:": return "Reset Tab"
        case "createNote:": return "New Parc Note"
        default: return CommandBarCommandPresentation.title(commandID: id, title: menuTitle)
        }
    }

    ///
    ///
    static func commandBarSearchText(forMenuCommand id: String) -> String {
        let triggers = CommandBarMenuItemInfo.searchText(forMenuCommand: id)
        return id == "createNote:" ? triggers + " new arc note" : triggers
    }

    /// Single-pane Add offers all four edges; a split offers its own axis
    ///
    static func splitCommands(paneCount: Int, vertical: Bool) -> [CommandBarTypedCommand] {
        guard (1...4).contains(paneCount) else { return [] }
        let edges: [SplitEdge]
        if paneCount == 1 { edges = [.left, .right, .top, .bottom] }
        else { edges = vertical ? [.top, .bottom] : [.right, .left] }
        var commands = paneCount < 4 ? edges.map { CommandBarTypedCommand(kind: .addSplit($0)) } : []
        if paneCount < 4 && edges.contains(.bottom) { commands.append(.init(kind: .addVerticalSplit)) }
        if paneCount > 1 { commands.append(.init(kind: .convertSplit(toVertical: !vertical))) }
        return commands
    }
}
