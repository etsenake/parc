import Foundation
import Testing
@testable import ParcCore

enum OriginalSplitDropTestsSupport {
    @MainActor final class Fixture {
        let root: URL
        let store: BrowserStore
        let a: UUID, b: UUID, c: UUID
        let original: BrowserState
        let profile: UUID, space: UUID
        let home = UUID(), bHome = UUID()
        let now = Date(timeIntervalSince1970: 1234)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-original-split-" + UUID().uuidString)
            let store = try BrowserStore(directory: root)
            let a = store.open("https://saved.invalid", kind: .pinned), b = store.open("https://ordinary.invalid")
            let c = store.open("https://sibling.invalid", kind: .pinned)
            store.selectTab(a)
            self.store = store
            self.a = a; self.b = b; self.c = c
            original = store.state
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var aIndex: Int { original.tabs.firstIndex { $0.id == a }! }
        var bIndex: Int { original.tabs.firstIndex { $0.id == b }! }
        var pinnedLocation: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned) }
        var tray: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile) }

        func pinned() -> BrowserState {
            var state = original
            state.tabs[aIndex].url = "https://live.invalid/form"
            state.tabs[aIndex].title = "Live"
            state.tabs[aIndex].customTitle = "Authored"
            state.tabs[aIndex].referrerID = b
            state.sidebarItemOrder[pinnedLocation.key] = [.tab(c), .tab(a)]
            return state
        }

        func favoriteTarget() -> BrowserState {
            var state = original
            state.tabs[aIndex].kind = .favorite
            state.sidebarItemOrder[tray.key] = [.tab(a)]
            return state
        }

        func favoriteContainer() -> (BrowserState, BrowserSplitLayout) {
            var state = favoriteTarget()
            state.tabs[state.tabs.firstIndex { $0.id == c }!].kind = .favorite
            let layout = BrowserSplitLayout(spaceID: space, tabIDs: [a, c], orientation: .horizontal, widthFactors: [0.4, 0.6])
            state.splitLayouts = [layout]
            state.selectedTabIDs = [a, c]
            return (state, layout)
        }

        func propose(_ state: BrowserState, source: UUID? = nil, target: SplitDropTarget = .insert(1),
                     layout: BrowserSplitLayout? = nil, homes: [UUID: UUID]? = nil) -> BrowserState? {
            OriginalSplitDrop.proposal(source: source ?? b, state: state, selection: state.selectedTabIDs,
                layout: layout, target: target, orientation: .horizontal, spaceID: space,
                profileID: profile, now: now, savedHomeIDs: homes ?? [a: home],
                creation: TabCreationProvenance(referrerID: nil, activeTabID: a, profileID: profile, state: state))
        }

        func session(_ state: BrowserState, _ name: String) throws -> URL {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            return directory
        }

        func breakWrites() throws -> Data {
            let file = root.appendingPathComponent("session.json")
            let saved = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            return saved
        }

        func restoreWrites(_ saved: Data) throws {
            let file = root.appendingPathComponent("session.json")
            try FileManager.default.removeItem(at: file)
            try saved.write(to: file)
        }
    }
}
