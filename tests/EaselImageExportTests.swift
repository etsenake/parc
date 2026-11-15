import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct EaselImageExportTests {
    @MainActor static var count = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; if !value() { fatalError(message) }
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-export-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Export board")
        var box = EaselItem(kind: .rectangle, frame: .init(x: 40, y: 40, width: 100, height: 60)); box.color = "#D03030"
        let words = EaselItem(kind: .text, frame: .init(x: 200, y: 30, width: 220, height: 60), text: "Exported words")
        var seam = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 110, width: 60, height: 40)); seam.color = "#2040D0"
        try session.perform("Seed") { $0.items = [box, words, seam] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        func pixel(_ data: [UInt8], _ image: CGImage, _ x: Double, _ y: Double, scale: Double = 2) -> (r: Double, g: Double, b: Double) {
            let i = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
            return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
        }

        NSApp.appearance = NSAppearance(named: .aqua)
        let width = canvas.bounds.width
        guard let light = canvas.exportImage(backingScale: 2) else { fatalError("The canvas produced no export image") }
        let lightBytes = bytes(light)
        expect(light.width == Int(width) * 2 && light.height == Int(width + 60) * 2,
               "Content above a canvas-width square exports the width-square plus 60 points at the backing scale")
        let paper = pixel(lightBytes, light, 5, 5)
        expect(paper.r > 0.99 && paper.g > 0.99 && paper.b > 0.99, "A light app exports over white")
        let edge = pixel(lightBytes, light, 40.2, 70)
        expect(edge.r > 0.7 && edge.g < 0.35, "The rectangle's saved stroke colour is drawn")
        let inside = pixel(lightBytes, light, 90, 70)
        expect(inside.r > inside.g && inside.g < 0.99, "The rectangle's tinted fill is drawn")
        var ink = 0
        for y in stride(from: 30.0, to: 90, by: 1) { for x in stride(from: 200.0, to: 420, by: 1) where pixel(lightBytes, light, x, y).g < 0.5 { ink += 1 } }
        expect(ink > 50, "Saved text is drawn into the export")
        let seamRows = (254...257).map { pixel(lightBytes, light, 500.1, Double($0) / 2) }
        expect(seamRows.allSatisfy { $0.b > 0.7 && $0.r < 0.35 }, "A stroke crossing a strip boundary has no seam")

        func screen() -> Data {
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep); return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }
        let unselected = screen()
        canvas.selectAll(nil)
        expect(screen() != unselected, "Selection is visible in the canvas's own drawing")
        expect(bytes(canvas.exportImage(backingScale: 2)!) == lightBytes, "Selection outlines and handles are not exported")

        canvas.cancelOperation(nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: 300, y: 60), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseUp(with: event) }
        }
        window.makeFirstResponder(canvas); canvas.keyDown(with: key(36, []))
        guard let editor = window.firstResponder as? EaselStyledTextView else { fatalError("The text object did not enter editing") }
        expect(bytes(canvas.exportImage(backingScale: 2)!) == lightBytes, "Editing alone does not change the exported artwork")
        expect(window.firstResponder === editor && canvas.subviews.contains(editor), "Export leaves the open text editor in place")
        let snapshot = canvas.exportImage(backingScale: 2)!
        editor.localUndo.groupsByEvent = false
        editor.localUndo.beginUndoGrouping()
        editor.insertText("Retyped", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.localUndo.endUndoGrouping()
        expect(session.document.items.contains { $0.text == "Retyped" }, "Typing saves the edited text")
        expect(bytes(snapshot) == lightBytes, "An export keeps the artwork of the moment it was asked for")
        expect(bytes(canvas.exportImage(backingScale: 2)!) != lightBytes, "The edited object's saved text is exported while its editor is open")
        expect(window.firstResponder === editor, "The editor still owns input after exporting")
        canvas.cancelOperation(nil)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        let dark = canvas.exportImage(backingScale: 1)!
        let night = pixel(bytes(dark), dark, 5, 5, scale: 1)
        expect(night.r < 0.01 && night.g < 0.01 && night.b < 0.01, "A dark app exports over black")
        expect(dark.width == Int(width) && dark.height == Int(width + 60), "A 1x window exports one pixel per point")
        NSApp.appearance = nil

        let far = try store.create(title: "Far")
        try far.perform("Seed") { $0.items = [EaselItem(kind: .circle, frame: .init(x: 20, y: 2400, width: 80, height: 90))] }
        let farCanvas = EaselCanvasView(session: far)
        expect(farCanvas.exportImage(backingScale: 1)?.height == 2400 + 90 + 60, "Content below the width-square extends the export to its bottom plus 60 points")
        let empty = try store.create(title: "Empty")
        let emptyCanvas = EaselCanvasView(session: empty)
        expect(emptyCanvas.exportImage(backingScale: 1)?.height == Int(emptyCanvas.bounds.width + 60), "An empty Easel exports the width-square plus 60 points")

        let tall = try store.create(title: "Tall")
        try tall.perform("Seed") { $0.items = [EaselItem(kind: .rectangle, frame: .init(x: 20, y: 40_000, width: 100, height: 50))] }
        let tallImage = EaselCanvasView(session: tall).exportImage(backingScale: 2)!
        func peakMegabytes() -> Int { var usage = rusage(); getrusage(RUSAGE_SELF, &usage); return usage.ru_maxrss / 1_048_576 }
        func properties(_ url: URL) -> [CFString: Any]? {
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        }
        func rawMegabytes(_ image: CGImage) -> Int { image.bytesPerRow * image.height / 1_048_576 }
        var before = peakMegabytes()
        let tallPNG = directory.appendingPathComponent("Tall.png")
        try EaselImageExport.write(tallImage, scale: 2, to: tallPNG)
        expect(tallImage.height == 80_220 && properties(tallPNG)?[kCGImagePropertyPixelHeight] as? Int == 80_220, "A 40,110-point Easel exports every row as PNG")
        expect(peakMegabytes() - before < rawMegabytes(tallImage) / 2, "PNG encoding streams to the file without the whole raw image")
        let tallJPEG = directory.appendingPathComponent("Tall.jpg")
        expect((try? EaselImageExport.write(tallImage, scale: 2, to: tallJPEG)) == nil && !FileManager.default.fileExists(atPath: tallJPEG.path),
               "JPEG's 65,535-pixel limit refuses it and leaves no file")
        let jpegTall = try store.create(title: "JPEG tall")
        try jpegTall.perform("Seed") { $0.items = [EaselItem(kind: .rectangle, frame: .init(x: 20, y: 30_000, width: 100, height: 50))] }
        let jpegImage = EaselCanvasView(session: jpegTall).exportImage(backingScale: 2)!
        before = peakMegabytes()
        try EaselImageExport.write(jpegImage, scale: 2, to: tallJPEG)
        expect(properties(tallJPEG)?[kCGImagePropertyPixelHeight] as? Int == 60_220, "A 30,110-point Easel fits JPEG")
        expect(peakMegabytes() - before < rawMegabytes(jpegImage) / 2, "JPEG encoding streams to the file without the whole raw image")

        let now = Date()
        var mark = EaselItem(kind: .rectangle, frame: .init(x: 10, y: 10, width: 50, height: 30)); mark.color = "#D03030"
        let fixed = EaselCanvasView(session: try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Capture", createdAt: now, modifiedAt: now, items: [mark]), assets: [:]))
        fixed.fixedCanvasSize = NSSize(width: 300, height: 200)
        let fixedImage = fixed.exportImage(backingScale: 2)!
        expect(fixedImage.width == 600 && fixedImage.height == 400, "A fixed canvas exports exactly its bounds")
        expect(pixel(bytes(fixedImage), fixedImage, 10.2, 20).r > 0.7, "A fixed canvas exports its saved artwork")

        var requests = 0
        canvas.onExportImage = { requests += 1 }
        window.makeFirstResponder(canvas)
        canvas.keyDown(with: key(1, [.command, .shift]))
        expect(requests == 1, "Command-Shift-S on the canvas asks to export")
        canvas.keyDown(with: key(1, [.command])); canvas.keyDown(with: key(1, [.command, .shift, .option])); canvas.keyDown(with: key(2, [.command, .shift]))
        expect(requests == 1, "Other keys and modifier combinations do not export")
        var fixedRequests = 0
        fixed.onExportImage = { fixedRequests += 1 }
        window.contentView = fixed; window.makeFirstResponder(fixed)
        fixed.keyDown(with: key(1, [.command, .shift]))
        expect(fixedRequests == 1, "The capture editor's canvas exports too")
        window.contentView = canvas

        var chosen = 0
        let menu = EaselImageExport.shareMenu { chosen += 1 }
        menu.update()
        expect(menu.items.count == 1, "A local Easel's Share menu has only Export as Image")
        let row = menu.items[0]
        expect(row.title == "Export as Image" && row.keyEquivalent.isEmpty && row.isEnabled, "the row title, with no shortcut, enabled")
        expect(row.image?.size == NSSize(width: 14, height: 14) && row.image?.isTemplate == true, "The row shows a 14-point template glyph")
        expect(SidebarIconCatalog.font(.feather, size: 14).fontName == "feather", "The glyph comes from the bundled Feather font")
        if #available(macOS 27, *) { expect(row.preferredImageVisibility == .visible, "macOS 27 is asked to show the row's image") }
        menu.performActionForItem(at: 0)
        expect(chosen == 1, "Choosing the row exports")

        let panel = EaselImageExport.savePanel(title: session.document.title)
        expect(panel.title == "Export Easel" && panel.allowedContentTypes == [.png, .jpeg], "the panel title and PNG-then-JPEG types")
        expect(panel.nameFieldStringValue == "Export board", "The default name is the Easel's title")
        expect(EaselImageExport.savePanel(title: "  ").nameFieldStringValue == "Untitled Easel"
               && EaselImageExport.savePanel(title: nil).nameFieldStringValue == "Untitled Easel", "No title falls back to Untitled Easel")

        func encoded(_ name: String, _ image: CGImage = light, scale: CGFloat = 2) throws -> (prefix: [UInt8], dpi: Double, width: Int) {
            let url = directory.appendingPathComponent(name)
            try EaselImageExport.write(image, scale: scale, to: url)
            let data = try Data(contentsOf: url), properties = properties(url) ?? [:]
            return (Array(data.prefix(4)), properties[kCGImagePropertyDPIWidth] as? Double ?? 0, properties[kCGImagePropertyPixelWidth] as? Int ?? 0)
        }
        let png = try encoded("Export board.png"), jpeg = try encoded("Export board.jpg"), bare = try encoded("Export board"), upper = try encoded("BOARD.PNG")
        expect(png.prefix == [0x89, 0x50, 0x4E, 0x47] && upper.prefix == [0x89, 0x50, 0x4E, 0x47], "A .png name receives PNG bytes")
        expect(jpeg.prefix.starts(with: [0xFF, 0xD8, 0xFF]) && bare.prefix.starts(with: [0xFF, 0xD8, 0xFF]), "Other names receive a JPEG")
        expect(png.width == light.width && jpeg.width == light.width, "Encoding keeps every rendered pixel")
        expect(png.dpi == 144 && jpeg.dpi == 144, "A 2x export records its point size")
        let replaced = try encoded("Export board.png", dark, scale: 1)
        expect(replaced.width == dark.width && replaced.dpi == 72, "Saving over an existing file replaces it")
        let rep = NSBitmapImageRep(cgImage: light)
        rep.size = NSSize(width: width, height: width + 60)
        _ = try encoded("a.jpg")
        let defaultJPEG = try Data(contentsOf: directory.appendingPathComponent("a.jpg")), names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        expect(defaultJPEG == rep.representation(using: .jpeg, properties: [:]), "JPEG bytes equal NSBitmapImageRep's default encoding")
        expect(names.allSatisfy { !$0.hasPrefix("(A Document Being Saved") }, "No staging directory is left beside the export")

        let plainImage = NSImage(size: NSSize(width: 100, height: 50), flipped: false) { _ in true }
        expect(EaselImageExport.pixelDensity() == CGFloat(plainImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!.width) / 100,
               "Export density is the one AppKit gives a no-context conversion")

        let failure = EaselImageExport.failureDialog()
        let texts = failure.panel.contentView!.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        expect(texts == ["Exporting Easel", "Encountered problem exporting easel. Please try again later."]
               && failure.confirmButton.title == "OK" && failure.cancelButton == nil && failure.suppression == nil,
               "the export failure dialog wording with a single OK")
        expect(failure.panel.contentView!.frame.width == 450 && ParcBrandMark.image(.borderless) != nil,
               "The failure uses the default 450-point dialog with the app mark")

        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false; other.contentView = farCanvas
        defer { other.contentView = nil; other.close() }
        var admissions = 0
        EaselImageExport.run(canvas: canvas, title: nil, in: window) { admissions += 1; return false }
        EaselImageExport.run(canvas: farCanvas, title: nil, in: other) { admissions += 1; return false }
        expect(admissions == 0, "Nothing after the collection runs inside its reply")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        expect(admissions == 2, "Each export re-admits its owner after the wait")
        expect(window.attachedSheet != nil && other.attachedSheet != nil && window.attachedSheet !== other.attachedSheet,
               "An owner refused after the wait shows the failure, and each window shows its own")
        for owner in [window, other] { if let sheet = owner.attachedSheet { owner.endSheet(sheet) } }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        EaselImageExport.run(canvas: farCanvas, title: nil, in: other) { admissions += 1; return false }
        other.contentView = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        expect(admissions == 2 && other.attachedSheet == nil, "A canvas that left its window during the wait ends the export silently")
        print("Easel image export: \(count) checks passed")
    }
}
