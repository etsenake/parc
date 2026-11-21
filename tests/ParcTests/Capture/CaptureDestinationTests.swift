import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
private final class DestinationFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-capture-destinations-" + UUID().uuidString, isDirectory: true)
    let png: Data
    let url = URL(string: "https://example.com/original/page")!
    let store: EaselStore

    nonisolated static func pngBytes() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 0x7f, bitmap.bytesPerRow * bitmap.pixelsHigh)
        return bitmap.representation(using: .png, properties: [:])!
    }

    init() throws {
        store = try EaselStore(directory: directory)
        png = Self.pngBytes()
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var input: EaselImageInput { EaselImageInput(pngData: png, sourceURL: url, pageTitle: "Captured page", valid: { true }) }

    func placed() throws -> EaselImagePlacement.Result {
        try EaselImagePlacement.place(input, in: store, destinationID: nil, newTitle: "Captured page")
    }

    func existingEasel() throws -> EaselSession {
        let session = try store.create(title: "Existing destination")
        try session.perform("Add original text") {
            $0.items.append(EaselItem(kind: .text, frame: EaselRect(x: 1, y: 2, width: 100, height: 180), text: "Keep me"))
        }
        return session
    }

    static let layout = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 0, y: 350),
                                           region: .init(x: 20, y: 40, width: 300, height: 200))

    func capturedInput() -> EaselImageInput {
        var captured = input
        captured.capturedPage = true
        captured.captureLayout = Self.layout
        captured.capturedAt = Date(timeIntervalSince1970: 1234567)
        return captured
    }

    func card() throws -> (session: EaselSession, card: EaselItem, id: UUID) {
        let created = try placed()
        let placement = try EaselImagePlacement.place(capturedInput(), in: store, destinationID: created.id, newTitle: "Ignored")
        return (created.session, placement.session.document.items.last!, created.id)
    }
}

struct CaptureMessagePayloadTests {
    private let png = DestinationFixture.pngBytes()
    private let url = URL(string: "https://example.com/original/page")!

    @MainActor @Test func messagePreparationRetainsThePreviewedPNG() {
        #expect(CaptureMessagePayload(png: png, sourceAddress: url.absoluteString)?.pngData == png)
    }

    @MainActor @Test func aNativeMessageReceivesTheOriginalURLThenTheImage() throws {
        let message = try #require(CaptureMessagePayload(png: png, sourceAddress: url.absoluteString))
        #expect(message.items.count == 2 && message.items[0] as? URL == url && message.items[1] is NSImage)
    }

    @MainActor @Test func aMessageNeverInventsATitleOrBranding() throws {
        let message = try #require(CaptureMessagePayload(png: png, sourceAddress: url.absoluteString))
        #expect(!message.items.contains { $0 is String })
    }

    @MainActor @Test func anAbsentOriginalURLSharesJustTheImage() throws {
        let imageOnly = try #require(CaptureMessagePayload(png: png, sourceAddress: ""))
        #expect(imageOnly.sourceURL == nil && imageOnly.items.count == 1 && imageOnly.items[0] is NSImage)
    }

    @MainActor @Test func aRelativeAddressIsNotFabricatedIntoASourceURL() {
        #expect(CaptureMessagePayload(png: png, sourceAddress: "relative/path")?.sourceURL == nil)
    }

    @MainActor @Test func badImageDataCannotPrepareAMessage() {
        #expect(CaptureMessagePayload(png: Data("invalid".utf8), sourceAddress: url.absoluteString) == nil)
    }
}

struct CaptureEaselPlacementTests {
    @MainActor @Test func aNewEaselUsesTheSuppliedTitle() throws {
        #expect(try DestinationFixture().placed().title == "Captured page")
    }

    @MainActor @Test func theImportSessionSurvivesExactDestinationAdoption() throws {
        let fixture = try DestinationFixture()
        let created = try fixture.placed()
        #expect(try fixture.store.load(created.id) === created.session)
    }

    @MainActor @Test func insertionRetainsRealUndoHistory() throws {
        let fixture = try DestinationFixture()
        let created = try fixture.placed()
        #expect(try fixture.store.load(created.id).canUndo)
    }

    @MainActor @Test func theImageKeepsItsSourceProvenance() throws {
        let fixture = try DestinationFixture()
        let item = try fixture.placed().session.document.items[0]
        #expect(item.kind == .image && item.url == fixture.url.absoluteString)
    }

