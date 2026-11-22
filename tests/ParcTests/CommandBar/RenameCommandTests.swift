import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

struct RenameCommandTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let first: UUID
        let second: UUID
        var state: BrowserState { store.state }
        var space: UUID { state.activeSpaceID }
        var profile: UUID { state.spaces.first { $0.id == space }!.profileID }

        init() throws {
            store = try BrowserStore(directory: directory)
            store.scheduleDeferredSave = { _, _ in }
            first = store.openResolvedURL(URL(string: "https://first.test/")!)
            second = store.openResolvedURL(URL(string: "https://second.test/")!)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func target(_ selection: [UUID], state snapshot: BrowserState? = nil) -> BrowserTab? {
            SidebarTabTitle.currentRenameTab(state: snapshot ?? state, spaceID: space, profileID: profile,
                                            selectedTabIDs: selection)
        }
    }

    @Test @MainActor func renameUsesTheWindowSelection() throws {
        let fixture = try Fixture()
        #expect(fixture.state.selectedTabIDs == [fixture.second])
        #expect(fixture.target([fixture.first])?.id == fixture.first)
    }

    enum Selection: CaseIterable { case none, split, missing }

    @Test(arguments: Selection.allCases)
    @MainActor func anAmbiguousOrMissingSelectionHasNoRenameTarget(selection: Selection) throws {
        let fixture = try Fixture()
        let ids: [UUID]
        switch selection {
        case .none: ids = []
        case .split: ids = [fixture.first, fixture.second]
        case .missing: ids = [UUID()]
        }
        #expect(fixture.target(ids) == nil)
    }

    enum Change: CaseIterable { case favorite, archived, space, profile, document, splitChild }

    @Test(arguments: Change.allCases)
    @MainActor func itemsWithOtherOwnersAreUnavailableForTabRename(change: Change) throws {
        let fixture = try Fixture()
        var state = fixture.state
        let index = try #require(state.tabs.firstIndex { $0.id == fixture.first })
        switch change {
        case .favorite: state.tabs[index].kind = .favorite
        case .archived: state.tabs[index].archivedAt = .distantPast
        case .space: state.tabs[index].spaceID = UUID()
        case .profile: state.tabs[index].profileID = UUID()
        case .document: state.tabs[index].url = "parc://note/" + UUID().uuidString
        case .splitChild:
            state.splitLayouts.append(BrowserSplitLayout(spaceID: fixture.space, tabIDs: [fixture.first, fixture.second],
                                                        widthFactors: [0.5, 0.5]))
        }
        #expect(fixture.target([fixture.first], state: state) == nil)
    }

    @Test @MainActor func savingTheRenameKeepsTheOtherWindowSelection() throws {
        let fixture = try Fixture()
        let before = fixture.state
        let target = try #require(fixture.target([fixture.first]))
        try fixture.store.saveSidebarTitle(target, title: "Window one")
        #expect(fixture.state.tab(fixture.first)?.customTitle == "Window one")
        #expect(fixture.state.tab(fixture.second)?.customTitle == nil)
        #expect(fixture.state.selectedTabIDs == before.selectedTabIDs)
        #expect(fixture.state.history == before.history)
    }
}

extension RenameCommandTests {
    @Test(arguments: [false, true])
    @MainActor func theHiddenRenameActionAppearsOnlyWhileItsOriginalMenuOwnsIt(detached: Bool) throws {
        _ = NSApplication.shared
        let menu = NSMenu(title: "Tabs")
        let registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
        let id = "renameCurrentItem:"
        let item = NSMenuItem(title: "Rename Current Tab…", action: NSSelectorFromString(id), keyEquivalent: "")
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        menu.addItem(item)
        registry.register(item, group: "Tabs")
        if detached { menu.removeItem(item) }
        let window = CommandBarTestSupport.borderlessWindow()
        #expect(registry.shortcut(for: id) == nil)
        #expect(registry.menuCommands(in: window).contains { $0.id == id } == !detached)
    }

    @Test @MainActor func aCustomRenameBindingPersistsAndCanReturnToUnassigned() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let menu = NSMenu(title: "Tabs")
        let registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
        registry.configure(directory: directory)
        let id = "renameCurrentItem:"
        let item = NSMenuItem(title: "Rename Current Tab…", action: NSSelectorFromString(id), keyEquivalent: "")
        menu.addItem(item)
        registry.register(item, group: "Tabs")
        let chord = KeyboardShortcut(key: "r", flags: [.command, .option])
        try registry.set(chord, for: id)
        try registry.setPriority(.useBoth, for: id)
        registry.configure(directory: directory)
        #expect(item.keyEquivalent == chord.key)
        #expect(registry.priority(for: id) == .useBoth)
        try registry.reset(id)
        #expect(registry.shortcut(for: id) == nil)
    }
}
