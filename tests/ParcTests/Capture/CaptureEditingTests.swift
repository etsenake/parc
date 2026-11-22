import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
private struct CaptureEditingFixture {
    let sourceImage: CGImage
    let png: Data
    let id = UUID().uuidString + ".png"
    let original: EaselDocument
    let source: EaselItem
    let draft: EaselSession
    let canvas: EaselCanvasView

    init() throws {
        _ = NSApplication.shared
        let pattern = Self.context(width: 40, height: 20, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        pattern.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        pattern.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        pattern.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        pattern.fill(CGRect(x: 0, y: 10, width: 40, height: 10))
        sourceImage = pattern.makeImage()!
        png = NSBitmapImageRep(cgImage: sourceImage).representation(using: .png, properties: [:])!
        source = EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 20, height: 10), assetID: id)
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        original = EaselDocument(id: UUID(), title: "Capture", createdAt: date, modifiedAt: date, items: [source])
        draft = try EaselSession(inMemory: original, assets: [id: png])
        canvas = makeTestEaselCanvas(session: draft)
        canvas.fixedCanvasSize = NSSize(width: 20, height: 10)
        canvas.resizeCanvas(viewport: NSSize(width: 800, height: 600))
    }

    static func context(width: Int, height: Int, space: CGColorSpace) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixel.interpolationQuality = .none
        pixel.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: pixel.data!.assumingMemoryBound(to: UInt8.self), count: 4))
    }

    func withShape() -> EaselItem {
        canvas.setInsertionColor(.green)
        canvas.insert(kind: .rectangle)
        return draft.document.items[1]
    }

    func withRichText() throws -> EaselRichText {
        let attributed = NSAttributedString(string: "Rich", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black, .link: "https://example.com",
        ])
        var rich = try EaselRichTextCodec.snapshot(attributed)
        rich.runs[0].attributes.semanticInk = .noteBody
        rich.runs[0].attributes.ink = "#000000FF"
        let text = EaselItem(kind: .text, frame: .init(x: 1, y: 1, width: 18, height: 8), text: "Rich", richText: rich)
        try draft.perform("Text") { $0.items.append(text) }
        canvas.selectAll(nil)
        canvas.setInsertionColor(.green)
        return rich
    }
}

struct CaptureEditingTests {
    @MainActor @Test func anInMemorySourceRetainsItsExactPNG() throws {
        let fixture = try CaptureEditingFixture()
        #expect(try fixture.draft.assetData(fixture.id) == fixture.png)
    }

    @MainActor @Test func aFixedImageCanvasCannotGrowWithTheViewport() throws {
        let fixture = try CaptureEditingFixture()
        #expect(fixture.canvas.frame.size == NSSize(width: 20, height: 10))
    }

    @MainActor @Test func outputKeepsTheSourceBackingPixels() throws {
        let fixture = try CaptureEditingFixture()
        let rendered = try fixture.canvas.renderImage(pixelSize: NSSize(width: 40, height: 20), backingScale: 2)
        #expect(rendered.width == 40 && rendered.height == 20)
    }

    @MainActor @Test(arguments: [4, 18])
    func artworkRenderingPreservesOrientationAndSourceColors(_ y: Int) throws {
        let fixture = try CaptureEditingFixture()
        let rendered = try fixture.canvas.renderImage(pixelSize: NSSize(width: 40, height: 20), backingScale: 2)
        #expect(CaptureEditingFixture.sample(rendered, x: 4, y: y) == CaptureEditingFixture.sample(fixture.sourceImage, x: 4, y: y))
    }

    @MainActor @Test func theRecoveredShapeToolUsesTheCurrentAnnotationInk() throws {
        let fixture = try CaptureEditingFixture()
        let shape = fixture.withShape()
        #expect(fixture.draft.document.items.count == 2 && shape.color == "#00FF00")
    }

    @MainActor @Test func toolsStayInsideTinyCapturedImages() throws {
        let fixture = try CaptureEditingFixture()
        let frame = fixture.withShape().frame
        #expect(frame.x >= 0 && frame.y >= 0 && frame.x + frame.width <= 20 && frame.y + frame.height <= 10)
    }

    @MainActor @Test func oneUndoRestoresTheOriginalCanvas() throws {
        let fixture = try CaptureEditingFixture()
        _ = fixture.withShape()
        try fixture.draft.undo()
        #expect(fixture.draft.document.items == [fixture.source])
    }

    @MainActor @Test func redoPreservesAnnotationIdentity() throws {
        let fixture = try CaptureEditingFixture()
        let shape = fixture.withShape()
        try fixture.draft.undo()
        try fixture.draft.redo()
        #expect(fixture.draft.document.items[1].id == shape.id)
    }