    @MainActor @Test func thePixelAspectRatioSurvives() throws {
        let item = try DestinationFixture().placed().session.document.items[0]
        #expect(item.frame.width / item.frame.height == 1.5)
    }

    @MainActor @Test func theImportedAssetKeepsTheExactPNGBytes() throws {
        let fixture = try DestinationFixture()
        let session = try fixture.placed().session
        let item = session.document.items[0]
        #expect(try Data(contentsOf: session.assetURL(try #require(item.assetID))) == fixture.png)
    }

    @MainActor @Test func theImageTransactionSurvivesReload() throws {
        let fixture = try DestinationFixture()
        let created = try fixture.placed()
        let fresh = try EaselStore(directory: fixture.directory).load(created.id)
        #expect(fresh.document.items == created.session.document.items)
    }

    @MainActor @Test func realUndoRemovesTheImage() throws {
        let session = try DestinationFixture().placed().session
        try session.undo()
        #expect(session.document.items.isEmpty)
    }

    @MainActor @Test func realRedoRestoresTheImage() throws {
        let session = try DestinationFixture().placed().session
        try session.undo()
        try session.redo()
        #expect(session.document.items.count == 1)
    }

    @MainActor @Test func anExistingDestinationIsTheOriginalSharedSession() throws {
        let fixture = try DestinationFixture()
        let second = try fixture.existingEasel()
        let placed = try EaselImagePlacement.place(fixture.input, in: fixture.store, destinationID: second.document.id, newTitle: "Ignored")
        #expect(placed.session === second)
    }

    @MainActor @Test func placementNeverRenamesAnExistingEasel() throws {
        let fixture = try DestinationFixture()
        let second = try fixture.existingEasel()
        let placed = try EaselImagePlacement.place(fixture.input, in: fixture.store, destinationID: second.document.id, newTitle: "Ignored")
        #expect(placed.title == "Existing destination")
    }

    @MainActor @Test func existingContentsRemainIntact() throws {
        let fixture = try DestinationFixture()
        let second = try fixture.existingEasel()
        _ = try EaselImagePlacement.place(fixture.input, in: fixture.store, destinationID: second.document.id, newTitle: "Ignored")
        #expect(second.document.items[0].text == "Keep me")
    }

    @MainActor @Test func theImageIsAppendedBeneathExistingContent() throws {
        let fixture = try DestinationFixture()
        let second = try fixture.existingEasel()
        _ = try EaselImagePlacement.place(fixture.input, in: fixture.store, destinationID: second.document.id, newTitle: "Ignored")
        #expect(second.document.items[1].frame.y >= 214)
    }

    @MainActor @Test func oneUndoReversesOnlyThePlacement() throws {
        let fixture = try DestinationFixture()
        let second = try fixture.existingEasel()
        _ = try EaselImagePlacement.place(fixture.input, in: fixture.store, destinationID: second.document.id, newTitle: "Ignored")
        try second.undo()
        #expect(second.document.items.count == 1 && second.document.items[0].text == "Keep me")
    }

    @MainActor @Test func aPageCaptureBecomesASnapshotCardWithSourceProvenance() throws {
        let fixture = try DestinationFixture()
        let (_, card, _) = try fixture.card()
        #expect(card.kind == .webCard && card.url == fixture.url.absoluteString && card.text == "Captured page")
    }

    @MainActor @Test func aSnapshotCardCarriesTheCapturedTimeAndImageAsset() throws {
        let (_, card, _) = try DestinationFixture().card()
        #expect(card.capturedAt != nil && card.assetID != nil)
    }

    @MainActor @Test func aSnapshotCardKeepsTheOriginalPNGBytes() throws {
        let fixture = try DestinationFixture()
        let (session, card, _) = try fixture.card()
        #expect(try Data(contentsOf: session.assetURL(try #require(card.assetID))) == fixture.png)
    }

    @MainActor @Test func aSnapshotCardRoundTripsThroughReload() throws {
        let fixture = try DestinationFixture()
        let (_, card, id) = try fixture.card()
        #expect(try EaselStore(directory: fixture.directory).load(id).document.items.last == card)
    }

    @MainActor @Test func theOriginalGeometryPersistsWithoutStartingALivePage() throws {
        let (_, card, _) = try DestinationFixture().card()
        #expect(card.captureLayout == DestinationFixture.layout && card.liveCapture != true)
    }

