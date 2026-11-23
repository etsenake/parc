import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreArchivedSplitIntegrityTests {
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)

    private static func editSavedProvenance(in directory: URL, _ edit: (inout [String: [String: Any]]) -> Void) throws {
        let file = directory.appendingPathComponent("session.json")
        var saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var tabs = try #require(saved["tabs"] as? [[String: Any]])
        var provenance: [String: [String: Any]] = [:]
        for tab in tabs { if let id = tab["id"] as? String, let value = tab["archiveProvenance"] as? [String: Any] { provenance[id] = value } }
        edit(&provenance)
        for index in tabs.indices { if let id = tabs[index]["id"] as? String { tabs[index]["archiveProvenance"] = provenance[id] } }
        saved["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
    }

    @Test func anArchivedTabMissingFromItsSavedSplitStillAppearsInTheArchive() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Self.now })
            let a = store.open("https://archive-a.example"), b = store.open("https://archive-b.example")
            let c = store.open("https://archive-c.example")
            store.setSplit([a, b])
            store.closeTabs([a, b, c])
            try store.save()
            try Self.editSavedProvenance(in: directory) { provenance in
                let grouped = provenance[a.uuidString]
                provenance[c.uuidString]?["groupID"] = grouped?["groupID"]
                provenance[c.uuidString]?["split"] = grouped?["split"]
            }
            let loaded = try BrowserStore(directory: directory, now: { Self.now })
            let items = loaded.archivedItems(profileID: loaded.activeSpace.profileID).map { $0.tabs.map(\.id) }
            #expect(items.count == 2)
            #expect(Set(items) == [[a, b], [c]])
        }
    }
}