    @MainActor @Test func aReopenedEditorPreservesTheOriginalAndAnnotationObjects() throws {
        let fixture = try CaptureEditingFixture()
        _ = fixture.withShape()
        let resumed = try EaselSession(inMemory: fixture.draft.document, assets: fixture.draft.inMemoryAssets)
        #expect(resumed.document.items == fixture.draft.document.items)
    }

    @MainActor @Test func cancellingALaterEditorCannotMutateTheAcceptedSnapshot() throws {
        let fixture = try CaptureEditingFixture()
        let shape = fixture.withShape()
        let resumed = try EaselSession(inMemory: fixture.draft.document, assets: fixture.draft.inMemoryAssets)
        try resumed.perform("Move") { $0.items[1].frame.x = 3 }
        #expect(fixture.draft.document.items[1].frame.x == shape.frame.x)
    }

    @MainActor @Test func aFailedEditPreservesTheCommittedDraft() throws {
        let fixture = try CaptureEditingFixture()
        let shape = fixture.withShape()
        let resumed = try EaselSession(inMemory: fixture.draft.document, assets: fixture.draft.inMemoryAssets)
        #expect(throws: (any Error).self) { try resumed.perform("Invalid") { $0.items[1].frame.width = .nan } }
        #expect(resumed.document.items[1].frame.width == shape.frame.width)
    }

    @MainActor @Test func theFixedCaptureEditorCannotCreateABrowserProvider() throws {
        let fixture = try CaptureEditingFixture()
        #expect(!fixture.canvas.pasteWebLink(URL(string: "https://example.com")!))
        #expect(fixture.canvas.placeEmptyObject(.browser) == nil)
    }

    @MainActor @Test func arrowEndpointsTrackTheClippedCanvasDimensions() throws {
        let fixture = try CaptureEditingFixture()
        fixture.canvas.insert(kind: .arrow)
        let arrow = try #require(fixture.draft.document.items.last)
        #expect(arrow.points.last!.x <= 20 && arrow.points.first!.y <= 10)
    }

    @MainActor @Test func freshCaptureShapesKeepTheClassicOutlineLook() throws {
        let fixture = try CaptureEditingFixture()
        let shape = fixture.withShape()
        #expect(shape.shape == nil && shape.fill == nil && shape.strokeWidth == nil && shape.strokeDash == nil && shape.rotation == nil)
    }

    @MainActor @Test func freshCaptureArrowsKeepTheClassicStraightArrow() throws {
        let fixture = try CaptureEditingFixture()
        fixture.canvas.insert(kind: .arrow)
        let arrow = try #require(fixture.draft.document.items.last)
        #expect(arrow.startHead == nil && arrow.endHead == nil && arrow.routing == nil && arrow.strokeWidth == nil)
    }

    @MainActor @Test func aFixedCanvasIsACaptureBoard() throws {
        #expect(try CaptureEditingFixture().canvas.isCaptureBoard)
    }

    @MainActor @Test func anUnfixedCanvasIsNotACaptureBoard() throws {
        let fixture = try CaptureEditingFixture()
        #expect(!makeTestEaselCanvas(session: fixture.draft).isCaptureBoard)
    }

    @MainActor @Test(arguments: [EaselToolbarControl.createSection, .sectionTitle, .link, .connectorLabel, .altText])
    func theCaptureToolbarDropsControlsThatDoNotApply(_ control: EaselToolbarControl) throws {
        #expect(!(try CaptureEditingFixture().canvas.captureBoardAllows(control)))
    }

    @MainActor @Test(arguments: [EaselToolbarControl.color, .startHead, .endHead, .routing, .crop, .group, .more])
    func theCaptureToolbarKeepsAnnotationStylingAndArranging(_ control: EaselToolbarControl) throws {
        #expect(try CaptureEditingFixture().canvas.captureBoardAllows(control))
    }

    private static let pasteKinds: [EaselItemKind] = [.rectangle, .section, .table, .code, .sticky, .link, .stamp]
    private static let pasteItems = pasteKinds.map { EaselItem(kind: $0, frame: .init(x: 0, y: 0, width: 4, height: 4)) }

    @MainActor @Test func captureBoardPasteKeepsOnlyAnnotationKinds() throws {
        let fixture = try CaptureEditingFixture()
        #expect(fixture.canvas.captureBoardPasteable(Self.pasteItems).map(\.kind) == [.rectangle, .sticky, .stamp])
    }

    @MainActor @Test func anEaselPasteKeepsEveryKind() throws {
        let fixture = try CaptureEditingFixture()
        #expect(makeTestEaselCanvas(session: fixture.draft).captureBoardPasteable(Self.pasteItems).count == Self.pasteKinds.count)
    }

    @MainActor @Test func captureObjectsNeverTakeObjectLinks() throws {
        #expect(try CaptureEditingFixture().canvas.objectLinkTarget == nil)
    }