    @MainActor @Test func insertionKeepsTheOriginalAcquisitionTime() throws {
        let fixture = try DestinationFixture()
        let (_, card, _) = try fixture.card()
        #expect(card.capturedAt == fixture.capturedInput().capturedAt)
    }

    @MainActor @Test func liveAdmissionRetainsTheSourceAndImmutableImage() throws {
        let (session, card, _) = try DestinationFixture().card()
        try session.perform("Make live") { $0.items[$0.items.count - 1].liveCapture = true }
        let live = try #require(session.document.items.last)
        #expect(live.ownsEmbeddedPage && live.assetID == card.assetID && live.captureLayout == DestinationFixture.layout && live.url == card.url)
    }

    @MainActor @Test func undoingLiveModeRestoresTheCapturedImageRecord() throws {
        let (session, card, _) = try DestinationFixture().card()
        try session.perform("Make live") { $0.items[$0.items.count - 1].liveCapture = true }
        try session.undo()
        #expect(session.document.items.last == card)
    }

    @MainActor @Test func aSnapshotUndoPreservesTheOrdinaryImageImport() throws {
        let (session, card, _) = try DestinationFixture().card()
        try session.undo()
        #expect(!session.document.items.contains { $0.id == card.id } && session.document.items.first?.kind == .image)
    }

    @MainActor @Test func redoRestoresTheExactCapturedCard() throws {
        let (session, card, _) = try DestinationFixture().card()
        try session.undo()
        try session.redo()
        #expect(session.document.items.last == card)
    }

    @MainActor @Test func invalidGeometryNeverPersists() throws {
        let (session, _, _) = try DestinationFixture().card()
        #expect(throws: (any Error).self) {
            try session.perform("Bad capture") { $0.items[$0.items.count - 1].captureLayout?.region.width = .infinity }
        }
    }

    @MainActor @Test func liveModeRequiresGeometry() throws {
        let (session, _, _) = try DestinationFixture().card()
        #expect(throws: (any Error).self) { try session.perform("Unowned live") { $0.items[0].liveCapture = true } }
    }

    @MainActor @Test func rejectedCaptureRecordsPreserveTheSavedDocument() throws {
        let (session, _, _) = try DestinationFixture().card()
        let unchanged = session.document
        _ = try? session.perform("Bad capture") { $0.items[$0.items.count - 1].captureLayout?.region.width = .infinity }
        _ = try? session.perform("Unowned live") { $0.items[0].liveCapture = true }
        #expect(session.document == unchanged)
    }

    @MainActor @Test func aRegionOutsideTheViewportIsInvalid() {
        let layout = EaselCaptureLayout(viewport: .init(x: 300, y: 200), scroll: .init(x: 0, y: 0),
                                        region: .init(x: 200, y: 0, width: 200, height: 100))
        #expect(!layout.isValid)
    }

    @MainActor @Test func anExpiredSourceCreatesNoDocument() throws {
        let fixture = try DestinationFixture()
        let before = try fixture.store.list().count
        let expired = EaselImageInput(pngData: fixture.png, sourceURL: fixture.url, pageTitle: "Expired", valid: { false })
        #expect(throws: (any Error).self) { _ = try EaselImagePlacement.place(expired, in: fixture.store, destinationID: nil, newTitle: "Expired") }
        #expect(try fixture.store.list().count == before)
    }

    @MainActor @Test func aDeletedDestinationIsNeverSubstituted() throws {
        let fixture = try DestinationFixture()
        let second = try fixture.existingEasel()
        let deletedID = second.document.id
        try fixture.store.delete(deletedID)
        let remaining = try fixture.store.list().count
        #expect(throws: (any Error).self) {
            _ = try EaselImagePlacement.place(fixture.input, in: fixture.store, destinationID: deletedID, newTitle: "Substitute")
        }
        #expect(try fixture.store.list().count == remaining)
    }

    @MainActor @Test func anUndecodableImageCreatesNoEasel() throws {
        let fixture = try DestinationFixture()
        let before = try fixture.store.list().count
        let invalid = EaselImageInput(pngData: Data("not an image".utf8), sourceURL: fixture.url, pageTitle: "Invalid", valid: { true })
        #expect(throws: (any Error).self) { _ = try EaselImagePlacement.place(invalid, in: fixture.store, destinationID: nil, newTitle: "Invalid") }
        #expect(try fixture.store.list().count == before)
    }
}
