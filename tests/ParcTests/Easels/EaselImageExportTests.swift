import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import ParcCore
@testable import ParcEasels
@testable import ParcKit

struct EaselImageExportTests {
    @MainActor
    private func board(_ items: [EaselItem] = []) throws -> (EaselCanvasView, EaselSession) {
        let date = Date(timeIntervalSince1970: 0)
        let document = EaselDocument(id: UUID(), title: "Export board", createdAt: date, modifiedAt: date, items: items)
        let session = try EaselSession(inMemory: document, assets: [:])
        let canvas = makeTestEaselCanvas(session: session)
        canvas.appearance = NSAppearance(named: .aqua)
        return (canvas, session)
    }

    @MainActor
    private func attach(_ canvas: EaselCanvasView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return window
    }

    private func bytes(_ image: CGImage) -> Data {
        image.dataProvider!.data! as Data
    }

    private func pixel(_ image: CGImage, _ x: Double, _ y: Double, scale: Double = 2) -> (r: Double, g: Double, b: Double) {
        let data = bytes(image)
        let index = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
        return (Double(data[index]) / 255, Double(data[index + 1]) / 255, Double(data[index + 2]) / 255)
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @MainActor
    private func solidImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @MainActor @Test
    func anEmptyExportUsesOnePixelPerPointAtOneX() throws {
        let (canvas, _) = try board()
        let image = try #require(canvas.exportImage(backingScale: 1))
        #expect(image.width == Int(canvas.bounds.width))
        #expect(image.height == Int(canvas.bounds.width + 60))
    }

    @MainActor @Test(arguments: [false, true])
    func exportPaperUsesTheCanvasAppearance(_ dark: Bool) throws {
        let (canvas, _) = try board()
        canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let image = try #require(canvas.exportImage(backingScale: 2))
        let background = pixel(image, 5, 5)
        #expect(background.r == (dark ? 0 : 1) && background.g == background.r && background.b == background.r)
    }

    @MainActor @Test
    func exportDrawsTheSavedStrokeAndTint() throws {
        var box = EaselItem(kind: .rectangle, frame: .init(x: 40, y: 40, width: 100, height: 60)); box.color = "#D03030"
        let (canvas, _) = try board([box])
        let light = try #require(canvas.exportImage(backingScale: 2))
        let edge = pixel(light, 40.2, 70)
        #expect(edge.r > 0.7 && edge.g < 0.35, "The rectangle's saved stroke colour is drawn")
        let inside = pixel(light, 90, 70)
        #expect(inside.r > inside.g && inside.g < 0.99, "The rectangle's tinted fill is drawn")
    }

    @MainActor @Test
    func exportDrawsSavedText() throws {
        let words = EaselItem(kind: .text, frame: .init(x: 200, y: 30, width: 220, height: 60), text: "Exported words")
        let (canvas, _) = try board([words])
        let light = try #require(canvas.exportImage(backingScale: 2))
        let data = bytes(light)
        let ink = stride(from: 60, to: 180, by: 2).contains { y in
            stride(from: 400, to: 840, by: 2).contains { x in data[y * light.bytesPerRow + x * 4 + 1] < 127 }
        }
        #expect(ink)
    }

    @MainActor @Test
    func aStrokeDoesNotBreakAtAStripBoundary() throws {
        var seam = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 110, width: 60, height: 40)); seam.color = "#2040D0"
        let (canvas, _) = try board([seam])
        let light = try #require(canvas.exportImage(backingScale: 2))
        let seamRows = (254...257).map { pixel(light, 500.1, Double($0) / 2) }
        #expect(seamRows.allSatisfy { $0.b > 0.7 && $0.r < 0.35 }, "A stroke crossing a strip boundary has no seam")
    }

    @MainActor @Test
    func selectionChromeDoesNotChangeTheExportedPixels() throws {
        var box = EaselItem(kind: .rectangle, frame: .init(x: 40, y: 40, width: 100, height: 60)); box.color = "#D03030"
        let (canvas, _) = try board([box])
        let unselected = try #require(canvas.exportImage(backingScale: 1))
        canvas.selectAll(nil)
        let selected = try #require(canvas.exportImage(backingScale: 1))
        #expect(!canvas.selection.isEmpty)
        #expect(bytes(selected) == bytes(unselected))
    }

    @MainActor @Test
    func anExportKeepsItsSnapshotWhileTheTextEditorStaysOpen() throws {
        let words = EaselItem(kind: .text, frame: .init(x: 200, y: 30, width: 220, height: 60), text: "Exported words")
        let (canvas, session) = try board([words])
        let window = attach(canvas)
        defer { window.contentView = nil; window.close() }
        let light = try #require(canvas.exportImage(backingScale: 1))
        let lightBytes = bytes(light)
        canvas.beginEditing(words)
        let editor = try #require(canvas.editor)
        #expect(bytes(canvas.exportImage(backingScale: 1)!) == lightBytes, "Editing alone does not change the exported artwork")
        #expect(window.firstResponder === editor && canvas.subviews.contains(editor), "Export leaves the open text editor in place")
        let snapshot = canvas.exportImage(backingScale: 1)!
        editor.localUndo.groupsByEvent = false
        editor.localUndo.beginUndoGrouping()
        editor.insertText("Retyped", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.localUndo.endUndoGrouping()
        #expect(session.document.items.contains { $0.text == "Retyped" }, "Typing saves the edited text")
        #expect(bytes(snapshot) == lightBytes, "An export keeps the artwork of the moment it was asked for")
        #expect(bytes(canvas.exportImage(backingScale: 1)!) != lightBytes, "The edited object's saved text is exported while its editor is open")
        #expect(window.firstResponder === editor, "The editor still owns input after exporting")
    }

    @MainActor @Test
    func contentFarDownTheCanvasDeterminesExportHeight() throws {
        let circle = EaselItem(kind: .circle, frame: .init(x: 20, y: 2400, width: 80, height: 90))
        let (canvas, _) = try board([circle])
        #expect(canvas.exportImage(backingScale: 1)?.height == 2400 + 90 + 60)
    }

    @MainActor @Test
    func croppedExportHugsTheContents() throws {
        let circle = EaselItem(kind: .circle, frame: .init(x: 20, y: 2400, width: 80, height: 90))
        let (canvas, _) = try board([circle])
        let bounds = EaselVectorExport.contentBounds([circle])
        let image = try #require(canvas.exportImage(backingScale: 1, hugsContent: true))
        #expect(image.width == Int(bounds.width.rounded()))
        #expect(image.height == Int(bounds.height.rounded()))
    }

    @Test
    func tallExportScaleKeepsTheLongSideWithinItsLimit() {
        let height = 40_110.0
        let scale = EaselExportScale.capped(2, width: 800, height: height)
        #expect((height * scale).rounded() == EaselExportScale.maximumSide)
    }

    @MainActor @Test
    func aFixedCanvasExportsItsOwnSizeAndArtwork() throws {
        let now = Date(timeIntervalSince1970: 0)
        var mark = EaselItem(kind: .rectangle, frame: .init(x: 10, y: 10, width: 50, height: 30)); mark.color = "#D03030"
        let fixed = makeTestEaselCanvas(session: try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Capture", createdAt: now, modifiedAt: now, items: [mark]), assets: [:]))
        fixed.fixedCanvasSize = NSSize(width: 300, height: 200)
        let fixedImage = fixed.exportImage(backingScale: 2)!
        #expect(fixedImage.width == 600 && fixedImage.height == 400, "A fixed canvas exports exactly its bounds")
        #expect(pixel(fixedImage, 10.2, 20).r > 0.7, "A fixed canvas exports its saved artwork")
    }

    @MainActor @Test(arguments: [(UInt16(1), true, true, false, true), (1, true, false, false, false), (1, true, true, true, false), (2, true, true, false, false)])
    func onlyTheExportChordRequestsAnImage(_ keyCode: UInt16, _ command: Bool, _ shift: Bool, _ option: Bool, _ expected: Bool) throws {
        let (canvas, _) = try board()
        let window = attach(canvas)
        defer { window.contentView = nil; window.close() }
        window.makeFirstResponder(canvas)
        var modifiers: NSEvent.ModifierFlags = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        var requests = 0
        canvas.onExportImage = { requests += 1 }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                  characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
        canvas.keyDown(with: event)
        #expect(requests == (expected ? 1 : 0))
    }

    @MainActor @Test(arguments: [(Optional("Export board"), "Export board"), ("  ", "Untitled Easel"), (nil, "Untitled Easel")])
    func savePanelOffersTheFormatsAndAReadableName(_ title: String?, _ name: String) {
        _ = NSApplication.shared
        let panel = EaselImageExport.savePanel(title: title)
        #expect(panel.title == "Export Easel")
        #expect(panel.allowedContentTypes == [.png, .jpeg])
        #expect(panel.nameFieldStringValue == name)
    }

    @MainActor @Test(arguments: [("Easel.png", true), ("Easel.PNG", true), ("Easel.jpg", false), ("Easel", false)])
    func exportChoosesTheFileFormatAndPreservesItsDensity(_ filename: String, _ png: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(filename)
        let image = try solidImage(width: 24, height: 18)
        try EaselImageExport.write(image, scale: 2, to: url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let info = try properties(url)
        let type: UTType = png ? .png : .jpeg
        #expect(CGImageSourceGetType(source) as String? == type.identifier)
        #expect(info[kCGImagePropertyPixelWidth] as? Int == image.width)
        #expect(info[kCGImagePropertyDPIWidth] as? Double == 144)
    }

    @MainActor @Test(arguments: [false, true])
    func aNarrowImageBeyondTheJpegHeightLimitCanStillBePng(_ png: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(png ? "Tall.png" : "Tall.jpg")
        let image = try solidImage(width: 2, height: 65_536)
        if png {
            try EaselImageExport.write(image, scale: 1, to: url)
            let info = try properties(url)
            #expect(info[kCGImagePropertyPixelHeight] as? Int == image.height)
        } else {
            #expect(throws: CocoaError.self) { try EaselImageExport.write(image, scale: 1, to: url) }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @MainActor @Test
    func savingOverAnExportReplacesItsDimensionsAndDensity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Easel.png")
        try EaselImageExport.write(solidImage(width: 24, height: 18), scale: 2, to: url)
        try EaselImageExport.write(solidImage(width: 12, height: 9), scale: 1, to: url)
        let info = try properties(url)
        #expect(info[kCGImagePropertyPixelWidth] as? Int == 12)
        #expect(info[kCGImagePropertyDPIWidth] as? Double == 72)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["Easel.png"])
    }

    @MainActor @Test
    func exportUsesTheDensityFromAppKit() {
        let plainImage = NSImage(size: NSSize(width: 100, height: 50), flipped: false) { _ in true }
        #expect(EaselImageExport.pixelDensity() == CGFloat(plainImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!.width) / 100,
               "Export density is the one AppKit gives a no-context conversion")
    }

    @MainActor @Test
    func theFailureDialogOffersOneAcknowledgement() {
        _ = NSApplication.shared
        let failure = EaselImageExport.failureDialog()
        let texts = failure.panel.contentView!.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(texts == ["Exporting Easel", "Encountered problem exporting easel. Please try again later."]
               && failure.confirmButton.title == "OK" && failure.cancelButton == nil && failure.suppression == nil,
               "the export failure dialog wording with a single OK")
    }

    @MainActor @Test(arguments: [false, true])
    func exportRechecksTheOriginalOwnerAtTheScheduledStep(_ detach: Bool) throws {
        let (canvas, _) = try board()
        let window = attach(canvas)
        defer { window.contentView = nil; window.close() }
        var queued: (() -> Void)?
        var failedOwner: NSWindow?
        var checks = 0
        EaselImageExport.run(canvas: canvas, title: nil, in: window, schedule: { queued = $0 },
                             onFailure: { failedOwner = $0 }) {
            checks += 1
            return false
        }

        #expect(checks == 0)
        if detach { window.contentView = nil }
        let run = try #require(queued)
        run()
        #expect(checks == (detach ? 0 : 1))
        #expect(failedOwner === (detach ? nil : window))
    }

}
