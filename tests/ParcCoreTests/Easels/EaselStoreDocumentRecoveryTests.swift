import Foundation
import Testing
@testable import ParcCore

struct EaselStoreDocumentRecoveryTests {
    enum UnreadableFile: CaseIterable {
        case malformedJson, futureVersion, differentID, oversized
    }

    @MainActor @Test(arguments: UnreadableFile.allCases)
    func anUnreadableEaselFileIsLeftExactlyAsItWas(_ unreadable: UnreadableFile) throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            let id = session.document.id
            let path = EaselStoreTestsSupport.file(directory, id)
            var invalid = session.document
            let bytes: Data
            switch unreadable {
            case .malformedJson:
                bytes = Data("{not json".utf8)
            case .futureVersion:
                invalid.version = 999
                bytes = try JSONEncoder().encode(invalid)
            case .differentID:
                invalid.id = UUID()
                bytes = try JSONEncoder().encode(invalid)
            case .oversized:
                bytes = Data(repeating: 32, count: EaselStore.maximumDocumentBytes + 1)
            }
            try bytes.write(to: path)
            #expect(throws: (any Error).self) { _ = try EaselStore(directory: directory).load(id) }
            #expect(try Data(contentsOf: path) == bytes)
        }
    }

    @MainActor @Test
    func anUnreadableFileDoesNotHideOtherBoards() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let unreadable = try store.create()
            try Data("invalid".utf8).write(to: EaselStoreTestsSupport.file(directory, unreadable.document.id))
            let healthy = try store.create(title: "Healthy")
            #expect(try! store.list().map(\.id) == [healthy.document.id], "One unreadable or stray Easel file does not hide the other Easels")
        }
    }

    @MainActor @Test
    func reopeningDuplicateObjectIDsKeepsIdentityAndContent() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let healthy = try store.create(title: "Healthy")
            try healthy.perform("Shapes") {
                $0.items = [EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame), EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame), EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Kept")]
            }
            let shapes = healthy.document.items
            var duplicated = try JSONSerialization.jsonObject(with: Data(contentsOf: EaselStoreTestsSupport.file(directory, healthy.document.id))) as! [String: Any]
            var raw = duplicated["items"] as! [[String: Any]]
            raw[1]["id"] = raw[0]["id"]; raw[2]["id"] = raw[0]["id"]
            duplicated["items"] = raw
            try JSONSerialization.data(withJSONObject: duplicated).write(to: EaselStoreTestsSupport.file(directory, healthy.document.id))
            let repaired = try EaselStore(directory: directory).load(healthy.document.id).document
            #expect(repaired.items.count == 3 && Set(repaired.items.map(\.id)).count == 3, "Duplicate object IDs on disk are re-IDed instead of rejecting the Easel")
            #expect(repaired.items[0].id == shapes[0].id && repaired.items.map(\.kind) == shapes.map(\.kind) && repaired.items[2].text == "Kept",
                   "Repair keeps the first object's ID and every object's content")
            #expect(try! EaselStore(directory: directory).load(healthy.document.id).document == repaired, "Duplicate repair is stable across reads")
        }
    }
}
