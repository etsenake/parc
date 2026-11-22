import AppKit
import CoreText
import Testing
@testable import ParcCore

enum SplitAppearanceSupport {
    static var iconFixtures: URL? {
        Bundle.module.url(forResource: "SplitViews", withExtension: nil)?.appendingPathComponent("CustomInfoPicker", isDirectory: true)
    }

    @MainActor final class SplitFixture {
        let directory: URL
        let store: BrowserStore
        let first: UUID
        let second: UUID
        let profile: UUID
        let space: UUID

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-appearance-" + UUID().uuidString)
            store = try BrowserStore(directory: directory)
            first = store.openResolvedURL(URL(string: "https://one.invalid")!)
            second = store.openResolvedURL(URL(string: "https://two.invalid")!)
            store.setSplit([first, second])
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var file: URL { directory.appendingPathComponent("session.json") }

        func target() -> SidebarSplitTitleEdit {
            SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [first, second])!
        }

        func breakDisk() throws {
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }

        func favoriteStore() throws -> (store: BrowserStore, other: BrowserSpace) {
            let other = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "AABBCC", profileID: profile)
            var state = store.state
            state.spaces.append(other)
            state.activeSpaceID = other.id
            for index in state.tabs.indices where [first, second].contains(state.tabs[index].id) {
                state.tabs[index].kind = .favorite
                state.tabs[index].folderID = nil
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: file)
            return (try BrowserStore(directory: directory), other)
        }
    }
}
