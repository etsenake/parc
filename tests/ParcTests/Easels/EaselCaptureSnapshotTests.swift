import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselCaptureSnapshotTests {
    private let url = URL(string: "https://example.com/long/page")!

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

    private func png(width: Int = 25, height: Int = 100) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        memset(try #require(bitmap.bitmapData), 0x40, bitmap.bytesPerRow * height)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func withStore(_ run: (EaselStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ParcEaselSnapshot-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(EaselStore(directory: directory))
    }

    private func place(_ pdf: Data?, capturedPage: Bool = true, in store: EaselStore) throws -> (EaselSession, EaselItem) {
        var input = EaselImageInput(pngData: try png(), sourceURL: url, pageTitle: "Long page", valid: { true })
        input.capturedPage = capturedPage
        input.snapshotPDF = pdf
        let placed = try EaselImagePlacement.place(input, in: store, destinationID: nil, newTitle: "Long page")
        let session = try store.load(placed.id)
        return (session, try #require(session.document.items.first))
    }

    @Test func aSharpFullPageLandsAsTheSameCaptureCardWithItsPageDocument() throws {
        try withStore { store in
            let pdf = Self.pdf()
            let (session, item) = try place(pdf, in: store)
            let snapshot = try #require(item.snapshot)
            #expect(item.kind == .webCard && item.assetID != nil && item.url == url.absoluteString)
            #expect(item.frame.width == 100 && item.frame.height == 400)
            #expect(EaselAssetType.of(assetID: snapshot) == .pdf)
            #expect(try session.assetData(snapshot) == pdf)
            #expect(try EaselStore(directory: store.directory).load(session.document.id).document.items.first?.snapshot == snapshot)
        }
    }

    @Test(arguments: [Data("%PDF-1.7 broken".utf8), Data("plain".utf8)])
    func anUnreadablePageDocumentFallsBackToThePictureQuietly(_ pdf: Data) throws {
        try withStore { store in
            let (_, item) = try place(pdf, in: store)
            #expect(item.kind == .webCard && item.assetID != nil && item.snapshot == nil)
        }
    }

    @Test func aPageDocumentOverTheAssetLimitFallsBackToThePicture() throws {
        try withStore { store in
            var pdf = Self.pdf()
            pdf.append(Data(count: EaselStore.maximumAssetBytes))
            let (_, item) = try place(pdf, in: store)
            #expect(item.kind == .webCard && item.snapshot == nil)
        }
    }

    @Test func aWidePageSizesTheCardFromThePageNotTheShrunkPicture() throws {
        try withStore { store in
            let (_, item) = try place(Self.pdf(width: 1_200, height: 4_800), in: store)
            #expect(item.snapshot != nil && item.frame.width == 480 && item.frame.height == 1_920)
        }
    }

    @Test func aCardWithoutAUsablePageDocumentKeepsThePictureSize() throws {
        try withStore { store in
            let (_, item) = try place(Data("%PDF-1.7 broken".utf8), in: store)
            #expect(item.frame.width == 25 && item.frame.height == 100)
        }
    }

    @Test func capturedCardSizeFollowsThePageAtItsAspect() {
        let wide = EaselMediaPlacement.capturedCardSize(picture: (120, 6_000), page: CGSize(width: 1_200, height: 60_000))
        #expect(wide.width == 480 && wide.height == 24_000)
        let narrow = EaselMediaPlacement.capturedCardSize(picture: (150, 450), page: CGSize(width: 300, height: 900))
        #expect(narrow.width == 300 && narrow.height == 900)
        let picture = EaselMediaPlacement.capturedCardSize(picture: (120, 6_000), page: nil)
        #expect(picture.width == 120 && picture.height == 6_000)
        let unusable = EaselMediaPlacement.capturedCardSize(picture: (120, 6_000), page: CGSize(width: 0, height: 900))
        #expect(unusable.width == 120 && unusable.height == 6_000)
    }

    private func key(_ level: Int, _ column: Int, _ row: Int) -> EaselSnapshotTileKey {
        EaselSnapshotTileKey(asset: "a.pdf", level: level, column: column, row: row)
    }

    @Test func aMissingTileBorrowsTheCoarserCachedTileThatContainsIt() {
        let page = CGSize(width: 2_048, height: 2_048)
        let cached: Set<EaselSnapshotTileKey> = [key(0, 1, 1)]
        let cover = EaselSnapshotTiling.cover([key(1, 2, 3), key(1, 3, 3)], page: page, sharperThan: 0.25, cached: cached.contains)
        #expect(cover.fallback == [key(0, 1, 1)] && cover.uncovered.isEmpty)
    }

    @Test func aFinerLevelCoversOnlyWhenEveryChildIsCached() {
        let page = CGSize(width: 2_048, height: 2_048)
        let all: Set<EaselSnapshotTileKey> = [key(2, 0, 0), key(2, 1, 0), key(2, 0, 1), key(2, 1, 1)]
        #expect(EaselSnapshotTiling.cover([key(1, 0, 0)], page: page, sharperThan: 0, cached: all.contains).fallback
                == [key(2, 0, 0), key(2, 1, 0), key(2, 0, 1), key(2, 1, 1)])
        let some: Set<EaselSnapshotTileKey> = [key(2, 0, 0), key(2, 1, 0)]
        let partial = EaselSnapshotTiling.cover([key(1, 0, 0)], page: page, sharperThan: 0, cached: some.contains)
        #expect(partial.fallback.isEmpty && partial.uncovered == [CGRect(x: 0, y: 0, width: 256, height: 256)])
    }

    @Test func theNearestLevelWinsAndSharperBeatsBlurrierAtTheSameDistance() {
        let page = CGSize(width: 4_096, height: 4_096)
        let cached: Set<EaselSnapshotTileKey> = [key(-1, 0, 0), key(0, 0, 0), key(2, 0, 0), key(2, 1, 0), key(2, 0, 1), key(2, 1, 1)]
        #expect(EaselSnapshotTiling.cover([key(1, 0, 0)], page: page, sharperThan: 0, cached: cached.contains).fallback
                == [key(2, 0, 0), key(2, 1, 0), key(2, 0, 1), key(2, 1, 1)])
        let coarse: Set<EaselSnapshotTileKey> = [key(-1, 0, 0), key(0, 0, 0)]
        #expect(EaselSnapshotTiling.cover([key(1, 0, 0)], page: page, sharperThan: 0, cached: coarse.contains).fallback == [key(0, 0, 0)])
    }

    @Test func aCoarserTileNoSharperThanThePictureLeavesThePictureShowing() {
        let page = CGSize(width: 2_048, height: 2_048)
        let cached: Set<EaselSnapshotTileKey> = [key(-1, 0, 0)]
        let cover = EaselSnapshotTiling.cover([key(1, 0, 0)], page: page, sharperThan: 0.5, cached: cached.contains)
        #expect(cover.fallback.isEmpty && cover.uncovered == [CGRect(x: 0, y: 0, width: 256, height: 256)])
        #expect(EaselSnapshotTiling.cover([key(1, 0, 0)], page: page, sharperThan: 0.4, cached: cached.contains).fallback == [key(-1, 0, 0)])
    }

    @Test func coarserFallbacksAreListedFirstSoSharperOnesPaintOnTop() {
        let page = CGSize(width: 2_048, height: 2_048)
        let cached: Set<EaselSnapshotTileKey> = [key(0, 0, 0), key(2, 2, 0), key(2, 3, 0), key(2, 2, 1), key(2, 3, 1)]
        let cover = EaselSnapshotTiling.cover([key(1, 0, 0), key(1, 1, 0)], page: page, sharperThan: 0, cached: cached.contains)
        #expect(cover.fallback.map(\.level) == [0, 2, 2, 2, 2] && cover.uncovered.isEmpty)
        let mixed: Set<EaselSnapshotTileKey> = [key(0, 1, 1), key(2, 0, 0), key(2, 1, 0), key(2, 0, 1), key(2, 1, 1)]
        let both = EaselSnapshotTiling.cover([key(1, 0, 0), key(1, 2, 2)], page: page, sharperThan: 0, cached: mixed.contains)
        #expect(both.fallback.map(\.level) == [0, 2, 2, 2, 2] && both.uncovered.isEmpty)
    }

    @Test func theRenderQueueServesTheNewestRequestFirstAndDropsStaleOnes() {
        var queue = EaselSnapshotTileQueue(limit: 3)
        #expect(queue.push(key(0, 0, 0)).isEmpty)
        queue.push(key(0, 1, 0))
        queue.push(key(0, 2, 0))
        queue.push(key(0, 0, 0))
        #expect(queue.push(key(1, 0, 0)) == [key(0, 1, 0)])
        #expect(!queue.contains(key(0, 1, 0)))
        #expect(queue.next() == key(1, 0, 0) && queue.next() == key(0, 0, 0) && queue.next() == key(0, 2, 0) && queue.next() == nil)
    }

    @Test func aPlainPictureNeverKeepsAPageDocument() throws {
        try withStore { store in
            let (_, item) = try place(Self.pdf(), capturedPage: false, in: store)
            #expect(item.kind == .image && item.snapshot == nil)
        }
    }

    @Test func tilesCoverOnlyTheVisiblePartOfATallCard() {
        let card = CGRect(x: 100, y: 0, width: 400, height: 40_000)
        let page = CGSize(width: 1_000, height: 100_000)
        let level = EaselSnapshotTiling.level(pixelsPerPoint: 2 * 400 / 1_000)
        #expect(level == 0)
        let keys = EaselSnapshotTiling.tiles(visible: CGRect(x: 0, y: 20_000, width: 800, height: 600), card: card, page: page,
                                             level: 0, asset: "a.pdf")
        #expect(keys.map(\.column).max() == 1 && keys.map(\.column).min() == 0)
        #expect(keys.map(\.row).min() == 97 && keys.map(\.row).max() == 100)
        #expect(EaselSnapshotTiling.tiles(visible: CGRect(x: 0, y: 50_000, width: 800, height: 600), card: card, page: page,
                                          level: 0, asset: "a.pdf").isEmpty)
    }

    @Test(arguments: [(0.3, -1), (0.5, -1), (1.0, 0), (1.01, 1), (3.0, 2), (16.0, 4)])
    func zoomPicksTheNextSharperLevel(pixelsPerPoint: Double, expected: Int) {
        #expect(EaselSnapshotTiling.level(pixelsPerPoint: CGFloat(pixelsPerPoint)) == expected)
    }

    @Test func edgeTilesStopAtThePageAndMapBackOntoTheCard() {
        let page = CGSize(width: 1_000, height: 1_300)
        let region = EaselSnapshotTiling.region(column: 1, row: 2, level: 0, page: page)
        #expect(region == CGRect(x: 512, y: 1_024, width: 488, height: 276))
        let onCard = EaselSnapshotTiling.canvasRect(of: region, card: CGRect(x: 10, y: 20, width: 500, height: 650), page: page)
        #expect(onCard == CGRect(x: 266, y: 532, width: 244, height: 138))
    }

    @Test func aTileIsRenderedFromThePageAtItsLevel() throws {
        let snapshot = try #require(CaptureSnapshotPDF(data: Self.pdf()))
        let top = try #require(EaselSnapshotTiling.render(snapshot, key: EaselSnapshotTileKey(asset: "a.pdf", level: 1, column: 0, row: 0)))
        #expect(top.width == 200 && top.height == 512)
        let rep = NSBitmapImageRep(cgImage: top)
        #expect((rep.colorAt(x: 100, y: 10)?.redComponent ?? 0) > 0.8)
        #expect((rep.colorAt(x: 100, y: 500)?.blueComponent ?? 0) > 0.8)
    }

    @Test func exportsDrawTheWholePageAsVectors() throws {
        let snapshot = try #require(CaptureSnapshotPDF(data: Self.pdf()))
        let context = try #require(CGContext(data: nil, width: 50, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 200)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        EaselSnapshotRenderer.draw(snapshot, asset: "a.pdf", picture: nil, pictureAsset: nil, in: NSRect(x: 0, y: 0, width: 50, height: 200), live: false)
        NSGraphicsContext.restoreGraphicsState()
        let rep = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        #expect((rep.colorAt(x: 25, y: 20)?.redComponent ?? 0) > 0.8)
        #expect((rep.colorAt(x: 25, y: 180)?.blueComponent ?? 0) > 0.8)
    }
}
