import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct CaptureEditingTests {
    @MainActor static var checks = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        let pattern = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pattern.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); pattern.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        pattern.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); pattern.fill(CGRect(x: 0, y: 10, width: 40, height: 10))
        let sourceImage = pattern.makeImage()!
        let png = NSBitmapImageRep(cgImage: sourceImage).representation(using: .png, properties: [:])!, id = UUID().uuidString + ".png", date = Date()
        func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
            let sample = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sample.interpolationQuality = .none
            sample.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: sample.data!.assumingMemoryBound(to: UInt8.self), count: 4))
        }
        let source = EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 20, height: 10), assetID: id)
        let original = EaselDocument(id: UUID(), title: "Capture", createdAt: date, modifiedAt: date, items: [source])
        let draft = try EaselSession(inMemory: original, assets: [id: png])
        let retained = try draft.assetData(id)
        expect(retained == png, "In-memory source retains exact PNG")
        let canvas = EaselCanvasView(session: draft); canvas.fixedCanvasSize = NSSize(width: 20, height: 10)
        canvas.resizeCanvas(viewport: NSSize(width: 800, height: 600))
        expect(canvas.frame.size == NSSize(width: 20, height: 10), "Fixed image canvas cannot grow with the viewport")
        let rendered = try canvas.renderImage(pixelSize: NSSize(width: 40, height: 20), backingScale: 2)
        expect(rendered.width == 40 && rendered.height == 20, "Output retains source backing pixels")
        expect(sample(rendered, x: 4, y: 2) == sample(sourceImage, x: 4, y: 2) && sample(rendered, x: 4, y: 18) == sample(sourceImage, x: 4, y: 18), "Artwork rendering preserves top/bottom orientation and source colors")
        canvas.setInsertionColor(.green); canvas.insert(kind: .rectangle)
        expect(draft.document.items.count == 2 && draft.document.items[1].color == "#00FF00", "Recovered shape tool uses current annotation ink")
        let shape = draft.document.items[1]
        expect(shape.frame.x >= 0 && shape.frame.y >= 0 && shape.frame.x + shape.frame.width <= 20 && shape.frame.y + shape.frame.height <= 10, "Tools stay available on tiny captured images")
        try draft.undo(); expect(draft.document.items == [source], "One undo restores original canvas")
        try draft.redo(); expect(draft.document.items[1].id == shape.id, "Redo preserves annotation identity")
        let resumed = try EaselSession(inMemory: draft.document, assets: draft.inMemoryAssets)
        expect(resumed.document.items == draft.document.items, "Reopened editor preserves original and annotation objects")
        try resumed.perform("Move") { $0.items[1].frame.x = 3 }
        expect(draft.document.items[1].frame.x == shape.frame.x, "Cancelling a later editor cannot mutate accepted snapshot")
        do { try resumed.perform("Invalid") { $0.items[1].frame.width = .nan }; preconditionFailure("Invalid geometry accepted") } catch {}
        expect(resumed.document.items[1].frame.width == shape.frame.width, "Failed edit preserves committed draft")
        expect(!canvas.insertLink("https://example.com", browser: true), "Fixed capture editor cannot create a browser provider")
        canvas.insert(kind: .arrow)
        expect(draft.document.items.last!.points.last!.x <= 20 && draft.document.items.last!.points.first!.y <= 10, "Arrow endpoints track clipped fixed-canvas dimensions")
        let freshArrow = draft.document.items.last!
        expect(shape.shape == nil && shape.fill == nil && shape.strokeWidth == nil && shape.strokeDash == nil && shape.rotation == nil, "Fresh capture shapes keep the classic outline look")
        expect(freshArrow.startHead == nil && freshArrow.endHead == nil && freshArrow.routing == nil && freshArrow.strokeWidth == nil, "Fresh capture arrows keep the classic straight arrow")
        expect(canvas.isCaptureBoard && !EaselCanvasView(session: draft).isCaptureBoard, "Only fixed canvases count as capture boards")
        expect([EaselToolbarControl.createSection, .sectionTitle, .link, .connectorLabel, .altText].allSatisfy { !canvas.captureBoardAllows($0) }, "Capture toolbar drops sections, links, labels and alt text")
        expect([EaselToolbarControl.color, .startHead, .endHead, .routing, .crop, .group, .more].allSatisfy(canvas.captureBoardAllows), "Capture toolbar keeps annotation styling and arranging")
        let pasteKinds: [EaselItemKind] = [.rectangle, .section, .table, .code, .sticky, .link, .stamp]
        let pasteItems = pasteKinds.map { EaselItem(kind: $0, frame: .init(x: 0, y: 0, width: 4, height: 4)) }
        expect(canvas.captureBoardPasteable(pasteItems).map(\.kind) == [.rectangle, .sticky, .stamp], "Capture paste keeps only annotation kinds")
        expect(EaselCanvasView(session: draft).captureBoardPasteable(pasteItems).count == pasteKinds.count, "Easel paste keeps every kind")
        expect(canvas.objectLinkTarget == nil, "Capture objects never take object links")
        let attributed = NSAttributedString(string: "Rich", attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black, .link: "https://example.com"])
        var rich = try EaselRichTextCodec.snapshot(attributed)
        rich.runs[0].attributes.semanticInk = .noteBody; rich.runs[0].attributes.ink = "#000000FF"
        let text = EaselItem(kind: .text, frame: .init(x: 1, y: 1, width: 18, height: 8), text: "Rich", richText: rich)
        try draft.perform("Text") { $0.items.append(text) }
        canvas.selectAll(nil); canvas.setInsertionColor(.green)
        let changedText = draft.document.items.last!
        expect(changedText.richText!.runs.allSatisfy { $0.attributes.ink == "#00FF00FF" && $0.attributes.semanticInk == nil }, "Formatted annotation color replaces authored and semantic foreground runs")
        expect(changedText.richText!.runs[0].attributes.font == rich.runs[0].attributes.font && changedText.richText!.runs[0].attributes.link == rich.runs[0].attributes.link, "Color keeps rich font and link attributes")
        let displayedColor = EaselRichTextCodec.attributed(changedText).attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        expect(displayedColor.usingColorSpace(.sRGB)!.greenComponent > 0.99, "Rendered rich text uses the selected color")
        try draft.undo(); expect(draft.document.items.last!.richText == rich, "One undo restores exact rich annotation attributes")
        var cancelled = 0; canvas.onImageEditingCancel = { cancelled += 1 }
        canvas.cancelOperation(nil); expect(cancelled == 0, "First Escape clears current object selection")
        canvas.cancelOperation(nil); expect(cancelled == 1, "Idle image canvas Escape reaches editor cancellation")
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let wideContext = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        wideContext.setFillColor(CGColor(colorSpace: p3, components: [1, 0.2, 0, 1])!); wideContext.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let widePNG = NSBitmapImageRep(cgImage: wideContext.makeImage()!).representation(using: .png, properties: [:])!
        let wideSession = try EaselSession(inMemory: original, assets: [id: widePNG])
        let wideCanvas = EaselCanvasView(session: wideSession); wideCanvas.fixedCanvasSize = NSSize(width: 20, height: 10)
        wideCanvas.resizeCanvas(viewport: .zero); wideCanvas.insert(kind: .circle)
        let wideRendered = try wideCanvas.renderImage(pixelSize: NSSize(width: 40, height: 20), backingScale: 2, colorSpace: p3)
        expect(wideRendered.colorSpace?.name == CGColorSpace.displayP3, "Annotated wide-gamut capture retains original RGB color space")
        let message = CaptureLibrarySharePayload(png: png, sourceAddress: "https://example.com/original?q=1", destination: .message)!
        expect(message.items.count == 2 && message.items[0] is NSImage && message.items[1] as? String == "https://example.com/original?q=1", "Library Messages uses image plus original address text, without title")
        let airDrop = CaptureLibrarySharePayload(png: png, sourceAddress: "https://example.com", destination: .airDrop)!
        expect(airDrop.items.count == 1 && airDrop.items[0] is NSImage, "Captured-item AirDrop sends image, never source page URL")
        expect(CaptureLibrarySharePayload(png: Data([1, 2]), sourceAddress: "https://example.com", destination: .message) == nil, "Invalid image refuses share payload")
        expect(CaptureLibrarySharing.isCancellation(CocoaError(.userCancelled)), "OS cancellation stays distinct from share failure")
        expect(!CaptureLibrarySharing.isCancellation(CocoaError(.fileReadUnknown)), "Real service failure remains an error")
        print("Capture editing checks passed: \(checks)")
    }
}
