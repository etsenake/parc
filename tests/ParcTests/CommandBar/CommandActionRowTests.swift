import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct CommandActionRowTests {
    enum Kind: CaseIterable { case favorite, folder, move, space }

    @MainActor private func makeRow(_ kind: Kind, enabled: Bool = true, width: CGFloat = 745) throws -> CommandResultCell {
        _ = NSApplication.shared
        var state = BrowserState.initial()
        let profile = try #require(state.profiles.first)
        var space = try #require(state.spaces.first)
        space.name = "Home"
        state.spaces[0] = space
        let second = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        state.spaces.append(second)
        let projects = BrowserFolder(id: UUID(), spaceID: space.id, name: "Projects")
        let cafe = BrowserFolder(id: UUID(), spaceID: space.id, name: "Café", parentID: projects.id)
        let destination = BrowserFolder(id: UUID(), spaceID: second.id, name: "Destination")
        state.folders = [projects, cafe, destination]
        let tab = BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id, url: "https://example.test/",
            title: "Original", kind: .today, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "", savedTitle: "")
        state.tabs = [tab]
        let row: CommandResultCell
        switch kind {
        case .favorite:
            let action = try #require(CommandBarFavoriteAction(items: [.tab(tab.id)], spaceID: space.id, profileID: profile.id, state: state))
            row = CommandResultCell(title: action.title, detail: "", accessory: "", isTab: false,
                                    icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil), enabled: enabled)
        case .folder:
            let action = try #require(CommandBarFolderAction.snapshot(state: state, profileID: profile.id).first { $0.folderID == cafe.id })
            row = CommandResultCell(title: action.title, detail: action.detail, accessory: "", isTab: false,
                                    icon: NSImage(systemSymbolName: "folder", accessibilityDescription: nil), enabled: enabled, folderAction: action)
        case .move:
            let source = try #require(CommandBarFolderMoveSource(items: [.tab(tab.id)], spaceID: space.id, profileID: profile.id, state: state))
            let action = try #require(CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == destination.id })
            row = CommandResultCell(title: action.title, detail: action.folder.detail, accessory: "", isTab: false,
                                    icon: nil, enabled: enabled, folderAction: action.folder)
        case .space:
            let action = try #require(CommandBarSpaceAction.snapshot(spaces: state.spaces, profiles: [profile]).last)
            row = CommandResultCell(title: action.title, detail: action.detail, accessory: "", isTab: false,
                                    icon: nil, enabled: enabled, spaceAction: action)
        }
        row.frame = NSRect(x: 0, y: 0, width: width, height: 50)
        row.layoutSubtreeIfNeeded()
        return row
    }

    @Test(arguments: [(Kind.favorite, "Favorite Tab"), (.folder, "Open, Café, Home › Projects"),
                      (.move, "Pin to, Destination"), (.space, "Focus on, Home, Space 2")])
    @MainActor func voiceOverNamesTheOriginalAction(kind: Kind, label: String) throws {
        let row = try makeRow(kind)
        #expect(row.accessibilityLabel()?.hasPrefix(label) == true)
    }

    @Test(arguments: Kind.allCases, [true, false])
    @MainActor func onlyAnAvailableRowDispatchesItsAction(kind: Kind, enabled: Bool) throws {
        let row = try makeRow(kind, enabled: enabled)
        var dispatches = 0
        row.onPress = { dispatches += 1; return true }
        #expect(row.accessibilityPerformPress() == enabled)
        #expect(dispatches == (enabled ? 1 : 0))
    }

    @Test(arguments: Kind.allCases)
    @MainActor func aHighlightedActionExposesSelectionToVoiceOver(kind: Kind) throws {
        let row = try makeRow(kind)
        row.setSelected(true)
        #expect(row.isAccessibilitySelected())
    }

    @Test(arguments: [Kind.folder, .move, .space], [220.0, 320.0, 745.0])
    @MainActor func anActionRowFitsItsViewport(kind: Kind, width: Double) throws {
        let row = try makeRow(kind, width: width)
        let overhang = row.subviews.filter { !$0.isHidden && ($0.frame.minX < 0 || $0.frame.maxX > width) }
        #expect(overhang.isEmpty)
    }
}
