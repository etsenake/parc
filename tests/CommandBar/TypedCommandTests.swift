import Foundation

@main @MainActor
struct TypedCommandTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        typealias Command = CommandBarTypedCommand
        let space = UUID()
        let titles: [(Command.Kind, String)] = [
            (.undo("New Folder…"), "Undo New Folder…"), (.redo("Update Appearance"), "Redo Update Appearance"),
            (.pinToSpace(space, name: "Work"), "Pin to Work"), (.pinToNewFolder, "Pin to New Folder"),
            (.replacePinWithCurrentPage, "Replace Pin with Current Page"), (.duplicateCurrentTab, "Duplicate Current Tab"),
            (.convertSplit(toVertical: true), "Convert to Vertical Split View"),
            (.convertSplit(toVertical: false), "Convert to Horizontal Split View"),
            (.addSplit(.left), "Add Left Split"), (.addSplit(.right), "Add Right Split"),
            (.addSplit(.top), "Add Top Split"), (.addSplit(.bottom), "Add Bottom Split"),
            (.newWebDocument(CommandBarWebDocument.catalog[0]), "New Google Doc"),
            (.searchSettings, "Search Settings"), (.airTrafficControl, "Air Traffic Control"),
        ]
        for (kind, title) in titles { check(Command(kind: kind).title == title, "Recovered title \(title)") }
        check(Set(titles.map { Command(kind: $0.0).id }).count == titles.count, "Each command has its own row identity")
        check(Command(kind: .pinToSpace(space, name: "A")).id == Command(kind: .pinToSpace(space, name: "B")).id,
              "A renamed Space keeps its row identity")
        check(Command(kind: .undo("A")) != Command(kind: .undo("B")), "A different Undo step is a different command")

        check(Command(kind: .pinToSpace(space, name: "Work")).matches(query: "move work"), "Move finds Pin to Space")
        check(Command(kind: .pinToNewFolder).matches(query: "pin new"), "Title words match")
        check(Command(kind: .airTrafficControl).matches(query: "air traffic"), "Air Traffic Control matches")
        check(Command(kind: .airTrafficControl).matches(query: "routes"), "Air Traffic Control matches its routes")
        check(Command(kind: .newWebDocument(CommandBarWebDocument.catalog[5])).matches(query: "NOTION"), "Case folded")
        check(!Command(kind: .searchSettings).matches(query: ""), "Empty query is the provider's choice, not a match")
        check(!Command(kind: .searchSettings).matches(query: "split"), "Unrelated words do not match")

        check(Command.commandBarTitle(forMenuCommand: "toggleSidebar:", menuTitle: "Show / Hide Sidebar") == "Toggle Sidebar", "Toggle Sidebar")
        check(Command.commandBarTitle(forMenuCommand: "resetTab:", menuTitle: "Reset Tab to Original URL") == "Reset Tab", "Reset Tab")
        check(Command.commandBarTitle(forMenuCommand: "split:", menuTitle: "Add Split View") == "Add Split View", "Add Split View keeps its menu title (side by side)")
        check(Command(kind: .addVerticalSplit).title == "Add Vertical Split View", "the stacked add")
        check(Command.commandBarTitle(forMenuCommand: "createNote:", menuTitle: "New Note") == "New Parc Note", "New Note takes Parc's name")
        check(Command.commandBarSearchText(forMenuCommand: "createNote:").contains("arc note"), "\"arc note\" still finds it")
        check(Command.commandBarTitle(forMenuCommand: "newTab:", menuTitle: "New Tab") == "New Tab", "Other menu titles are unchanged")

        check(CommandBarWebDocument.catalog.count == 11, "Eleven recovered document types")
        check(CommandBarWebDocument.catalog.map(\.url).contains("https://make.page"), "Confluence uses make.page")
        check(CommandBarWebDocument.available(visitedHosts: []).isEmpty, "No engagement offers no document")
        let google = CommandBarWebDocument.available(visitedHosts: ["drive.google.com"]).map(\.title)
        check(google == ["Google Doc", "Google Sheet", "Google Slide"], "Drive engagement offers its three types in order")
        check(CommandBarWebDocument.available(visitedHosts: ["team.figma.com"]).map(\.title) == ["Figma Document", "FigJam"],
              "Subdomains count as engagement")
        check(CommandBarWebDocument.available(visitedHosts: ["notfigma.com"]).isEmpty, "A suffix that is not a subdomain does not")

        check(Command.splitCommands(paneCount: 1, vertical: false).map(\.title)
              == ["Add Left Split", "Add Right Split", "Add Top Split", "Add Bottom Split", "Add Vertical Split View"],
              "One pane offers every edge and the stacked add")
        check(Command.splitCommands(paneCount: 2, vertical: false).map(\.title)
              == ["Add Right Split", "Add Left Split", "Convert to Vertical Split View"], "Horizontal split")
        check(Command.splitCommands(paneCount: 3, vertical: true).map(\.title)
              == ["Add Top Split", "Add Bottom Split", "Add Vertical Split View", "Convert to Horizontal Split View"], "Vertical split")
        check(Command.splitCommands(paneCount: 4, vertical: true).map(\.title) == ["Convert to Horizontal Split View"],
              "A full split adds nothing")
        check(Command.splitCommands(paneCount: 0, vertical: false).isEmpty, "No pane, no split command")

        let panes = Command.SettingsPane.allCases
        check(panes.map(\.title) == ["Settings", "Open General Preferences", "Open Space Preferences",
            "Edit Keyboard Shortcuts", "Open Link Preferences", "Open App Icon", "Open Advanced Preferences"],
              "Settings pane titles in order")
        check(Command(kind: .settingsPane(.shortcuts)).matches(query: "hotkeys"), "Pane trigger phrase matches")
        check(Command(kind: .settingsPane(.general)).matches(query: "autofill"), "General finds autofill")
        check(Command(kind: .settingsPane(.account)).matches(query: "membership"), "Account finds its card")
        check(!Command(kind: .settingsPane(.links)).matches(query: "little arc"), "Words for the excluded mini browser window are not offered")
        check(Command(kind: .settingsPane(.general)).candidateBump == 0.6 && Command(kind: .settingsPane(.links)).candidateBump == 0.5,
              "Recovered pane bumps")
        check(Command(kind: .searchSettings).candidateBump == nil, "No invented bump")
        check(!panes.contains { $0.title.contains("Max") || $0.title.contains("Staff") }, "AI and staff panes excluded")

        check(Command(kind: .appearance(.dark)).title == "Switch to Dark Mode", "Dark title")
        check(Command(kind: .appearance(.dark)).matches(query: "night"), "Dark trigger")
        check(Command(kind: .appearance(.automatic)).title == "Switch to Automatic Appearance", "Automatic title")

        check(Command(kind: .copyAppInfo).title == "Copy Parc Info" && Command(kind: .copyAppInfo).symbol == "list.clipboard",
              "Copy Parc Info title and icon")
        check(Command(kind: .revealAppData).title == "Reveal Parc Data" && Command(kind: .revealAppData).candidateBump == 0.1,
              "Reveal Parc Data title and bump")
        check(Command(kind: .copyAppInfo).matches(query: "copy arc info"), "\"copy arc info\" finds Copy Parc Info")
        check(Command(kind: .capturePortrait).title == "Capture in Portrait Mode" && Command(kind: .capturePortrait).symbol == "camera.macro",
              "Portrait title and icon")
        check(Command(kind: .capturePortrait).matches(query: "screenshot") && Command(kind: .capturePortrait).candidateBump == nil,
              "Portrait triggers, no bump")

        check(Command(kind: .openTaskManager).title == "Open Task Manager"
              && Command(kind: .openTaskManager).symbol == "exclamationmark.triangle", "Task Manager title and icon")
        check(Command(kind: .openTaskManager).matches(query: "cpu") && Command(kind: .openTaskManager).matches(query: "memory"),
              "Task Manager triggers")

        let foreignPin = Command(kind: .pinToSpace(space, name: "Work", position: 3))
        check(foreignPin.title == "Pin to Work" && foreignPin.detail == "Space 3", "Duplicate names show their position")
        check(!foreignPin.matches(query: "pin personal"), "No profile name finds it")
        check(Command(kind: .pinToSpace(space, name: "Work")).detail.isEmpty, "A unique name shows no label")
        check(Command(kind: .settingsPane(.profiles)).matches(query: "profile"), "Profile stays a hidden keyword for Space Preferences")

        check(CommandBarMenuItemInfo.candidateBump(forMenuCommand: "toggleSidebar:") == 0.5, "Sidebar bump")
        check(CommandBarMenuItemInfo.candidateBump(forMenuCommand: "exportNotes:") == 1.5, "Export Notes bump")
        check(CommandBarMenuItemInfo.candidateBump(forMenuCommand: "newTab:") == nil, "No bump without data")
        check(CommandBarMenuItemInfo.searchText(forMenuCommand: "clearToday:").contains("Close Unpinned Tabs"), "Clear Today triggers")
        check(CommandBarMenuItemInfo.searchText(forMenuCommand: "showReleaseNotes:").contains("Changelog"), "Release Notes triggers")
        check(Command.commandBarSearchText(forMenuCommand: "createEasel:").contains("Mood Board"), "Easel trigger")
        check(Command.commandBarTitle(forMenuCommand: "sharePage:", menuTitle: "Share…") == "Share URL", "Share's Type Travel title")
        check(CommandBarMenuItemInfo.rankingBump(1.5) < 0.95 - 0.85, "The largest bump can't lift an exact command over an exact tab")

        let profile = BrowserProfile(id: UUID(), name: "Original")
        let origin = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        func tab(_ kind: TabKind, url: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: origin.id, profileID: profile.id, url: url, title: "Current", kind: kind,
                       createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
                       savedURL: "https://home.test/", savedTitle: "Home")
        }
        let pinned = tab(.pinned, url: "https://away.test/page"), today = tab(.today, url: "https://away.test/today")
        let atHome = tab(.pinned, url: "https://home.test/")
        var state = BrowserState(profiles: [profile], spaces: [origin], activeSpaceID: origin.id)
        state.tabs = [pinned, today, atHome]; state.selectedTabIDs = [pinned.id]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-typed-commands-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        check(!store.replaceSavedHome(today, url: today.url, title: "Today"), "A Today tab has no pin to replace")
        check(!store.replaceSavedHome(atHome, url: atHome.url, title: "Home"), "A pin at its home is unchanged")
        check(!store.replaceSavedHome(pinned, url: "parc://note/\(UUID().uuidString)", title: "Note"), "A local document cannot become a web home")
        check(store.replaceSavedHome(pinned, url: pinned.url, title: "Away Page"), "An away pin takes its current page")
        let replaced = store.state.tabs.first { $0.id == pinned.id }
        check(replaced?.savedURL == pinned.url && replaced?.savedTitle == "Away Page" && replaced?.kind == .pinned,
              "Home replaced in place; identity and kind kept")
        check(replaced?.resetDestination == nil, "The replaced pin is now at home")
        check(!store.replaceSavedHome(pinned, url: pinned.url, title: "Again"), "A stale expected record is refused")
        let settingsPin = tab(.pinned, url: "chrome://settings/searchEngines")
        var withSettings = store.state; withSettings.tabs.append(settingsPin)
        try encoder.encode(withSettings).write(to: directory.appendingPathComponent("session.json"))
        let settingsStore = try BrowserStore(directory: directory)
        let loaded = settingsStore.state.tabs.first { $0.id == settingsPin.id }!
        check(settingsStore.replaceSavedHome(loaded, url: "chrome://settings/searchEngines", title: "Search engines"),
              "A WebUI page can become a pin's home")
        check(settingsStore.state.tabs.first { $0.id == settingsPin.id }?.savedURL == "parc://settings/searchEngines",
              "WebUI homes are saved under their public parc:// address")
        let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        var spaces = BrowserState(profiles: [profile], spaces: [origin, away], activeSpaceID: origin.id)
        spaces.tabs = [today]; spaces.selectedTabIDs = [today.id]
        if let source = SidebarHierarchySnapshot(state: spaces, spaceID: origin.id, profileID: profile.id),
           let target = SidebarHierarchySnapshot(state: spaces, spaceID: away.id, profileID: profile.id),
           var move = SidebarSpaceMove(items: [.tab(today.id)], from: source, to: target, state: spaces) {
            let kept = move.applying(to: spaces)?.tabs.first { $0.id == today.id }
            check(kept?.kind == .today && kept?.spaceID == away.id, "A sidebar drag keeps its Today section")
            move.pinsToday = true
            let pinnedState = move.applying(to: spaces)
            let moved = pinnedState?.tabs.first { $0.id == today.id }
            check(moved?.kind == .pinned && moved?.spaceID == away.id, "Pin to [Space] moves into Pinned")
            check(moved?.savedURL == today.url && moved?.savedTitle == today.title, "The current page becomes its saved home")
            let pinnedKey = SidebarContainerLocation(spaceID: away.id, folderID: nil, section: .pinned).key
            check(pinnedState?.sidebarItemOrder[pinnedKey]?.contains(.tab(today.id)) == true, "Ordered in the destination's Pinned list")
        } else { check(false, "Space move preflight") }
        print("TypedCommandTests: \(count) checks passed")
    }
}
