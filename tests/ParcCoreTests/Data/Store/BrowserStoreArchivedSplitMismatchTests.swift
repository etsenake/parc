import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreArchivedSplitMismatchTests {
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)

    @MainActor private static func archivedSplit(in directory: URL) throws -> (a: UUID, b: UUID) {
        let store = try BrowserStore(directory: directory, now: { now })
        let a = store.open("https://archive-a.example"), b = store.open("https://archive-b.example")
        store.setSplit([a, b])
        store.closeTabs([a, b])
        try store.save()
        return (a, b)
    }

    private static func damageSplit(of id: UUID, in directory: URL) throws {
        let file = directory.appendingPathComponent("session.json")
        var root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var tabs = try #require(root["tabs"] as? [[String: Any]])
        let index = try #require(tabs.firstIndex { ($0["id"] as? String) == id.uuidString })
        var provenance = try #require(tabs[index]["archiveProvenance"] as? [String: Any])
        var split = try #require(provenance["split"] as? [String: Any])
        split["widthFactors"] = [1.0]
        provenance["split"] = split
        tabs[index]["archiveProvenance"] = provenance
        root["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: root).write(to: file)
    }

    @MainActor @Test func membersWhoseSavedSplitsDisagreeComeBackOnTheirOwn() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let (a, b) = try Self.archivedSplit(in: directory)
            try Self.damageSplit(of: a, in: directory)
            let store = try BrowserStore(directory: directory, now: { Self.now })
            let items = store.archivedItems(profileID: store.activeSpace.profileID)
            #expect(items.map(\.tabs.count) == [1, 1])
            #expect(store.restoreArchivedTab(b, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID)) == [b])
            #expect(store.restoreArchivedTab(a, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID)) == [a])
        }
    }

    @MainActor @Test func membersWithMatchingSavedSplitsStillComeBackTogether() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let (a, b) = try Self.archivedSplit(in: directory)
            let store = try BrowserStore(directory: directory, now: { Self.now })
            #expect(store.archivedItems(profileID: store.activeSpace.profileID).map(\.tabs.count) == [2])
            #expect(Set(store.restoreArchivedTab(b, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID))) == [a, b])
        }
    }
}
