import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveAssetRollbackTests {
    @MainActor private final class Rollback {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-shared-rollback-" + UUID().uuidString)
        let source: EaselStore, destination: EaselStore
        let a: EaselSession, b: EaselSession
        let asset: String
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let rollback = LocalDocumentRelocationRollback()
        var attempted = 0

        init() throws {
            source = try EaselStore(directory: root.appendingPathComponent("source"))
            destination = try EaselStore(directory: root.appendingPathComponent("destination"))
            let a = try source.create(), b = try source.create()
            let asset = try a.importPNG(png)
            for session in [a, b] {
                try session.perform("Shared image") { $0.items = [EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 10, height: 10), assetID: asset)] }
                try source.retireSessionForRelocation(session.document.id)
            }
            self.a = a; self.b = b; self.asset = asset
            let source = source, destination = destination
            for session in [a, b] {
                let id = session.document.id, copied = try source.relocate(id, to: destination)
                rollback.append(reverse: { [unowned self] in
                    attempted += 1
                    do { _ = try destination.relocate(id, to: source); return true } catch { return false }
                }, cleanup: { destination.removeAssets(copied) })
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func blockBsReversal() throws {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("source/documents/" + b.document.id.uuidString.lowercased() + ".json"),
                                                    withIntermediateDirectories: false)
        }
    }

    @MainActor @Test func collectionRollbackAttemptsEveryReversalAfterOneFails() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        #expect(r.attempted == 2)
    }

    @MainActor @Test func partialRollbackKeepsRestoredAndStillDestinationDocumentsIntact() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        #expect(try r.source.load(r.a.document.id).document == r.a.document)
        #expect(try r.destination.load(r.b.document.id).document == r.b.document)
    }

    @MainActor @Test func partialRollbackPreservesASharedAssetCopiedByTheReversedDocument() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        #expect(try r.destination.load(r.b.document.id).assetData(r.asset) == r.png)
    }

    @MainActor @Test func theRollbackCapabilityIsConsumedOnce() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        r.rollback.run()
        #expect(r.attempted == 2)
    }

    @MainActor @Test func aFullyReversedCollectionRemovesItsCopiedAssetsAfterRestoration() throws {
        let r = try Rollback()
        r.rollback.run()
        #expect(try r.source.load(r.a.document.id).document == r.a.document)
        #expect(!FileManager.default.fileExists(atPath: r.destination.directory.appendingPathComponent("assets/" + r.asset).path))
    }

    @MainActor private final class Relocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-doc-relocate-" + UUID().uuidString)
        let ex: EaselStore, ey: EaselStore
        let easelID: UUID
        let asset: String
        let copied: [String]

        init() throws {
            ex = try EaselStore(directory: root.appendingPathComponent("X/Easels"))
            ey = try EaselStore(directory: root.appendingPathComponent("Y/Easels"))
            var easel: EaselSession? = try ex.create(title: "Board")
            easelID = easel!.document.id
            let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13] + Array("IHDR".utf8) + Array(repeating: 0, count: 13))
            let asset = try easel!.importPNG(png)
            try easel!.perform("Add image") { $0.items.append(EaselItem(kind: .image, frame: EaselRect(x: 0, y: 0, width: 10, height: 10), assetID: asset)) }
            easel = nil
            self.asset = asset
            copied = try ex.relocate(easelID, to: ey)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func assetExists(_ side: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(side + "/Easels/assets/" + asset).path)
        }
    }

    @MainActor @Test func anEaselDocumentMovesWithItsCopiedAssets() throws {
        let r = try Relocation()
        #expect(r.copied == [r.asset])
        #expect((try? r.ex.load(r.easelID)) == nil)
    }

    @MainActor @Test func theDestinationResolvesTheAssetAndTheSourceAssetsStay() throws {
        let r = try Relocation()
        #expect(try r.ey.load(r.easelID).document.items.first?.assetID == r.asset)
        #expect(r.assetExists("X"))
        #expect(r.assetExists("Y"))
    }

    @MainActor @Test func rollbackRemovesOnlyCopiedAssets() throws {
        let r = try Relocation()
        _ = try r.ey.relocate(r.easelID, to: r.ex)
        r.ey.removeAssets(r.copied)
        #expect(!r.assetExists("Y"))
        #expect(r.assetExists("X"))
        #expect(try r.ex.load(r.easelID).document.title == "Board")
    }
}
