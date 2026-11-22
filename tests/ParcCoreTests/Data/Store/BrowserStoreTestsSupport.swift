import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
enum BrowserStoreTestsSupport {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @discardableResult
    static func savedSplit(_ store: BrowserStore, _ ids: [UUID], in location: SidebarContainerLocation) throws -> BrowserSplitLayout {
        store.selectTab(ids[0])
        for id in ids.dropFirst() { store.selectTab(id, extendingSplit: true) }
        guard let group = store.activeSplitLayout, group.tabIDs == ids else { throw Failure(description: "Split was not formed") }
        let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: store.activeSpaceID,
            profileID: store.activeSpace.profileID, includesFavorites: location.section == .favorite)!
        guard try store.moveSidebarItem(.split(group.id), to: location, before: nil, expected: snapshot),
              let moved = store.state.splitLayouts.first(where: { $0.id == group.id }) else { throw Failure(description: "Split did not move") }
        return moved
    }

    static func expectHome(of original: UUID, in store: BrowserStore, savedURL: String,
                           sourceLocation: SourceLocation = #_sourceLocation) throws -> BrowserTab {
        let homes = store.state.tabs.filter { $0.id != original && $0.savedURL == savedURL && $0.archivedAt == nil
            && ($0.kind == .pinned || $0.kind == .favorite) }
        #expect(homes.count == 1, "Exactly one fresh saved home holds the original slot", sourceLocation: sourceLocation)
        return homes[0]
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static func tab(_ id: UUID, in store: BrowserStore) throws -> BrowserTab {
        guard let value = store.state.tabs.first(where: { $0.id == id }) else {
            throw Failure(description: "Expected tab \(id) to exist")
        }
        return value
    }

    static func expectValidSelection(_ store: BrowserStore) throws {
        let visible = Set(store.visibleTabs.map(\.id))
        #expect(store.state.selectedTabIDs.allSatisfy { visible.contains($0) }, "Selection must contain only visible, unarchived tabs in the active profile/Space")
        #expect(Set(store.state.selectedTabIDs).count == store.state.selectedTabIDs.count, "Split selection must not contain duplicate tabs")
    }

    static func expectFactors(_ actual: [Double]?, _ expected: [Double], _ message: String) throws {
        #expect(actual?.count == expected.count, Comment(rawValue: message + " (pane count)"))
        guard let actual, actual.count == expected.count else { return }
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 1e-10 }, Comment(rawValue: message))
    }
}
