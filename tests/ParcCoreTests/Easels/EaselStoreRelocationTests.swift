import Foundation
import Testing
@testable import ParcCore

struct EaselStoreRelocationTests {
    @MainActor
    private func makeRelocation(in directory: URL) throws -> (
        source: EaselStore, destination: EaselStore, original: EaselSession, asset: String, browser: EaselItem
    ) {
        let source = try EaselStore(directory: directory.appendingPathComponent("source"))
        let destination = try EaselStore(directory: directory.appendingPathComponent("destination"))
        let original = try source.create(title: "Profile transfer")
        let asset = try original.importPNG(EaselStoreTestsSupport.png)
        let browser = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/original")
        let card = EaselItem(kind: .webCard, frame: EaselStoreTestsSupport.frame, text: "Original capture", url: "https://example.com/source", assetID: asset, capturedAt: Date(timeIntervalSince1970: 42))
        try original.perform("Seed") { $0.items = [browser, card] }
        _ = try original.recordBrowserNavigation(URL(string: "https://example.com/current")!, itemID: browser.id, expectedURL: browser.url!)
        return (source, destination, original, asset, browser)
    }

    @MainActor @Test
    func aLiveChildPreventsSessionRetirement() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let (source, _, original, _, _) = try makeRelocation(in: directory)
            let id = original.document.id
            let liveChild = original.observeReplacement { $0 != nil }
            EaselStoreTestsSupport.expectThrows("a live original child prevents session retirement") { try source.retireSessionForRelocation(id) }
            #expect(!original.isClosed && (try! source.load(id)) === original, "refused retirement preserves source session")
            original.removeReplacementObserver(liveChild)
        }
    }

    @MainActor @Test
    func aBoardWithAnOpenSessionCannotMoveProfiles() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let (source, destination, original, _, _) = try makeRelocation(in: directory)
            let id = original.document.id
            EaselStoreTestsSupport.expectThrows("a still-open editor cannot move by deallocation timing") { _ = try source.relocate(id, to: destination) }
        }
    }

    @MainActor @Test
    func anEaselRelocatesToAnotherProfileWithItsExactBytes() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let (source, destination, original, asset, _) = try makeRelocation(in: directory)
            let id = original.document.id
            let saved = original.document
            let originalBytes = try Data(contentsOf: EaselStoreTestsSupport.file(source.directory, id))
            try source.retireSessionForRelocation(id)
            #expect(original.isClosed && !original.canUndo && !original.canRedo, "explicit session retirement revokes history despite a retained old owner")
            let copied = try source.relocate(id, to: destination)
            #expect(copied == [asset] && (try? source.load(id)) == nil, "actual document moves after explicit retirement")
            #expect(try! Data(contentsOf: EaselStoreTestsSupport.file(destination.directory, id)) == originalBytes, "Profile relocation preserves the exact document bytes")
            let arrived = try destination.load(id)
            #expect(arrived !== original && arrived.document == saved, "destination uses a fresh session with exact identity/current URL/capture provenance")
            #expect(try! arrived.assetData(asset) == EaselStoreTestsSupport.png, "destination capture resolves the original bytes")
        }
    }

    enum LateRelocationAction: CaseIterable {
        case edit, navigate, save, importImage, undo, redo
    }

    @MainActor @Test(arguments: LateRelocationAction.allCases)
    func aRetiredSessionCannotRecreateTheSource(_ action: LateRelocationAction) throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let (source, destination, original, _, browser) = try makeRelocation(in: directory)
            let id = original.document.id
            try source.retireSessionForRelocation(id)
            _ = try source.relocate(id, to: destination)
            #expect(throws: EaselStoreError.self) {
                switch action {
                case .edit: try original.perform("Late edit") { $0.title = "Wrong profile" }
                case .navigate:
                    let url = try #require(URL(string: "https://example.com/stale"))
                    _ = try original.recordBrowserNavigation(url, itemID: browser.id, expectedURL: "https://example.com/current")
                case .save: try original.save()
                case .importImage: _ = try original.importPNG(EaselStoreTestsSupport.png)
                case .undo: try original.undo()
                case .redo: try original.redo()
                }
            }
            #expect(!FileManager.default.fileExists(atPath: EaselStoreTestsSupport.file(source.directory, id).path))
        }
    }

    @MainActor @Test
    func rollingBackRelocationReopensASeparateWritableSession() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let (source, destination, original, _, _) = try makeRelocation(in: directory)
            let id = original.document.id
            let saved = original.document
            try source.retireSessionForRelocation(id)
            let copied = try source.relocate(id, to: destination)
            let arrived = try destination.load(id)
            try destination.retireSessionForRelocation(arrived.document.id)
            _ = try destination.relocate(id, to: source); destination.removeAssets(copied)
            let restored = try source.load(id)
            #expect(restored !== original && restored.document == saved, "rollback reopens exact original data through a fresh source session")
            try restored.perform("After rollback") { $0.title = "Writable source" }
            #expect(restored.document.title == "Writable source" && original.document == saved, "old retained session stays revoked after rollback")
        }
    }

    @MainActor @Test
    func aDestinationAssetCollisionPreservesBothProfiles() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let (source, destination, original, asset, _) = try makeRelocation(in: directory)
            let id = original.document.id
            let saved = original.document
            try source.retireSessionForRelocation(id)
            let collision = destination.directory.appendingPathComponent("assets/" + asset)
            var other = EaselStoreTestsSupport.png; other.append(0)
            try other.write(to: collision)
            EaselStoreTestsSupport.expectThrows("destination asset collision cannot silently replace a capture") { _ = try source.relocate(id, to: destination) }
            #expect((try! source.load(id)).document == saved && (try? destination.load(id)) == nil,
                   "asset collision preserves source ownership and leaves no destination document")
            #expect(try! Data(contentsOf: collision) == other, "collision preserves the preexisting destination asset")
        }
    }
}
