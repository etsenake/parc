import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselPictureImportTests {
    private func canvas() throws -> EaselCanvasView {
        let date = Date(timeIntervalSince1970: 1)
        let document = EaselDocument(id: UUID(), title: "Pictures", createdAt: date, modifiedAt: date)
        return makeTestEaselCanvas(session: try EaselSession(inMemory: document, assets: [:]))
    }

    private func bitmap(width: Int, height: Int, noise: Bool) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try #require(bitmap.bitmapData)
        if noise { arc4random_buf(pixels, bitmap.bytesPerRow * height) } else { memset(pixels, 0x66, bitmap.bytesPerRow * height) }
        return bitmap
    }

    @Test func aPhotoWhosePNGWouldPassTheLimitStillLands() throws {
        let photo = try #require(try bitmap(width: 4000, height: 3000, noise: true)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        try #require(photo.count <= EaselStore.maximumAssetBytes)
        let asset = try canvas().preparedImageAsset(photo)
        #expect(asset.type == .png && asset.data.count <= EaselStore.maximumAssetBytes)
        #expect(abs(asset.pixelSize.width / asset.pixelSize.height - 4.0 / 3.0) < 0.01)
    }

    @Test func aPictureFileOverThirtyMegabytesDraggedInLands() throws {
        let data = try #require(try bitmap(width: 3300, height: 3300, noise: true).representation(using: .png, properties: [:]))
        try #require(data.count > EaselStore.maximumAssetBytes)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let media = try canvas().prepareMedia(url)
        #expect(media.type == .png && media.data.count <= EaselStore.maximumAssetBytes)
    }

    @Test func aPictureTallerThanAnEaselAllowsLandsScaledToFit() throws {
        let data = try #require(try bitmap(width: 400, height: EaselImagePlacement.maximumSide + 2000, noise: false)
            .representation(using: .png, properties: [:]))
        let asset = try canvas().preparedImageAsset(data)
        #expect(Int(asset.pixelSize.height) <= EaselImagePlacement.maximumSide)
        #expect(asset.data.count <= EaselStore.maximumAssetBytes)
    }

    @Test func aPictureWithinTheLimitsKeepsItsPixels() throws {
        let data = try #require(try bitmap(width: 640, height: 480, noise: false).representation(using: .png, properties: [:]))
        let asset = try canvas().preparedImageAsset(data)
        #expect(asset.pixelSize == CGSize(width: 640, height: 480))
    }
}
