import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct CaptureDestinationTests {
    private let url = URL(string: "https://example.com/original/page")!

    @MainActor
    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try #require(bitmap.bitmapData)
        memset(pixels, 0x7f, bitmap.bytesPerRow * bitmap.pixelsHigh)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor
    private func withStore(_ run: (EaselStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(EaselStore(directory: directory))
    }

    @MainActor @Test
    func messageSharingUsesTheOriginalURLAndImage() throws {
        let data = try png()
        let message = try #require(CaptureMessagePayload(png: data, sourceAddress: url.absoluteString))
        #expect(message.pngData == data)
        #expect(message.items.count == 2)
        #expect(message.items.first as? URL == url)
        #expect(message.items.last is NSImage)
    }

    @MainActor @Test(arguments: ["", "relative/path"])
    func aMissingOrRelativeAddressSharesOnlyTheImage(_ address: String) throws {
        let data = try png()
        let message = try #require(CaptureMessagePayload(png: data, sourceAddress: address))
        #expect(message.sourceURL == nil)
        #expect(message.items.count == 1 && message.items.first is NSImage)
    }

    @MainActor @Test
    func anInvalidImageCannotBeShared() {
        #expect(CaptureMessagePayload(png: Data("invalid".utf8), sourceAddress: url.absoluteString) == nil)
    }

    @Test
    func rankingsUseOnlyTheCurrentProfilesLatestActivity() {
        let profile = UUID(), otherProfile = UUID()
        let first = UUID(), second = UUID(), inactive = UUID()
        let summaries = [
            EaselSummary(id: first, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1),
            EaselSummary(id: second, title: "Travel", modifiedAt: Date(timeIntervalSince1970: 900), itemCount: 2),
            EaselSummary(id: inactive, title: "Research", modifiedAt: Date(timeIntervalSince1970: 999), itemCount: 0)
        ]
        let destinations = CaptureEaselDestination.catalog(documents: summaries, activity: [
            .init(id: first, profileID: profile, date: Date(timeIntervalSince1970: 800)),
            .init(id: first, profileID: profile, date: Date(timeIntervalSince1970: 100)),
            .init(id: second, profileID: profile, date: Date(timeIntervalSince1970: 400)),
            .init(id: inactive, profileID: otherProfile, date: Date(timeIntervalSince1970: 2000))
        ], profileID: profile)
        #expect(CaptureEaselDestination.ranked(destinations).map(\.id) == [first, second, inactive])
    }

    @MainActor @Test
    func aNewEaselPreservesTheOriginalImageAndProvenance() throws {
        try withStore { store in
            let data = try png()
            let input = EaselImageInput(pngData: data, sourceURL: url, pageTitle: "Captured page", valid: { true })
            let placed = try EaselImagePlacement.place(input, in: store, destinationID: nil, newTitle: "Captured page")
            let session = try store.load(placed.id)
            let item = try #require(session.document.items.first)
            let asset = try #require(item.assetID)
            #expect(placed.title == "Captured page" && session === placed.session)
            #expect(item.kind == .image && item.url == url.absoluteString)
            #expect(item.frame.width / item.frame.height == 1.5)
            #expect(try session.assetData(asset) == data)
            #expect(try EaselStore(directory: store.directory).load(placed.id).document.items == [item])
        }
    }

    @MainActor @Test
    func placementAddsAnUndoableImageBelowExistingContent() throws {
        try withStore { store in
            let input = EaselImageInput(pngData: try png(), sourceURL: url, pageTitle: "Page", valid: { true })
            let original = EaselItem(kind: .text, frame: .init(x: 1, y: 2, width: 100, height: 180), text: "Keep me")
            let session = try store.create(title: "Existing destination")
            try session.perform("Seed") { $0.items = [original] }
            let placed = try EaselImagePlacement.place(input, in: store, destinationID: session.document.id, newTitle: "Ignored")
            let image = try #require(session.document.items.last)
            #expect(placed.session === session && placed.title == "Existing destination")
            #expect(session.document.items.first == original)
            #expect(image.kind == .image && image.frame.y >= original.frame.y + original.frame.height + 32)
            try session.undo()
            #expect(session.document.items == [original])
            try session.redo()
            #expect(session.document.items == [original, image])
        }
    }

    @MainActor @Test
    func aPageCaptureRetainsItsOriginalGeometryAndBytes() throws {
        try withStore { store in
            let data = try png()
            var input = EaselImageInput(pngData: data, sourceURL: url, pageTitle: "Captured page", valid: { true })
            let layout = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 0, y: 350),
                region: .init(x: 20, y: 40, width: 300, height: 200))
            input.capturedPage = true
            input.captureLayout = layout
            input.capturedAt = Date(timeIntervalSince1970: 1_234_567)
            let placed = try EaselImagePlacement.place(input, in: store, destinationID: nil, newTitle: "Captured page")
            let card = try #require(placed.session.document.items.first)
            let asset = try #require(card.assetID)
            #expect(card.kind == .webCard && card.url == url.absoluteString && card.text == "Captured page")
            #expect(card.captureLayout == layout && card.capturedAt == input.capturedAt && card.liveCapture != true)
            #expect(try placed.session.assetData(asset) == data)
            let reopened = try EaselStore(directory: store.directory).load(placed.id)
            #expect(reopened.document.items == [card])
        }
    }

    enum InvalidPlacement: CaseIterable {
        case expired, deleted, malformedImage
    }

    @MainActor @Test(arguments: InvalidPlacement.allCases)
    func refusedPlacementDoesNotCreateAnyEasel(_ invalid: InvalidPlacement) throws {
        try withStore { store in
            var destination: UUID?
            if invalid == .deleted {
                let deleted = try store.create(title: "Deleted destination").document.id
                try store.delete(deleted)
                destination = deleted
            }
            let data = invalid == .malformedImage ? Data("invalid".utf8) : try png()
            let input = EaselImageInput(pngData: data, sourceURL: url, pageTitle: "Page", valid: { invalid != .expired })
            #expect(throws: (any Error).self) {
                _ = try EaselImagePlacement.place(input, in: store, destinationID: destination, newTitle: "Substitute")
            }
            #expect(try store.list().isEmpty)
        }
    }
}
