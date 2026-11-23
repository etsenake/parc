import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ParcCore

enum CaptureSnapshotFixture {
    static func pdf(width: CGFloat = 100, height: CGFloat = 400) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    static func png() -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 4, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 16))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return (bytes[0], bytes[1], bytes[2])
    }
}

struct CaptureSnapshotPDFTests {
    @Test func aCapturedPagePDFOpensAtItsPageSize() throws {
        let snapshot = try #require(CaptureSnapshotPDF(data: CaptureSnapshotFixture.pdf()))
        #expect(snapshot.size == CGSize(width: 100, height: 400))
    }

    @Test(arguments: [Data(), Data("not a pdf".utf8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), Data("%PDF-1.7 broken".utf8)])
    func anythingButAReadablePDFIsRefused(_ data: Data) {
        #expect(CaptureSnapshotPDF(data: data) == nil)
    }

    @Test func aRenderedRegionShowsThatPartOfThePageTheRightWayUp() throws {
        let snapshot = try #require(CaptureSnapshotPDF(data: CaptureSnapshotFixture.pdf()))
        let page = CGRect(origin: .zero, size: snapshot.size)
        let top = try #require(snapshot.render(region: CGRect(x: 0, y: 0, width: 100, height: 100), in: page, pixelScale: 2, flipped: true))
        let bottom = try #require(snapshot.render(region: CGRect(x: 0, y: 300, width: 100, height: 100), in: page, pixelScale: 2, flipped: true))
        #expect(top.width == 200 && top.height == 200)
        #expect(CaptureSnapshotFixture.pixel(top, x: 100, y: 100).red > 200)
        #expect(CaptureSnapshotFixture.pixel(bottom, x: 100, y: 100).blue > 200)
    }

    @Test func drawingFillsTheCardItIsGiven() throws {
        let snapshot = try #require(CaptureSnapshotPDF(data: CaptureSnapshotFixture.pdf()))
        let image = try #require(snapshot.render(region: CGRect(x: 0, y: 0, width: 50, height: 100), in: CGRect(x: 0, y: 0, width: 50, height: 100),
                                                 pixelScale: 1, flipped: true))
        #expect(CaptureSnapshotFixture.pixel(image, x: 25, y: 10).red > 200)
        #expect(CaptureSnapshotFixture.pixel(image, x: 25, y: 90).blue > 200)
    }
}

@MainActor
struct EaselCaptureSnapshotStoreTests {
    private func withSession(_ run: (EaselStore, EaselSession, String, String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ParcSnapshot-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory)
        let session = try store.create(title: "Board")
        let png = try session.importPNG(CaptureSnapshotFixture.png())
        let pdf = try session.importAsset(CaptureSnapshotFixture.pdf(), type: .pdf)
        try run(store, session, png, pdf)
    }

    private func card(png: String, snapshot: String?) -> EaselItem {
        EaselItem(kind: .webCard, frame: EaselRect(x: 0, y: 0, width: 100, height: 400), url: "https://example.com/long",
                  assetID: png, snapshot: snapshot)
    }

    @Test func aCaptureCardKeepsItsPDFSnapshotAcrossReopening() throws {
        try withSession { store, session, png, pdf in
            let item = card(png: png, snapshot: pdf)
            try session.perform("Add") { $0.items.append(item) }
            let reopened = try EaselStore(directory: store.directory).load(session.document.id)
            #expect(reopened.document.items.first?.snapshot == pdf)
            #expect(try reopened.assetData(pdf) == session.assetData(pdf))
        }
    }

    @Test func onlyCaptureCardsWithAPictureMayCarryAPDFSnapshot() throws {
        try withSession { _, session, png, pdf in
            var image = card(png: png, snapshot: pdf)
            image.kind = .image
            #expect(throws: EaselStoreError.self) { try session.perform("Add") { $0.items.append(image) } }
            #expect(throws: EaselStoreError.self) { try session.perform("Add") { $0.items.append(self.card(png: png, snapshot: png)) } }
            #expect(session.document.items.isEmpty)
        }
    }

    @Test func discardingKeepsASnapshotStillInUse() throws {
        try withSession { _, session, png, pdf in
            try session.perform("Add") { $0.items.append(card(png: png, snapshot: pdf)) }
            session.discardUnusedAssets([pdf])
            #expect((try? session.assetData(pdf)) != nil)
        }
    }

    @Test func copyingACardBringsItsSnapshotAndPastingRemapsIt() throws {
        let item = card(png: "a.png", snapshot: "b.pdf")
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [item])
        #expect(EaselClipboardPayload.assetIDs(of: [item.id], in: board) == ["a.png", "b.pdf"])
        let payload = try #require(try EaselClipboardPayload.capturing([item.id], in: board, assets: ["a.png": Data([1]), "b.pdf": Data([2])]))
        #expect(payload.items.first?.snapshot == "b.pdf" && payload.assets["b.pdf"] == Data([2]))
        let pasted = item.carryingAssets(["a.png": "c.png", "b.pdf": "d.pdf"])
        #expect(pasted.assetID == "c.png" && pasted.snapshot == "d.pdf")
        #expect(item.carryingAssets(["a.png": "c.png"]).snapshot == nil)
    }

    @Test func aCopyWhoseSnapshotCannotBeReadStillCopiesThePicture() throws {
        let item = card(png: "a.png", snapshot: "b.pdf")
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [item])
        let payload = try #require(try EaselClipboardPayload.capturing([item.id], in: board, assets: ["a.png": Data([1])]))
        #expect(payload.items.first?.assetID == "a.png" && payload.items.first?.snapshot == nil)
    }
}