    @MainActor @Test func aFormattedAnnotationColorReplacesAuthoredAndSemanticForegroundRuns() throws {
        let fixture = try CaptureEditingFixture()
        _ = try fixture.withRichText()
        let runs = try #require(fixture.draft.document.items.last?.richText?.runs)
        #expect(runs.allSatisfy { $0.attributes.ink == "#00FF00FF" && $0.attributes.semanticInk == nil })
    }

    @MainActor @Test func colorKeepsTheRichFontAndLinkAttributes() throws {
        let fixture = try CaptureEditingFixture()
        let rich = try fixture.withRichText()
        let run = try #require(fixture.draft.document.items.last?.richText?.runs.first)
        #expect(run.attributes.font == rich.runs[0].attributes.font && run.attributes.link == rich.runs[0].attributes.link)
    }

    @MainActor @Test func renderedRichTextUsesTheSelectedColor() throws {
        let fixture = try CaptureEditingFixture()
        _ = try fixture.withRichText()
        let changed = try #require(fixture.draft.document.items.last)
        let displayed = try #require(EaselRichTextCodec.attributed(changed).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(displayed.usingColorSpace(.sRGB)!.greenComponent > 0.99)
    }

    @MainActor @Test func oneUndoRestoresTheExactRichAnnotationAttributes() throws {
        let fixture = try CaptureEditingFixture()
        let rich = try fixture.withRichText()
        try fixture.draft.undo()
        #expect(fixture.draft.document.items.last?.richText == rich)
    }

    @MainActor @Test func theFirstEscapeClearsTheObjectSelection() throws {
        let fixture = try CaptureEditingFixture()
        var cancelled = 0
        fixture.canvas.onImageEditingCancel = { cancelled += 1 }
        _ = fixture.withShape()
        fixture.canvas.cancelOperation(nil)
        #expect(cancelled == 0)
    }

    @MainActor @Test func anIdleImageCanvasEscapeReachesEditorCancellation() throws {
        let fixture = try CaptureEditingFixture()
        var cancelled = 0
        fixture.canvas.onImageEditingCancel = { cancelled += 1 }
        fixture.canvas.cancelOperation(nil)
        #expect(cancelled == 1)
    }

    @MainActor @Test func anAnnotatedWideGamutCaptureRetainsItsOriginalColorSpace() throws {
        let fixture = try CaptureEditingFixture()
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let wide = CaptureEditingFixture.context(width: 40, height: 20, space: p3)
        wide.setFillColor(CGColor(colorSpace: p3, components: [1, 0.2, 0, 1])!)
        wide.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let widePNG = NSBitmapImageRep(cgImage: wide.makeImage()!).representation(using: .png, properties: [:])!
        let session = try EaselSession(inMemory: fixture.original, assets: [fixture.id: widePNG])
        let canvas = makeTestEaselCanvas(session: session)
        canvas.fixedCanvasSize = NSSize(width: 20, height: 10)
        canvas.resizeCanvas(viewport: .zero)
        canvas.insert(kind: .circle)
        let rendered = try canvas.renderImage(pixelSize: NSSize(width: 40, height: 20), backingScale: 2, colorSpace: p3)
        #expect(rendered.colorSpace?.name == CGColorSpace.displayP3)
    }

    @MainActor @Test func libraryMessagesShareTheImageAndTheOriginalAddressWithoutATitle() throws {
        let fixture = try CaptureEditingFixture()
        let message = try #require(CaptureLibrarySharePayload(png: fixture.png, sourceAddress: "https://example.com/original?q=1", destination: .message))
        #expect(message.items.count == 2 && message.items[0] is NSImage && message.items[1] as? String == "https://example.com/original?q=1")
    }

    @MainActor @Test func capturedItemAirDropSendsTheImageAndNeverThePageURL() throws {
        let fixture = try CaptureEditingFixture()
        let airDrop = try #require(CaptureLibrarySharePayload(png: fixture.png, sourceAddress: "https://example.com", destination: .airDrop))
        #expect(airDrop.items.count == 1 && airDrop.items[0] is NSImage)
    }

    @MainActor @Test func anInvalidImageRefusesAShareItem() {
        #expect(CaptureLibrarySharePayload(png: Data([1, 2]), sourceAddress: "https://example.com", destination: .message) == nil)
    }

    @MainActor @Test func operatingSystemCancellationStaysDistinctFromShareFailure() {
        #expect(CaptureLibrarySharing.isCancellation(CocoaError(.userCancelled)))
    }

    @MainActor @Test func aRealServiceFailureRemainsAnError() {
        #expect(!CaptureLibrarySharing.isCancellation(CocoaError(.fileReadUnknown)))
    }
}
