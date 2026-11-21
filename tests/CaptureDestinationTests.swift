import AppKit

@main
struct CaptureDestinationTests {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(value(), message)
    }
    @MainActor static func mustThrow(_ message: String, _ body: () throws -> Void) {
        assertions += 1
        do { try body(); preconditionFailure(message) } catch { }
    }
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-capture-destinations-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 0x7f, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        let url = URL(string: "https://example.com/original/page")!
        let message = CaptureMessagePayload(png: png, sourceAddress: url.absoluteString)!
        expect(message.pngData == png, "Message preparation retains the currently previewed PNG")
        expect(message.items.count == 2 && message.items[0] as? URL == url && message.items[1] is NSImage,
               "Native message receives the original URL followed by the actual image")
        expect(!message.items.contains { $0 is String }, "Capture does not invent title or branding attribution")
        let imageOnly = CaptureMessagePayload(png: png, sourceAddress: "")!
        expect(imageOnly.sourceURL == nil && imageOnly.items.count == 1 && imageOnly.items[0] is NSImage,
               "Absent original URL preserves image-only sharing")
        expect(CaptureMessagePayload(png: png, sourceAddress: "relative/path")!.sourceURL == nil,
               "A relative address is not fabricated into a source URL")
        expect(CaptureMessagePayload(png: Data("invalid".utf8), sourceAddress: url.absoluteString) == nil,
               "Bad image data cannot prepare a message")

        let profile = UUID(), otherProfile = UUID()
        let first = UUID(), secondID = UUID(), inactive = UUID()
        let summaries = [
            EaselSummary(id: first, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1),
            EaselSummary(id: secondID, title: "Travel", modifiedAt: Date(timeIntervalSince1970: 900), itemCount: 2),
            EaselSummary(id: inactive, title: "Research", modifiedAt: Date(timeIntervalSince1970: 999), itemCount: 0)
        ]
        let destinations = CaptureEaselDestination.catalog(documents: summaries, activity: [
            .init(id: first, profileID: profile, date: Date(timeIntervalSince1970: 800)),
            .init(id: first, profileID: profile, date: Date(timeIntervalSince1970: 100)),
            .init(id: secondID, profileID: profile, date: Date(timeIntervalSince1970: 400)),
            .init(id: inactive, profileID: otherProfile, date: Date(timeIntervalSince1970: 2000))
        ], profileID: profile)
        expect(CaptureEaselDestination.ranked(destinations).map(\.id) == [first, secondID, inactive],
               "Last activity wins over document edits; another profile never contributes recency")
        let input = EaselImageInput(pngData: png, sourceURL: url, pageTitle: "Captured page", valid: { true })
        let created = try EaselImagePlacement.place(input, in: store, destinationID: nil, newTitle: "Captured page")
        expect(created.title == "Captured page", "New Easel uses the supplied title")
        let adopted = try store.load(created.id)
        expect(adopted === created.session, "Import session survives exact destination adoption")
        expect(adopted.canUndo, "Insertion retains real undo history")
        let item = adopted.document.items[0]
        expect(item.kind == .image && item.url == url.absoluteString, "Exact source provenance survives")
        expect(item.frame.width / item.frame.height == 1.5, "Pixel aspect ratio survives")
        expect(try! Data(contentsOf: adopted.assetURL(item.assetID!)) == png, "Imported asset keeps exact PNG bytes")
        let fresh = try EaselStore(directory: directory).load(created.id)
        expect(fresh.document.items == adopted.document.items, "Actual image transaction survives reload")
        try adopted.undo()
        expect(adopted.document.items.isEmpty, "Real undo removes the image")
        try adopted.redo()
        expect(adopted.document.items.count == 1, "Real redo restores the image")

        let second = try store.create(title: "Existing destination")
        try second.perform("Add original text") {
            $0.items.append(EaselItem(kind: .text, frame: EaselRect(x: 1, y: 2, width: 100, height: 180), text: "Keep me"))
        }
        let placed = try EaselImagePlacement.place(input, in: store, destinationID: second.document.id, newTitle: "Ignored")
        expect(placed.session === second, "Existing destination is the original shared session")
        expect(placed.title == "Existing destination", "Placement does not rename an existing Easel")
        expect(second.document.items[0].text == "Keep me", "Existing contents remain intact")
        expect(second.document.items[1].frame.y >= 214, "Image is appended beneath existing content")
        try second.undo()
        expect(second.document.items.count == 1 && second.document.items[0].text == "Keep me", "One undo reverses only placement")

        var captured = input; captured.capturedPage = true
        let layout = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 0, y: 350),
            region: .init(x: 20, y: 40, width: 300, height: 200))
        captured.captureLayout = layout; captured.capturedAt = Date(timeIntervalSince1970: 1234567)
        let cardPlacement = try EaselImagePlacement.place(captured, in: store, destinationID: created.id, newTitle: "Ignored")
        let card = cardPlacement.session.document.items.last!
        expect(card.kind == .webCard && card.url == url.absoluteString && card.text == "Captured page", "Page capture produces a genuine snapshot card with source provenance")
        expect(card.capturedAt != nil && card.assetID != nil, "Snapshot identity includes actual captured time and image asset")
        expect(try! Data(contentsOf: adopted.assetURL(card.assetID!)) == png, "Snapshot card retains original PNG bytes without live substitution")
        expect(try! EaselStore(directory: directory).load(created.id).document.items.last == card, "Snapshot card round-trips exact identity and metadata")
        expect(card.captureLayout == layout && card.liveCapture != true, "Original geometry persists without silently starting a live page")
        expect(card.capturedAt == captured.capturedAt, "Easel insertion keeps the original acquisition time")
        try adopted.perform("Make live") { $0.items[$0.items.count - 1].liveCapture = true }
        let live = adopted.document.items.last!
        expect(live.ownsEmbeddedPage && live.assetID == card.assetID && live.captureLayout == layout && live.url == card.url,
            "Live admission retains original source and immutable image")
        try adopted.undo()
        expect(adopted.document.items.last == card, "Undo live mode restores the exact captured image record")
        try adopted.undo()
        expect(!adopted.document.items.contains { $0.id == card.id } && adopted.document.items.first?.kind == .image, "One snapshot undo preserves ordinary image import")
        try adopted.redo()
        expect(adopted.document.items.last == card, "Redo restores the exact captured card")

        let unchanged = adopted.document
        mustThrow("Invalid geometry never persists") {
            try adopted.perform("Bad capture") { $0.items[$0.items.count - 1].captureLayout?.region.width = .infinity }
        }
        mustThrow("Live mode requires geometry") {
            try adopted.perform("Unowned live") { $0.items[0].liveCapture = true }
        }
        expect(adopted.document == unchanged, "Rejected capture records preserve the saved document")
        expect(!EaselCaptureLayout(viewport: .init(x: 300, y: 200), scroll: .init(x: 0, y: 0),
            region: .init(x: 200, y: 0, width: 200, height: 100)).isValid, "Out-of-viewport regions cannot be used")
        let count = try store.list().count
        let expired = EaselImageInput(pngData: png, sourceURL: url, pageTitle: "Expired", valid: { false })
        mustThrow("Expired source must not create a document") {
            _ = try EaselImagePlacement.place(expired, in: store, destinationID: nil, newTitle: "Expired")
        }
        expect(try! store.list().count == count, "Rejected source leaves no new Easel")
        let deletedID = second.document.id
        try store.delete(deletedID)
        mustThrow("Deleted row must not create a substitute destination") {
            _ = try EaselImagePlacement.place(input, in: store, destinationID: deletedID, newTitle: "Substitute")
        }
        expect(try! store.list().count == count - 1, "Missing UUID stays missing")
        let invalidPNG = EaselImageInput(pngData: Data("not an image".utf8), sourceURL: url, pageTitle: "Invalid", valid: { true })
        mustThrow("Undecodable image must not create an Easel") {
            _ = try EaselImagePlacement.place(invalidPNG, in: store, destinationID: nil, newTitle: "Invalid")
        }
        expect(try! store.list().count == count - 1, "Invalid image leaves catalog unchanged")
        print("Capture destinations: \(assertions) assertions passed")
    }
}
