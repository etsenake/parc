import Foundation
import Testing
@testable import ParcCore

@MainActor
final class NativeDownloadRecordTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-downloads-\(UUID())")
    let store: BrowserStore
    let first: UUID
    let second: UUID
    let guid = UUID().uuidString

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        store = try BrowserStore(directory: directory)
        first = store.activeSpace.profileID
        second = store.createProfile(name: "Independent")
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func update(_ profile: UUID, status: String = "downloading") -> [String: Any] {
        ["id": guid, "profilePath": store.independentEngineProfilePath(for: profile),
         "name": "actual.txt", "path": "/tmp/actual.txt", "receivedBytes": 17,
         "totalBytes": -1, "status": status, "available": true,
         "canPause": true, "canResume": false, "canCancel": true]
    }

    func recordInBothProfiles() {
        store.recordDownload(update(first))
        store.recordDownload(update(second))
    }

    @Test func theSameEngineDownloadInTwoProfilesStaysTwoRecords() {
        recordInBothProfiles()
        let downloads = store.state.downloads
        #expect(downloads.count == 2)
        #expect(Set(downloads.map(\.id)).count == 2)
        #expect(downloads[0].profileID == first && downloads[1].profileID == second)
        #expect(downloads[0].nativeID == guid)
        #expect(downloads[0].totalBytes == -1)
        #expect(downloads[0].canPause && !downloads[0].canResume)
    }

    @Test func aFailedDownloadKeepsItsErrorAndCanResume() {
        recordInBothProfiles()
        var failed = update(first, status: "failed")
        failed["errorCode"] = 20; failed["canPause"] = false; failed["canResume"] = true
        store.recordDownload(failed)
        let download = store.state.downloads[0]
        #expect(download.status == .failed && download.errorCode == 20)
        #expect(!download.isComplete && download.canResume)
    }

    @Test func aCompletedDownloadOffersNoControls() {
        recordInBothProfiles()
        var completed = update(first, status: "completed")
        completed["available"] = false
        store.recordDownload(completed)
        let download = store.state.downloads[0]
        #expect(download.isComplete)
        #expect(!download.canPause && !download.canCancel)
    }

    @Test func aRestoredStoreKeepsReviewsAndDropsLiveControls() throws {
        recordInBothProfiles()
        var unsafe = update(second)
        unsafe["requiresReview"] = true; unsafe["canPause"] = false
        store.recordDownload(unsafe)
        #expect(store.state.downloads[1].requiresReview)
        try store.save()
        let restored = try BrowserStore(directory: directory)
        #expect(restored.state.downloads.count == 2)
        #expect(restored.state.downloads[1].requiresReview)
        #expect(restored.state.downloads.allSatisfy { !$0.canPause && !$0.canResume && !$0.canCancel })
    }

    @Test func updatesFromAnotherProfileFolderAreIgnored() {
        recordInBothProfiles()
        var foreign = update(first, status: "completed")
        foreign["profilePath"] = "/profiles/foreign"
        store.recordDownload(foreign)
        #expect(store.state.downloads[0].status == .downloading)
    }

    @Test func aRemovedDownloadLeavesOnlyItsOwnRecord() {
        recordInBothProfiles()
        var removed = update(first)
        removed["removed"] = true
        store.recordDownload(removed)
        #expect(store.state.downloads.count == 1)
        #expect(store.state.downloads[0].profileID == second)
    }

    @Test func aLegacyRecordWithoutAProfileCannotBeCancelled() {
        store.recordDownload(["id": "legacy", "status": "completed"])
        #expect(store.state.downloads.count == 1)
        #expect(store.state.downloads[0].profileID == nil)
        #expect(!store.state.downloads[0].canCancel)
    }
}
