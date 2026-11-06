import Foundation

@main @MainActor
struct NativeDownloadsModelTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool) {
        count += 1; precondition(condition(), "Native download assertion \(count) failed")
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-downloads-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let first = store.activeSpace.profileID
        let second = store.createProfile(name: "Independent")
        let guid = UUID().uuidString
        func update(_ profile: UUID, status: String = "downloading") -> [String: Any] {
            ["id": guid, "profilePath": store.independentEngineProfilePath(for: profile),
             "name": "actual.txt", "path": "/tmp/actual.txt", "receivedBytes": 17,
             "totalBytes": -1, "status": status, "available": true,
             "canPause": true, "canResume": false, "canCancel": true]
        }
        store.recordDownload(update(first)); store.recordDownload(update(second))
        expect(store.state.downloads.count == 2)
        expect(Set(store.state.downloads.map(\.id)).count == 2)
        expect(store.state.downloads[0].profileID == first)
        expect(store.state.downloads[1].profileID == second)
        expect(store.state.downloads[0].nativeID == guid)
        expect(store.state.downloads[0].totalBytes == -1)
        expect(store.state.downloads[0].canPause)
        expect(!store.state.downloads[0].canResume)
        var failed = update(first, status: "failed")
        failed["errorCode"] = 20; failed["canPause"] = false; failed["canResume"] = true
        store.recordDownload(failed)
        expect(store.state.downloads[0].status == .failed)
        expect(store.state.downloads[0].errorCode == 20)
        expect(!store.state.downloads[0].isComplete)
        expect(store.state.downloads[0].canResume)
        var unavailable = update(first, status: "completed")
        unavailable["available"] = false
        store.recordDownload(unavailable)
        expect(store.state.downloads[0].isComplete)
        expect(!store.state.downloads[0].canPause && !store.state.downloads[0].canCancel)
        var unsafe = update(second)
        unsafe["requiresReview"] = true; unsafe["canPause"] = false
        store.recordDownload(unsafe)
        expect(store.state.downloads[1].requiresReview)
        try store.save()
        let restored = try BrowserStore(directory: directory)
        expect(restored.state.downloads.count == 2)
        expect(restored.state.downloads[1].requiresReview)
        expect(restored.state.downloads.allSatisfy { !$0.canPause && !$0.canResume && !$0.canCancel })
        expect(restored.state.downloads[0].status == .completed)
        var foreign = update(first)
        foreign["profilePath"] = "/profiles/foreign"
        restored.recordDownload(foreign)
        expect(restored.state.downloads[0].status == .completed)
        var removed = update(first); removed["removed"] = true
        restored.recordDownload(removed)
        expect(restored.state.downloads.count == 1)
        expect(restored.state.downloads[0].profileID == second)
        restored.recordDownload(["id": "legacy", "status": "completed"])
        expect(restored.state.downloads.count == 2)
        expect(restored.state.downloads[1].profileID == nil)
        expect(!restored.state.downloads[1].canCancel)
        print("NativeDownloads model: \(count) assertions passed")
    }
}
