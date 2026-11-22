import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceDownloadsTests {
    struct TransferSnapshot: Sendable, CustomTestStringConvertible {
        let state: String
        let received: Int64
        var testDescription: String { "\(state) at \(received) bytes" }
    }

    @Test(arguments: [
        TransferSnapshot(state: "pending", received: 0),
        TransferSnapshot(state: "downloading", received: 25),
        TransferSnapshot(state: "paused", received: 25),
        TransferSnapshot(state: "downloading", received: 50),
        TransferSnapshot(state: "failed", received: 50),
        TransferSnapshot(state: "downloading", received: 75),
        TransferSnapshot(state: "completed", received: 100),
    ])
    @MainActor static func aDownloadSnapshotUpdatesAndPersistsItsExistingRecord(_ snapshot: TransferSnapshot) throws {
        let state = snapshot.state
        let received = snapshot.received
        let status = try #require(BrowserDownloadStatus(rawValue: state))
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            store.recordDownload(["id": "transfer-1", "status": "pending"])
            store.recordDownload(["id": "transfer-1", "name": "notes.pdf", "path": "/isolated/notes.pdf",
                                  "receivedBytes": NSNumber(value: received), "totalBytes": 100,
                                  "status": status.rawValue])
            #expect(store.state.downloads.count == 1, "A lifecycle update must replace the existing download rather than append a duplicate")
            let item = store.state.downloads[0]
            #expect(item.status == status && item.receivedBytes == received && item.totalBytes == 100, "Download state and byte progress must track the latest native snapshot: \(status)")
            #expect(item.isComplete == (status == .completed) && !item.isCancelled, "Paused or failed downloads must never be described as completed or cancelled")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads == store.state.downloads, "Every download lifecycle state must persist across a restart: \(status)")
        }
    }

    @Test @MainActor static func cancellationPersistsAlongsideACompletedTransferWithoutNavigating() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSelection = store.state.selectedTabIDs
            let originalHistory = store.state.history
            store.recordDownload(["id": "transfer-1", "status": "completed", "receivedBytes": 100, "totalBytes": 100])
            store.recordDownload(["id": "transfer-2", "name": "cancelled.zip", "receivedBytes": 12,
                                  "totalBytes": 200, "status": "cancelled"])
            #expect(store.state.downloads.count == 2 && store.state.downloads[1].isCancelled
                       && !store.state.downloads[1].isComplete, "A cancelled transfer must remain distinct from a successful transfer")
            #expect(store.state.selectedTabIDs == originalSelection && store.state.history == originalHistory, "Download events must not navigate or create page history")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads == store.state.downloads, "Cancellation and the prior completed transfer must both survive relaunch")
        }
    }

    @MainActor
    private static func withNativeDownload(
        _ body: (BrowserStore, [String: Any]) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: profile)
            let snapshot: [String: Any] = ["id": "same-guid", "profilePath": path,
                "name": "report.pdf", "path": "/isolated/report.pdf", "status": "completed",
                "sourceURL": "https://example.test/report.pdf", "startedAt": 1_700_000_000.0,
                "available": true, "itemIdentity": "incarnation-one", "canOpen": true,
                "canReveal": true, "canRemove": true, "canCopyFile": true]
            store.recordDownload(snapshot)
            try body(store, snapshot)
        }
    }

    @Test @MainActor static func nativeDownloadMetadataKeepsTheProfileAndLiveFileActions() throws {
        try withNativeDownload { store, _ in
            let profile = store.activeSpace.profileID
            let original = store.state.downloads[0]
            #expect(original.profileID == profile && original.nativeIdentity == "incarnation-one"
                       && original.canOpen && original.canReveal && original.canRemove && original.canCopyFile, "Library controls must retain the real profile and live item incarnation")
            #expect(original.sourceURL == "https://example.test/report.pdf"
                       && original.startedAt == Date(timeIntervalSince1970: 1_700_000_000), "Source URL and native start time must survive the bridge without a fabricated date")
        }
    }

    @Test @MainActor static func reopenedDownloadsKeepMetadataButNotLiveFileActions() throws {
        try withNativeDownload { store, _ in
            let original = store.state.downloads[0]
            try store.save()
            let restored = try BrowserStore(directory: store.directory).state.downloads[0]
            #expect(restored.sourceURL == original.sourceURL && restored.startedAt == original.startedAt, "Library metadata survives session persistence")
            #expect(restored.nativeIdentity == nil && !restored.canOpen && !restored.canReveal
                       && !restored.canRemove && !restored.canCopyFile, "Restored metadata never grants live file actions")
        }
    }

    @Test @MainActor static func aNewDownloadIncarnationReplacesThePreviousOneForTheSameGUID() throws {
        try withNativeDownload { store, initial in
            var snapshot = initial
            snapshot["itemIdentity"] = "incarnation-two"
            store.recordDownload(snapshot)
            #expect(store.state.downloads.count == 1 && store.state.downloads[0].nativeIdentity == "incarnation-two", "The same GUID can receive a new incarnation without making an old row current")
        }
    }

    @Test @MainActor static func retiringADownloadManagerRevokesFileActions() throws {
        try withNativeDownload { store, initial in
            var snapshot = initial
            snapshot["available"] = false
            store.recordDownload(snapshot)
            #expect(store.state.downloads[0].nativeIdentity == nil && !store.state.downloads[0].canCopyFile, "Manager retirement revokes file actions without erasing truthful completion")
        }
    }

    @Test @MainActor static func downloadsFromUnknownProfilesCannotChangeTheSession() throws {
        try withNativeDownload { store, initial in
            let selection = store.state.selectedTabIDs
            var snapshot = initial
            snapshot["profilePath"] = store.directory.appendingPathComponent("unowned").path
            snapshot["id"] = "unowned"
            store.recordDownload(snapshot)
            #expect(store.state.downloads.count == 1 && store.state.selectedTabIDs == selection, "Unknown profiles are discarded; download updates do not switch pages")
        }
    }

    @Test @MainActor static func reconcilingDownloadHistoryRemovesOnlyStaleRecordsForThatProfile() throws {
        try withNativeDownload { store, _ in
            store.recordDownload(["id": "legacy", "name": "old.pdf", "status": "completed"])
            store.reconcileDownloads(profileID: store.activeSpace.profileID, nativeIDs: [])
            #expect(store.state.downloads.map(\.id) == ["legacy"], "Ready manager history removes only stale records assigned to its original profile")
        }
    }

    @Test @MainActor static func legacyDownloadSessionMigration() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var session = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            session["downloads"] = [
                ["id": "complete", "name": "complete.pdf", "path": "/isolated/complete.pdf",
                 "receivedBytes": 100, "totalBytes": 100, "isComplete": true, "isCancelled": false],
                ["id": "cancelled", "name": "cancelled.pdf", "path": "",
                 "receivedBytes": 50, "totalBytes": 100, "isComplete": false, "isCancelled": true],
                ["id": "active", "name": "active.pdf", "path": "/isolated/active.pdf",
                 "receivedBytes": 50, "totalBytes": 100, "isComplete": false, "isCancelled": false],
                ["id": "pending", "name": "pending.pdf", "path": "",
                 "receivedBytes": 0, "totalBytes": -1, "isComplete": false, "isCancelled": false]
            ]
            try JSONSerialization.data(withJSONObject: session).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            #expect(migrated.state.downloads.map(\.status) == [.completed, .cancelled, .downloading, .pending], "Old sessions without status must retain completion, cancellation, and available progress information")
            #expect(migrated.state.downloads[0].path == "/isolated/complete.pdf"
                       && migrated.state.downloads[2].receivedBytes == 50
                       && migrated.state.downloads[3].totalBytes == -1, "Migration must preserve paths, byte counts, and unknown content lengths")
            try migrated.save()
            let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let downloads = encoded["downloads"] as! [[String: Any]]
            #expect(downloads[0]["status"] as? String == "completed"
                       && downloads[0]["isComplete"] as? Bool == true
                       && downloads[1]["isCancelled"] as? Bool == true, "Newly saved states must include precise status and retain the original compatibility flags")
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads == migrated.state.downloads, "A migrated session must round-trip without further state changes")
        }
    }

    struct CompatibilityStatus: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let flag: String
        let status: String
        let expected: String
    }

    @Test(arguments: [
        CompatibilityStatus(testDescription: "Pause flag alone", flag: "isPaused", status: "", expected: "paused"),
        CompatibilityStatus(testDescription: "Failure flag alone", flag: "isFailed", status: "", expected: "failed"),
        CompatibilityStatus(testDescription: "Known status wins over failure flag", flag: "isFailed", status: "downloading", expected: "downloading"),
        CompatibilityStatus(testDescription: "Unknown status uses failure flag", flag: "isFailed", status: "unknown", expected: "failed"),
    ])
    @MainActor static func explicitDownloadStatusTakesPrecedenceOverCompatibilityFlags(_ input: CompatibilityStatus) throws {
        let (flag, status, expected) = (input.flag, input.status, input.expected)
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            var snapshot: [String: Any] = ["id": "transfer", flag: true, "receivedBytes": 4]
            if !status.isEmpty { snapshot["status"] = status }
            store.recordDownload(snapshot)
            #expect(store.state.downloads.map(\.status.rawValue) == [expected])
        }
    }
}
