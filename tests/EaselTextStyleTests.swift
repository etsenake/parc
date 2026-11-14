import AppKit
import CoreText

@main
struct EaselTextStyleTests {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }
    @MainActor static func rejects(_ message: String, _ operation: () throws -> Void) {
        assertions += 1
        do { try operation(); fatalError("Expected rejection: " + message) } catch { }
    }
    @MainActor static func main() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for family in EaselTextStyle.Family.allCases {
            for size in EaselTextStyle.Size.allCases {
                let style = EaselTextStyle(family: family, size: size)
                let payload = EaselStyledText(text: "Selected 👩🏽‍💻 café\nsecond line", style: style, color: "#194B93")
                let font = EaselTextAppearance.font(style)
                if family != .clean { expect(!font.fontName.hasPrefix("."), "Bundled family resolves without system fallback: \(family)/\(size)") }
                try payload.write(to: board)
                expect(try! EaselStyledText.read(from: board) == payload, "Private clipboard preserves exact text/style/color")
                expect(board.string(forType: .string) == payload.text, "Plain-text representation preserves Unicode")
                let rtf = board.data(forType: .rtf)!
                board.clearContents(); board.setData(rtf, forType: .rtf)
                let imported = try EaselStyledText.read(from: board)!
                let decoded = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                expect(imported.text == payload.text, "RTF preserves Unicode for every palette style")
                expect(try! EaselRichTextCodec.snapshot(imported.attributed) == EaselRichTextCodec.snapshot(decoded), "RTF preserves the actual exported font, including AppKit system-font substitution")
            }
        }
        func setRTF(_ text: NSAttributedString) throws {
            let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            board.clearContents(); board.setData(rtf, forType: .rtf)
        }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let mixed = NSMutableAttributedString(attributedString: base)
        mixed.addAttribute(.font, value: EaselTextAppearance.font(.init(family: .fancy, size: .h2)), range: NSRange(location: 4, length: 3))
        try setRTF(mixed)
        let importedMixed = try EaselStyledText.read(from: board)!
        expect(importedMixed.richText?.runs.count == 2, "Mixed fonts import as real range attributes")
        expect((importedMixed.attributed.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.pointSize == 28, "Second font range keeps its size")
        expect(try! EaselStyledText.plainText(from: board) == base.string, "Explicit plain-text paste extracts words from clipboard populated with RTF only")
        let linked = NSMutableAttributedString(attributedString: base)
        linked.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: 3))
        try setRTF(linked)
        let importedLink = try EaselStyledText.read(from: board)!
        expect(importedLink.richText?.runs.first?.attributes.link == "https://example.com", "Link range semantics survive RTF import")
        let spaced = NSMutableAttributedString(attributedString: base)
        let paragraph = NSMutableParagraphStyle(); paragraph.firstLineHeadIndent = 20
        spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        try setRTF(spaced)
        expect(try! EaselStyledText.read(from: board)?.richText?.runs.first?.attributes.paragraph?.firstIndent == 20, "Paragraph indentation survives RTF")
        paragraph.firstLineHeadIndent = 0; paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 90)]
        spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        try setRTF(spaced)
        expect(try! EaselStyledText.read(from: board)?.richText?.runs.first?.attributes.paragraph?.tabs.first?.alignment == NSTextAlignment.right.rawValue, "Custom tab alignment survives RTF")
        let list = NSTextList(markerFormat: .decimal, options: 0); list.startingItemNumber = 3
        paragraph.textLists = [list]; spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        let listed = try EaselStyledText.capture(spaced, style: .init(), color: "#252525")
        try listed.write(to: board)
        expect(try! EaselStyledText.read(from: board) == listed, "Private carrier preserves list marker and start metadata exactly")
        let unsafe = NSMutableAttributedString(attributedString: base)
        unsafe.addAttribute(.link, value: "javascript:alert(1)", range: NSRange(location: 0, length: 3))
        rejects("active scheme is not imported as an actionable link") { _ = try EaselStyledText.capture(unsafe, style: .init(), color: "#252525") }
        unsafe.removeAttribute(.link, range: NSRange(location: 0, length: unsafe.length))
        unsafe.addAttribute(.attachment, value: NSTextAttachment(), range: NSRange(location: 0, length: 1))
        rejects("attachments are never silently flattened") { _ = try EaselStyledText.capture(unsafe, style: .init(), color: "#252525") }
        board.clearContents(); board.setString("plain", forType: .string)
        expect(try! EaselStyledText.read(from: board) == nil, "Plain-text fallback stays with canvas")
        board.setData(Data("bad json".utf8), forType: EaselStyledText.pasteboardType)
        rejects("damaged private payload must not silently flatten") { _ = try EaselStyledText.read(from: board) }
        let legacy = EaselStyledText(version: 1, text: "Old styled text", style: .init(family: .mono, size: .h2), color: "#194B93")
        board.clearContents(); board.setData(try JSONEncoder().encode(legacy), forType: EaselStyledText.legacyPasteboardType)
        let restoredLegacy = try EaselStyledText.read(from: board)!
        expect(restoredLegacy.version == 3 && restoredLegacy.text == legacy.text && restoredLegacy.style == legacy.style && restoredLegacy.richText == nil, "Old private clipboard data remains readable without invented ranges")
        let view = EaselStyledTextView(frame: .zero)
        expect(view.undoManager === view.localUndo, "Text input owns its native undo manager")
        var fallback = 0
        view.onUndoDocument = { fallback += 1 }
        view.undo(nil)
        expect(fallback == 1, "Empty local history reaches document undo")
        try authoredFontEditing()
        try nativeEditing(board: board)
        try paragraphEditing(board: board)
        try markdownEditing(board: board)
        try inlineImages(board: board)
        try externalClipboard(board: board)
        try textFillLayout(board: board)
        try appearanceControls()
        print("EaselTextStyle: \(assertions) assertions passed")
    }

    @MainActor static func appearanceControls() throws {
        _ = NSApplication.shared
        let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root
        defer { window.contentView = nil; window.close() }
        let toolbar = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 44))
        toolbar.scrollerStyle = .legacy
        EaselAppearance.configureToolbarScroll(toolbar)
        toolbar.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 448, height: 44))
        toolbar.tile()
        expect(toolbar.scrollerStyle == .overlay, "Tool strip explicitly overrides legacy scrollbars with overlay presentation")
        expect(toolbar.contentSize.height >= 44 && toolbar.contentSize.width < 448, "Narrow native toolbar preserves full control height while requiring horizontal scrolling")
        let bar = EaselTextStyleBar(frame: NSRect(x: 20, y: 20, width: 50, height: 88)); root.addSubview(bar)
        func sizeBar() { bar.setFrameSize(NSSize(width: bar.preferredWidth, height: bar.preferredHeight)); bar.layoutSubtreeIfNeeded() }
        bar.onLayoutChange = { sizeBar() }
        bar.update(styles: [.init()]); sizeBar()
        let rail = bar.subviews.compactMap { $0 as? NSButton }
        expect(rail.count == 3 && rail.allSatisfy { $0.frame.size == NSSize(width: 24, height: 24) }, "Compact rail keeps three native24pt controls")
        expect(bar.preferredWidth == 50 && bar.preferredHeight == 88, "Closed disclosure uses recovered rail extent")
        let smaller = rail.first { $0.title == "−" }!, larger = rail.first { $0.title == "+" }!
        expect(!smaller.isEnabled && larger.isEnabled, "Body style visibly disables only decrease")
        let font = rail.first { $0.title == "Aa" }!
        font.performClick(nil)
        expect(font.state == .on && bar.preferredWidth == 254, "Font action exposes native disclosure without moving controls into another owner")
        let details = bar.subviews.first { $0 is EaselSurfaceView }!
        expect(!details.isHidden && details.frame.size == NSSize(width: 200, height: 85), "Object style disclosure keeps original font-panel extent")
        expect(details.subviews.filter { !$0.isHidden }.allSatisfy { details.bounds.contains($0.frame) }, "Visible object controls stay inside disclosure")
        let editor = EaselStyledTextView(frame: NSRect(x: 400, y: 20, width: 300, height: 100))
        editor.textStorage?.setAttributedString(EaselTextAppearance.attributed("Keep original text", style: .init(), color: "#194B93"))
        editor.setSelectedRange(NSRange(location: 0, length: 4)); root.addSubview(editor)
        let before = try EaselRichTextCodec.snapshot(editor.attributedString())
        bar.update(styles: [.init()], editor: editor); sizeBar()
        expect(details.subviews.filter { !$0.isHidden }.allSatisfy { details.bounds.contains($0.frame) }, "Rich disclosure contains every actual range control")
        let allFrames = details.subviews.filter { !$0.isHidden }.map(\.frame)
        expect(allFrames.enumerated().allSatisfy { index, frame in allFrames.dropFirst(index + 1).allSatisfy { !$0.intersects(frame) } }, "Native inspector controls never overlap")
        bar.collapse(); sizeBar()
        expect(details.isHidden && font.state == .off, "Collapsing removes disclosure controls from visible native subtree")
        bar.update(styles: [.init(size: .ultra)])
        expect(smaller.isEnabled && !larger.isEnabled, "Largest text style disables increase")
        let pill = EaselToolbarPill(frame: NSRect(x: 20, y: 220, width: 260, height: EaselAppearance.toolbarHeight))
        root.addSubview(pill)
        let selectedTool = EaselPaletteButton(title: "A", target: nil, action: nil)
        selectedTool.usesToolbarInk = true; selectedTool.font = .systemFont(ofSize: 16, weight: .medium)
        selectedTool.frame = NSRect(x: 8, y: 6, width: EaselAppearance.toolbarButton, height: EaselAppearance.toolbarButton)
        selectedTool.state = .on; pill.addSubview(selectedTool)
        let button = EaselPaletteButton(title: "Selected", target: nil, action: nil)
        button.frame = NSRect(x: 130, y: 170, width: 90, height: 28); button.state = .on; root.addSubview(button)
        let disabled = EaselPaletteButton(title: "Disabled", target: nil, action: nil)
        disabled.frame = NSRect(x: 230, y: 170, width: 90, height: 28); disabled.isEnabled = false; root.addSubview(disabled)
        let pressed = EaselPaletteButton(title: "Pressed", target: nil, action: nil)
        pressed.frame = NSRect(x: 330, y: 170, width: 90, height: 28); pressed.highlight(true); root.addSubview(pressed)
        root.appearance = NSAppearance(named: .aqua)
        root.layoutSubtreeIfNeeded()
        func pixels(_ view: NSView) -> NSBitmapImageRep {
            view.displayIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        let fill = pixels(pill).colorAt(x: 240, y: 22)!.usingColorSpace(.sRGB)!
        expect(fill.redComponent < 0.15 && fill.greenComponent < 0.18 && fill.blueComponent < 0.22 && fill.alphaComponent > 0.9,
               "Easel tool pill is a dark HUD")
        let selected = pixels(selectedTool).colorAt(x: 16, y: 16)!.usingColorSpace(.sRGB)!
        expect(selected.blueComponent > selected.redComponent && selected.greenComponent > 0.3 && selected.blueComponent > 0.4,
               "The selected tool cell fills steel blue")
        let link = EaselLinkEditor(value: "https://example.com")
        link.view.frame.origin = NSPoint(x: 400, y: 160); root.addSubview(link.view)
        font.performClick(nil); sizeBar()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            root.appearance = NSAppearance(named: appearance)
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
            let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            expect(data.count > 1000, "Native appearance renders actual controls in \(name) appearance")
            if let directory = ProcessInfo.processInfo.environment["PARC_EASEL_APPEARANCE_OUTPUT"] {
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("controls-" + name + ".png"))
            }
        }
        expect(try! EaselRichTextCodec.snapshot(editor.attributedString()) == before, "Appearance and disclosure transitions leave authored ranges unchanged")
        bar.update(styles: [])
        expect(bar.isHidden && details.isHidden, "Owner retirement hides the full disclosure")
        root.inheritSpaceContentAppearance(nil)
        expect(root.appearance == nil, "Easel paper inherits owner appearance without forcing Aqua")
        let dark = NSAppearance(named: .darkAqua)!
        root.inheritSpaceContentAppearance(dark)
        expect(root.appearance == dark, "Document host applies Space contentOverBackgroundAppearance DarkAqua")
        var paperHex = ""
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            paperHex = (try? EaselRichTextCodec.hex(EaselAppearance.surface)) ?? "unresolved"
        }
        expect(paperHex == "#000000FF", "Inherited dark appearance resolves named easel paper to black")
        root.inheritSpaceContentAppearance(nil)
        expect(root.appearance == nil, "Absent contentOverBackgroundAppearance clears the local override")
    }

    @MainActor static func textFillLayout(board: NSPasteboard) throws {
        let legacy = try JSONDecoder().decode(EaselTextStyle.self, from: Data(#"{"family":"clean","size":"body"}"#.utf8))
        expect(legacy.resolvedFill == .none && legacy.fill == nil, "Existing style JSON keeps fill off without migration")
        rejects("Unknown fill refuses rather than silently dropping styling") {
            _ = try JSONDecoder().decode(EaselTextStyle.self, from: Data(#"{"family":"clean","size":"body","fill":"unrecognized"}"#.utf8))
        }
        for family in EaselTextStyle.Family.allCases {
            for size in EaselTextStyle.Size.allCases {
                let style = EaselTextStyle(fill: .contentHugging, family: family, size: size)
                let value = EaselTextAppearance.attributed("Metrics gj\nShort", style: style, color: "#194B93")
                let layout = EaselTextLayout.Layout(value, width: 1000)
                let rects = EaselTextLayout.lineRects(manager: layout.manager, container: layout.container)
                expect(rects.count == 2 && rects.allSatisfy { $0.width > 0 && $0.height > 0 }, "Every actual bundled style produces visible glyph geometry")
                expect(rects[0].width > rects[1].width, "Fill hugs unequal lines instead of the object frame")
                let path = EaselTextLayout.fillPath(rects: rects, radius: EaselTextLayout.radius(style))
                expect(rects.allSatisfy { path.contains(NSPoint(x: $0.midX, y: $0.midY)) }, "Native rounded union contains each text line")
                let payload = try EaselStyledText.capture(value, style: style, color: "#194B93")
                try payload.write(to: board)
                expect(try! EaselStyledText.read(from: board) == payload, "Private clipboard preserves whole-object fill with original rich content")
                let editor = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
                editor.usesEaselObjectLayout = true; editor.isRichText = true; editor.drawsBackground = false
                editor.textContainerInset = EaselTextLayout.inset
                editor.textContainer?.lineFragmentPadding = EaselTextLayout.fragmentPadding
                editor.textContainer?.widthTracksTextView = true
                editor.textStorage?.setAttributedString(value); editor.objectStyle = style
                let before = try EaselRichTextCodec.snapshot(editor.attributedString())
                let editorRects = EaselTextLayout.lineRects(manager: editor.layoutManager!, container: editor.textContainer!)
                expect(editorRects == rects, "Editor and canvas share exact native line geometry for every family and size")
                expect(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor == .white,
                       "Filled editor uses temporary white presentation ink")
                editor.objectStyle.fill = nil
                expect(try! EaselRichTextCodec.snapshot(editor.attributedString()) == before,
                       "Toggling fill never rewrites authored range colors or fonts")
                expect(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil,
                       "Turning fill off restores authored ink")
            }
        }
        let blank = EaselTextLayout.Layout(EaselTextAppearance.attributed("  \n\t\n", style: .init(), color: "#252525"), width: 200)
        expect(EaselTextLayout.lineRects(manager: blank.manager, container: blank.container).isEmpty, "Whitespace-only lines receive no fill")
        let value = EaselTextAppearance.attributed("First\n\nThird 👩🏽‍💻 שלום", style: .init(), color: "#252525")
        let native = EaselTextLayout.Layout(value, width: 250)
        let lines = EaselTextLayout.lineRects(manager: native.manager, container: native.container)
        expect(lines.count == 2 && lines[1].minY > lines[0].maxY, "Empty line stays a real gap; Unicode and RTL use native glyph ranges")
        let gapPath = EaselTextLayout.fillPath(rects: lines, radius: 6)
        expect(!gapPath.contains(NSPoint(x: lines[0].midX, y: (lines[0].maxY + lines[1].minY) / 2)), "Fill does not bridge empty paragraph gaps")
        let stairs = [NSRect(x: 10, y: 10, width: 120, height: 30), NSRect(x: 10, y: 35, width: 60, height: 30)]
        let outline = EaselTextLayout.fillPath(rects: stairs, radius: 6)
        expect(outline.contains(NSPoint(x: 30, y: 38)) && !outline.contains(NSPoint(x: 110, y: 55)), "Union removes internal edges while retaining the shorter-line contour")
        expect(!outline.contains(NSPoint(x: 10.1, y: 10.1)), "Exterior corner is actually rounded")
        let smoothed = EaselTextLayout.smoothed([NSRect(x: 10, y: 0, width: 100, height: 25), NSRect(x: 12, y: 20, width: 100, height: 25)], radius: 6)
        expect(smoothed.allSatisfy { $0.minX == 10 && $0.maxX == 112 }, "Near neighboring edges expand to their common extrema")
        let strict = EaselTextLayout.smoothed([NSRect(x: 0, y: 0, width: 100, height: 25), NSRect(x: 6, y: 20, width: 100, height: 25)], radius: 6)
        expect(strict[0].minX == 0 && strict[1].minX == 6, "Exact-radius difference does not smooth")
        let cascade = EaselTextLayout.smoothed([20, 15, 10, 5, 10, 0].enumerated().map {
            NSRect(x: $0.element, y: $0.offset * 20, width: 100 - $0.element, height: 25)
        }, radius: 6)
        expect(cascade.map(\.minX) == [5, 5, 5, 0, 0, 0], "Each smoothing pass compares original adjacent edges before accumulating extrema")
        let palette = EaselTextStyleBar(frame: .zero)
        let checkbox = palette.subviews.flatMap { [$0] + $0.subviews }.compactMap { $0 as? NSButton }.first { $0.title == "Text fill" }!
        var changedFill: EaselTextStyle.Fill?
        palette.onFill = { changedFill = $0 }
        palette.update(styles: [.init(fill: .contentHugging)])
        checkbox.performClick(nil)
        expect(changedFill == EaselTextStyle.Fill.none, "Clicking an on tristate control turns fill off instead of accepting AppKit's mixed transition")
        palette.update(styles: [.init()]); checkbox.performClick(nil)
        expect(changedFill == .contentHugging, "Clicking off turns fill on")
        palette.update(styles: [.init(), .init(fill: .contentHugging)]); checkbox.performClick(nil)
        expect(changedFill == .contentHugging, "Clicking mixed fills the complete selection")
        for string in ["👩🏽‍💻", "漢字", "مرحبا"] {
            let fallback = EaselTextLayout.Layout(EaselTextAppearance.attributed(string, style: .init(family: .mono), color: "#252525"), width: 500)
            let fallbackRects = EaselTextLayout.lineRects(manager: fallback.manager, container: fallback.container)
            expect(fallbackRects.count == 1 && fallbackRects[0].width > 12, "Fallback glyphs retain real visible native geometry")
            var foundFallback = false
            for index in 0..<fallback.manager.numberOfGlyphs {
                let character = fallback.manager.characterIndexForGlyph(at: index)
                guard let font = fallback.storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont else { continue }
                var glyph = fallback.manager.cgGlyph(at: index)
                if glyph == 0xffff || fallback.manager.propertyForGlyph(at: index).contains(.null) { continue }
                let advance = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
                expect(advance.isFinite && advance > 0, "The laid-out native font owns each fallback CGGlyph advance")
                foundFallback = foundFallback || font.fontName != EaselTextAppearance.font(.init(family: .mono)).fontName
            }
            expect(foundFallback, "Native layout resolves the rendered fallback face before metrics are read")
        }
        let clipped = EaselTextLayout.Layout(value, width: 250, height: 30)
        expect(EaselTextLayout.lineRects(manager: clipped.manager, container: clipped.container).count == 1,
               "A resized short object renders only its actual text container's visible lines")
        let narrow = EaselTextLayout.Layout(value, width: 65)
        expect(narrow.height > native.height, "Measurement follows actual rewrapped native lines")
        let source = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let bytes = source.representation(using: .png, properties: [:])!
        let image = try EaselTextAttachments.image(data: bytes)
        let attachment = EaselTextAttachments.character(image, attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let imageLayout = EaselTextLayout.Layout(attachment, width: 240)
        let imageRects = EaselTextLayout.lineRects(manager: imageLayout.manager, container: imageLayout.container)
        expect(imageRects.count == 1 && imageRects[0].height >= 20, "Inline attachment uses its actual cell bounds without font-derived shrinking")
        expect(try! EaselRichTextCodec.snapshot(imageLayout.storage).runs[0].attributes.image?.data == bytes, "Layout preserves original attachment bytes")
    }

    @MainActor static func authoredFontEditing() throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        var failures = 0, boundaries = 0
        view.onClipboardError = { _ in failures += 1 }
        view.onEditBoundary = { boundaries += 1 }
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        func toggle(_ emphasis: EaselStyledTextView.Emphasis) {
            view.localUndo.beginUndoGrouping(); view.toggle(emphasis); view.localUndo.endUndoGrouping()
        }
        for emphasis in [EaselStyledTextView.Emphasis.bold, .italic] {
            load([.font: fallback, key: original, .foregroundColor: NSColor.black])
            let before = NSAttributedString(attributedString: view.attributedString())
            toggle(emphasis)
            expect(failures == 0 && view.hasEmphasis(emphasis), "Rendered emoji edits the original authored font's trait")
            let payload = try EaselRichTextCodec.snapshot(view.attributedString())
            let font = payload.runs.first!.attributes.font
            expect(font.size == 26 && font.name != fallback.fontName, "Formatting persists authored size and face instead of glyph fallback")
            expect(NSFontDescriptor.SymbolicTraits(rawValue: font.traits).contains(emphasis == .bold ? .bold : .italic), "Durable range carries the requested authored emphasis")
            view.undo(nil)
            expect(view.attributedString().isEqual(to: before), "Native undo restores the original attributed glyph and layout metadata")
            view.redo(nil)
            expect(view.hasEmphasis(emphasis), "Native redo restores the authored formatting")
            let authored = NSFontManager.shared.convert(original, toHaveTrait: emphasis == .bold ? .boldFontMask : .italicFontMask)
            load([.font: fallback, key: authored])
            expect(view.hasEmphasis(emphasis), "Checked state follows authored emphasis after native fallback")
            toggle(emphasis)
            expect(!view.hasEmphasis(emphasis), "Toggling a fallback run removes the authored trait")
        }
        let explicit = NSFont(name: "Times-Roman", size: 21)!
        load([.font: explicit], text: "Authored")
        toggle(.italic)
        let changed = try EaselRichTextCodec.snapshot(view.attributedString()).runs.first!.attributes.font
        expect(changed.size == 21 && changed.name.hasPrefix("Times"), "Explicit user family and size survive emphasis without fallback metadata")
        load([.font: fallback])
        let unsupportedFace = NSAttributedString(attributedString: view.attributedString())
        toggle(.italic)
        expect(failures == 1 && view.attributedString().isEqual(to: unsupportedFace), "An explicit unsupported font is refused, never silently replaced")
        load([.font: original, key: "invalid"])
        let malformed = NSAttributedString(attributedString: view.attributedString()), beforeRefusal = boundaries
        view.toggle(.bold)
        expect(failures == 2 && view.attributedString().isEqual(to: malformed) && boundaries == beforeRefusal, "Malformed original-font metadata is refused atomically")
        load([.font: fallback, key: original, NSAttributedString.Key("unsupported-local-attribute"): 1])
        let unsupported = NSAttributedString(attributedString: view.attributedString())
        view.toggle(.bold)
        expect(failures == 3 && view.attributedString().isEqual(to: unsupported) && boundaries == beforeRefusal, "Authored-font normalization does not weaken unsupported-attribute refusal")
        load([.font: fallback, key: original])
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.typingAttributes = [.font: fallback, key: original]
        toggle(.italic)
        expect(view.hasEmphasis(.italic) && view.typingAttributes[key] == nil, "Collapsed formatting normalizes only native original-font metadata")
        expect(view.string == "👋", "Collapsed formatting preserves existing text")
    }

    @MainActor static func externalClipboard(board: NSPasteboard) throws {
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Read café 👩🏽‍💻 now", style: .init(), color: "#194B93"))
        let label = (original.string as NSString).range(of: "café 👩🏽‍💻")
        original.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label)
        view.textStorage?.setAttributedString(original); view.setSelectedRange(label)
        board.clearContents(); board.setString("https://example.com/new?q=one%20two", forType: .URL)
        expect(view.readablePasteboardTypes.contains(.URL), "URL-only native paste is advertised")
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board), "URL-only clipboard links the original selected words"); view.localUndo.endUndoGrouping()
        let pasted = try EaselRichTextCodec.snapshot(view.attributedString())
        expect(view.string == original.string && pasted.runs.contains(where: { $0.attributes.link == "https://example.com/new?q=one%20two" && $0.length == label.length }), "Link paste keeps exact Unicode label and UTF-16 range")
        expect((view.attributedString().attribute(.underlineStyle, at: label.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue, "Existing label styling survives link paste")
        expect(view.typingAttributes[.link] == nil && view.selectedRange() == NSRange(location: NSMaxRange(label), length: 0), "New typing stays outside the pasted link")
        view.undo(nil)
        expect(view.attributedString().isEqual(to: original) && view.selectedRange() == label, "One native undo restores original text, attributes and selection")
        view.redo(nil); expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == pasted, "Redo restores exact pasted-link ranges")
        let selfURL = "https://example.com/old"
        view.textStorage?.setAttributedString(NSAttributedString(string: selfURL, attributes: [.font: NSFont.systemFont(ofSize: 15), .link: URL(string: selfURL)!]))
        view.setSelectedRange(NSRange(location: 0, length: selfURL.utf16.count))
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board), "An existing self-labelled link accepts replacement"); view.localUndo.endUndoGrouping()
        expect(view.string == "https://example.com/new?q=one%20two", "Self-labelled URL replacement changes both label and destination")
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        board.clearContents(); board.setString("https://example.org/", forType: .string)
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board), "Plain-string HTTP URL works at a caret"); view.localUndo.endUndoGrouping()
        expect(view.string.hasSuffix("https://example.org/"), "Caret URL paste inserts its own label")
        view.setSelectedRange(NSRange(location: 0, length: view.attributedString().length))
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board, plain: true), "Explicit plain paste bypasses selected-word linking"); view.localUndo.endUndoGrouping()
        expect(view.string == "https://example.org/" && view.attributedString().attribute(.link, at: 0, effectiveRange: nil) == nil, "Plain paste inserts URL words without an active link")
        let rich = EaselStyledText(text: "https://example.com/rich", style: .init(family: .mono, size: .h2), color: "#194B93")
        try rich.write(to: board)
        expect(try! EaselClipboardURL.read(from: board) == nil, "Private rich carrier stays authoritative over its URL-shaped plain fallback")
        for raw in ["javascript:alert(1)", "file:///tmp/private", "https://user:password@example.com/", "two https://example.com links"] {
            board.clearContents(); board.setString(raw, forType: .URL)
            expect(try! EaselClipboardURL.read(from: board) == nil, "Non-web, credential and multiword values are not actionable URL pastes")
            expect(try! EaselStyledText.plainText(from: board) == raw, "URL-only unsupported values remain available to explicit plain paste")
        }
        board.clearContents(); board.setString("https://example.com/", forType: .URL)
        view.localUndo.beginUndoGrouping()
        view.setMarkedText("composing", selectedRange: NSRange(location: 9, length: 0), replacementRange: NSRange(location: 0, length: view.attributedString().length))
        view.localUndo.endUndoGrouping()
        let composition = NSAttributedString(attributedString: view.attributedString())
        expect(!view.pasteContent(from: board) && view.hasMarkedText() && view.attributedString().isEqual(to: composition), "URL paste refuses native composition atomically")
        view.unmarkText()
        let wrapper = FileWrapper(regularFileWithContents: Data("non-image file bytes".utf8)); wrapper.preferredFilename = "attachment.txt"
        let file = NSTextAttachment(fileWrapper: wrapper)
        let mixed = NSMutableAttributedString(string: "before ")
        mixed.append(NSAttributedString(attachment: file)); mixed.append(NSAttributedString(string: " after"))
        let rtfd = try mixed.data(from: NSRange(location: 0, length: mixed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        board.clearContents(); board.setData(rtfd, forType: .rtfd)
        let before = NSAttributedString(attributedString: view.attributedString()), selection = view.selectedRange(), generation = board.changeCount
        var failure: Error?; view.onClipboardError = { failure = $0 }
        let result = view.pasteContent(from: board)
        expect(!result && failure is EaselTextClipboardError, "Non-image RTFD explicitly refuses instead of inventing file persistence")
        expect(view.attributedString().isEqual(to: before) && view.selectedRange() == selection && board.changeCount == generation, "Refused attachment preserves selection, text and source clipboard")
        expect(try! EaselStyledText.plainText(from: board) == "before  after", "Explicit plain fallback keeps surrounding words and omits the non-image attachment")
        let paragraphs = NSMutableAttributedString(string: "one\ntwo", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let first = NSMutableParagraphStyle(); first.alignment = .center
        let second = NSMutableParagraphStyle(); second.alignment = .right; second.headIndent = 20
        paragraphs.addAttribute(.paragraphStyle, value: first, range: NSRange(location: 0, length: 4))
        paragraphs.addAttribute(.paragraphStyle, value: second, range: NSRange(location: 4, length: 3))
        view.textStorage?.setAttributedString(paragraphs); view.setSelectedRange(NSRange(location: 2, length: 3))
        let beforeJoin = NSAttributedString(attributedString: view.attributedString())
        board.clearContents(); board.setString("X", forType: .string)
        view.localUndo.beginUndoGrouping(); let joined = view.pasteContent(from: board, plain: true); view.localUndo.endUndoGrouping()
        expect(joined && view.string == "onXwo", "Plain paste joining differently styled paragraphs reports native success")
        let joinedParagraph = view.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        expect(joinedParagraph == view.attributedString().attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle, "Native paragraph normalization gives the joined line one paragraph style")
        view.undo(nil)
        expect(view.attributedString().isEqual(to: beforeJoin) && view.selectedRange() == NSRange(location: 2, length: 3), "One undo restores both original paragraph styles and selection")
        board.clearContents(); board.setString(String(repeating: "x", count: 1_048_577), forType: .URL)
        rejects("URL payloads obey the text byte budget") { _ = try EaselClipboardURL.read(from: board) }
    }

    @MainActor static func inlineImages(board: NSPasteboard) throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        expect(source.data == png && source.fileType == "public.png", "Native inline image preserves actual original PNG bytes")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24)!
        bitmap.bitmapData!.initialize(repeating: 128, count: 12); bitmap.size = NSSize(width: 2, height: 2)
        for (format, type) in [(NSBitmapImageRep.FileType.jpeg, "public.jpeg"), (.tiff, "public.tiff")] {
            let original = bitmap.representation(using: format, properties: [:])!
            let imported = try EaselTextAttachments.image(data: original)
            expect(imported.data == original && imported.fileType == type, "Supported image import preserves the actual JPEG/TIFF bytes")
        }

        let text = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("before\n", style: .init(), color: "#252525"))
        text.append(EaselTextAttachments.character(source, attributes: [:]))
        text.append(EaselTextAppearance.attributed("\nafter", style: .init(), color: "#252525"))
        let payload = try EaselStyledText.capture(text, style: .init(), color: "#252525")
        expect(payload.richText?.runs.first(where: { $0.attributes.image != nil })?.location == 7, "Inline image stays in its original UTF-16 text range")
        try payload.write(to: board)
        expect(board.data(forType: .rtfd) != nil && board.data(forType: .rtf) == nil, "Copy advertises real attachment-preserving RTFD")
        expect(board.string(forType: .string) == "before\n\nafter", "Plain copy carries words without an orphan object-replacement character")
        expect(try! EaselStyledText.read(from: board) == payload, "Private range carrier preserves encoded image and styled text exactly")
        let rtfd = board.data(forType: .rtfd)!
        board.clearContents(); board.setData(rtfd, forType: .rtfd)
        let decoded = try EaselStyledText.read(from: board)!
        expect(decoded.text == payload.text && decoded.richText?.runs.contains(where: { $0.attributes.image != nil }) == true, "External native RTFD really imports its inline image")
        let encoded = decoded.richText!.runs.first(where: { $0.attributes.image != nil })!.attributes.image!
        expect(encoded.data == png, "RTFD retains the attachment's actual original encoded PNG")
        expect(try! EaselStyledText.plainText(from: board) == "before\n\nafter", "Explicit plain paste extracts words from RTFD without importing pixels")
        let cell = EaselImageAttachment(source: .init(data: png, fileType: "public.png", width: 400, height: 200)).attachmentCell as! EaselImageAttachmentCell
        let container = NSTextContainer(containerSize: NSSize(width: 260, height: 1000))
        cell.textContainer = container
        expect(cell.cellSize() == NSSize(width: 260, height: 160), "Original attachment cell fits both dimensions into width minus 60 and reserves full line width")
        container.size.width = 160
        expect(cell.cellSize() == NSSize(width: 160, height: 110), "Text-container resizing recomputes from original image size")
        expect(source.data == png, "Layout-only NSImage size changes leave encoded bytes untouched")
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); expect(try! view.insertImage(png), "Native image authoring accepts original selected range"); view.localUndo.endUndoGrouping()
        expect(view.string == "one \n\u{FFFC}\n" && view.selectedRange() == NSRange(location: 7, length: 0), "Image replaces selected text and adds original paragraph boundaries")
        expect(view.typingAttributes[.attachment] == nil, "Following typing cannot accidentally duplicate the image")
        let inserted = try EaselRichTextCodec.snapshot(view.attributedString())
        view.undo(nil); expect(view.attributedString().isEqual(to: original) && view.selectedRange() == NSRange(location: 4, length: 3), "One native undo restores original text and selection")
        view.redo(nil); expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == inserted, "Redo restores exact image bytes and paragraph structure")
        view.setSelectedRange(NSRange(location: 5, length: 1))
        let selected = try view.selectedPayload()!
        expect(selected.text == "\u{FFFC}" && selected.richText?.runs.first?.attributes.image?.data == png, "Selected image copy rebases its real attachment range")
        view.localUndo.beginUndoGrouping(); view.deleteBackward(nil); view.localUndo.endUndoGrouping()
        expect(!EaselTextAttachments.hasImages(view.attributedString()), "Native Delete removes just the selected attachment character")
        view.undo(nil); expect(EaselTextAttachments.hasImages(view.attributedString()), "Native Delete undo restores the original attachment")
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping(); view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composition = view.attributedString()
        expect(try! !view.insertImage(png) && view.hasMarkedText() && view.attributedString().isEqual(to: composition), "Inline image admission cannot replace an active native composition")
        view.finishComposition(); view.localUndo.endUndoGrouping()
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let untouched = view.attributedString()
        rejects("Corrupt image cannot mutate original selection") { _ = try view.insertImage(Data("bad".utf8)) }
        expect(view.attributedString().isEqual(to: untouched), "Rejected image leaves editor and existing attachments intact")
        let unsafe = NSTextAttachment(fileWrapper: FileWrapper(directoryWithFileWrappers: [:]))
        rejects("Directory attachment is not followed as an external file") { _ = try EaselTextAttachments.source(unsafe) }
        board.clearContents(); board.setData(png, forType: .png)
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board), "Ordinary native PNG paste reaches actual inline image authoring"); view.localUndo.endUndoGrouping()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("original.png"); try png.write(to: file)
        board.clearContents(); board.setString(file.absoluteString, forType: .fileURL)
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board), "A real local image file pastes into the original native text range"); view.localUndo.endUndoGrouping()
        try FileManager.default.removeItem(at: file)
        expect(try! EaselRichTextCodec.snapshot(view.attributedString()).runs.contains(where: { $0.attributes.image?.data == png }), "Inline file import retains bytes after source file deletion")
        board.clearContents(); board.setString(directory.absoluteString, forType: .fileURL)
        let beforeDirectory = view.attributedString()
        expect(!view.pasteContent(from: board) && view.attributedString().isEqual(to: beforeDirectory), "Directory paste is refused without mutating rich text")
        view.setSelectedRange(NSRange(location: 0, length: view.attributedString().length))
        expect(view.writablePasteboardTypes.contains(.rtfd) && !view.writablePasteboardTypes.contains(.rtf), "Native selected-text export advertises the lossless attachment format")
        board.clearContents(); board.declareTypes([.rtfd], owner: nil)
        expect(view.writeSelection(to: board, type: .rtfd), "Native Services/drag writer serializes the actual selected range as RTFD")
        expect(try! EaselStyledText.read(from: board)?.richText?.runs.contains(where: { $0.attributes.image?.data == png }) == true, "Native selected-range RTFD export retains original image bytes")
        let old = EaselStyledText(version: 2, text: "Prior", style: .init(), color: "#252525")
        board.clearContents(); board.setData(try JSONEncoder().encode(old), forType: EaselStyledText.previousPasteboardType)
        expect(try! EaselStyledText.read(from: board)?.text == "Prior", "Version-2 text clipboard remains readable")
        view.localUndo.beginUndoGrouping(); view.resetEditingHistory(); view.localUndo.endUndoGrouping()
        let beforeNewEdit = view.string
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping(); view.insertText("Retained", replacementRange: view.selectedRange()); view.localUndo.endUndoGrouping()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(view.localUndo.canUndo, "Deferred rollback cleanup cannot erase a later native edit")
        view.undo(nil); expect(view.string == beforeNewEdit, "Later edit still has its own original undo after stale cleanup retires")
        view.retire()
    }
    @MainActor static func nativeEditing(board: NSPasteboard) throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.underline); view.localUndo.endUndoGrouping()
        expect(view.hasEmphasis(.underline), "Selection receives real underline attributes")
        expect(view.attributedString().attribute(.underlineStyle, at: 4, effectiveRange: nil) == nil, "Formatting does not leak into other ranges")
        view.undo(nil)
        expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == EaselRichTextCodec.snapshot(original), "Native local undo restores range attributes")
        view.redo(nil)
        expect(view.hasEmphasis(.underline), "Native local redo restores range attributes")
        let selected = try view.selectedPayload()!
        expect(selected.text == "One" && selected.richText?.runs.first?.location == 0, "Selected copy rebases ranges to its substring")
        try selected.write(to: board)
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping(); expect(view.pasteContent(from: board), "Native rich paste succeeds"); view.localUndo.endUndoGrouping()
        expect(view.string == original.string + "One", "Native rich paste inserts at the original caret")
        expect((view.attributedString().attribute(.underlineStyle, at: view.attributedString().length - 1, effectiveRange: nil) as? NSNumber)?.intValue == 1, "Pasted selection retains attributes")
        let before = view.attributedString()
        board.clearContents(); board.setData(Data("bad".utf8), forType: EaselStyledText.pasteboardType)
        expect(!view.pasteContent(from: board) && view.attributedString().isEqual(to: before), "Rejected paste preserves existing editor content")
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.toggle(.italic)
        expect((view.typingAttributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true, "Collapsed formatting changes future typing attributes")
        expect(view.attributedString().isEqual(to: before), "Collapsed formatting leaves existing content untouched")
        let emoji = NSMutableAttributedString(attributedString: original)
        emoji.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: (original.string as NSString).range(of: "👩🏽‍💻"))
        let payload = try EaselStyledText.capture(emoji, style: .init(), color: "#252525")
        try payload.write(to: board)
        expect(try! EaselStyledText.read(from: board) == payload, "Unicode-rich selected ranges round trip in private carrier")
        view.textStorage!.setAttributedString(original); view.localUndo.removeAllActions()
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.bold); view.toggle(.italic); view.localUndo.endUndoGrouping()
        let emphasized = try EaselRichTextCodec.snapshot(view.attributedString())
        view.localUndo.beginUndoGrouping(); view.changeStyle { $0.size = .h1 }; view.localUndo.endUndoGrouping()
        expect(view.hasEmphasis(.bold) && view.hasEmphasis(.italic), "Bold and italic survive palette size change")
        expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 44, "Palette change really applies the new font size")
        let palette = EaselTextAppearance.paletteStyle(view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as! NSFont)
        expect(palette == EaselTextStyle(family: .clean, size: .h1), "Palette recognizes emphasized range without losing its actual size")
        view.undo(nil)
        expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == emphasized, "Undo restores emphasized range before palette change")
        let old = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: [.boldFontMask, .italicFontMask])
        let result = try EaselTextAppearance.font(.init(family: .clean, size: .h2), preservingEmphasisFrom: old)
        expect(result.fontDescriptor.symbolicTraits.contains([.bold, .italic]), "Shared object/range palette helper preserves both traits")
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping()
        view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(view.hasMarkedText(), "Native input method owns marked text")
        let composition = view.attributedString()
        view.toggle(.underline)
        expect(view.attributedString().isEqual(to: composition), "Formatting does not mutate an active composition")
        view.finishComposition(); view.localUndo.endUndoGrouping()
        expect(!view.hasMarkedText() && view.string.hasSuffix("かな"), "Finishing editor commits the actual native composition without dropping words")
        view.retire()
    }
    @MainActor static func paragraphEditing(board: NSPasteboard) throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        func grouped(_ action: () -> Void) { view.localUndo.beginUndoGrouping(); action(); view.localUndo.endUndoGrouping() }
        func load(_ string: String) {
            view.textStorage!.setAttributedString(EaselTextAppearance.attributed(string, style: .init(), color: "#252525"))
            view.localUndo.removeAllActions(); view.setSelectedRange(NSRange(location: 0, length: (string as NSString).length))
        }
        for format in [NSTextList.MarkerFormat.disc, NSTextList.MarkerFormat(rawValue: "{decimal}.")] {
            load("\tImportant\tKeep this text")
            let imported = NSMutableParagraphStyle()
            imported.textLists = [NSTextList(markerFormat: format, options: 0)]
            view.textStorage!.addAttribute(.paragraphStyle, value: imported, range: view.selectedRange())
            let original = view.attributedString()
            grouped { view.changeParagraph(.text) }
            expect(view.string == original.string, "Removing imported list metadata preserves ordinary tab-delimited words")
            view.undo(nil)
            expect(view.attributedString().isEqual(to: original), "Imported content and metadata restore together on undo")
            view.setSelectedRange(NSRange(location: 1, length: 0))
            grouped { view.insertBacktab(nil) }
            expect(view.string == original.string, "Outdenting imported list metadata preserves a non-marker prefix")
        }
        load("One 👩🏽‍💻\nTwo\nThree")
        let source = view.attributedString()
        grouped { view.changeParagraph(.numbers) }
        expect(view.string == "\t1.\tOne 👩🏽‍💻\n\t2.\tTwo\n\t3.\tThree", "Numbered paragraphs have actual ordered markers: \(view.string.debugDescription)")
        expect(view.paragraphKind() == .numbers, "Selected numbered paragraphs report actual state")
        let saved = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        try saved.write(to: board)
        expect(try! EaselStyledText.read(from: board) == saved, "Authored lists preserve marker text and native metadata in private copy")
        view.undo(nil)
        expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == EaselRichTextCodec.snapshot(source), "List command undo restores original words and attributes")
        view.redo(nil)
        let endFirst = (view.string as NSString).range(of: "\n").location
        view.setSelectedRange(NSRange(location: endFirst, length: 0))
        grouped { view.insertNewline(nil) }
        expect(view.string.contains("\t2.\t\n\t3.\tTwo\n\t4.\tThree"), "Return inserts and renumbers the actual next item")
        let continued = view.attributedString(), caret = view.selectedRange()
        grouped { view.insertNewline(nil) }
        expect(!view.string.contains("\t2.\t\n"), "Return on an empty item exits the list")
        expect(view.paragraphKind() == .text, "Exited empty item is a body paragraph")
        view.undo(nil)
        expect(view.attributedString().isEqual(to: continued) && view.selectedRange() == caret, "Undo restores list prefix and original caret")
        grouped { view.deleteBackward(nil) }
        expect(view.paragraphKind() == .text, "Backspace at item content start removes list formatting without deleting words")
        load("A\nB\nC"); grouped { view.changeParagraph(.numbers) }
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "B").location, length: 0))
        grouped { view.insertTab(nil) }
        expect((view.attributedString().attribute(.paragraphStyle, at: view.selectedRange().location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.count == 2, "Tab changes real list nesting")
        expect(view.string == "\t1.\tA\n\t1.\tB\n\t2.\tC", "Nested numbering preserves parent sequence")
        grouped { view.insertBacktab(nil) }
        expect(view.string == "\t1.\tA\n\t2.\tB\n\t3.\tC", "Shift-Tab restores parent list and numbering")
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "\n").location, length: 0))
        grouped { view.deleteForward(nil) }
        expect(view.string == "\t1.\tAB\n\t2.\tC", "Forward delete joins list content and renumbers without a stray marker")
        view.undo(nil)
        expect(view.string == "\t1.\tA\n\t2.\tB\n\t3.\tC", "Join undo restores exact list text")
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "B").location + 1, length: 0))
        grouped { view.insertText("\nPasted\nMore", replacementRange: view.selectedRange()) }
        expect(view.string.contains("\t3.\tPasted\n\t4.\tMore\n\t5.\tC"), "Multiline native insertion keeps list structure and subsequent numbering")
        view.undo(nil)
        expect(view.string == "\t1.\tA\n\t2.\tB\n\t3.\tC", "Multiline list insertion is one undo transaction")
        load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        grouped { view.changeParagraph(.heading2) }
        expect((view.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "Caret/range heading command formats full original paragraph")
        expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 26, "Heading 2 uses recovered 26-point constant")
        expect((view.attributedString().attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0 == 0, "Heading stops before next paragraph")
        let rich = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        try rich.write(to: board)
        expect(try! EaselStyledText.read(from: board) == rich, "Heading semantics persist in the shared carrier")
        let decoded = try JSONDecoder().decode(EaselStyledText.self, from: JSONEncoder().encode(rich))
        expect((decoded.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "Persisted heading restores native paragraph metadata")
        expect((decoded.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == (view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName, "Heading's non-palette size restores actual system family without a named-font substitution")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Paragraph component")
        try session.perform("Add heading") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 200, height: 100), text: rich.text, richText: rich.richText)] }
        expect(try! EaselStore(directory: directory).load(session.document.id).document.items[0].richText == rich.richText, "Actual file-backed session preserves authored heading metadata")
        try session.perform("Replace with list") { $0.items[0].text = saved.text; $0.items[0].richText = saved.richText }
        try session.undo()
        expect(session.document.items[0].richText == rich.richText, "Document undo restores heading after list replacement")
        try session.redo()
        expect(session.document.items[0].richText == saved.richText, "Document redo restores authored list metadata")
        view.setSelectedRange(NSRange(location: 0, length: 3))
        grouped { view.changeStyle(preservingSize: true) { $0.family = .mono } }
        expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 26, "Family change preserves actual paragraph heading size")
        expect(EaselTextAppearance.paletteFamily(view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as! NSFont) == .mono, "Family control actually changes a heading font")
        view.undo(nil)
        view.setSelectedRange(NSRange(location: 3, length: 0))
        grouped { view.insertNewline(nil) }
        expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headerLevel == 0, "Return after heading prepares body typing")
        expect(view.string == "One\n\nTwo", "Heading Return keeps original content")
        load(""); grouped { view.changeParagraph(.bullets) }
        expect(view.string == "\t•\t" && view.selectedRange().location == 3, "Empty object list starts with a real marker and caret after it")
        grouped { view.insertText("Hello", replacementRange: view.selectedRange()) }
        expect(view.string == "\t•\tHello", "Native typing retains authored list")
        grouped { view.insertNewline(nil) }
        expect(view.string == "\t•\tHello\n\t•\t", "Bullets continue after typed text")
        view.undo(nil)
        expect(view.string == "\t•\tHello", "Return is one native undo transaction")
        load("First\nSecond")
        view.setSelectedRange(NSRange(location: 0, length: 6))
        grouped { view.changeParagraph(.bullets) }
        expect(view.string == "\t•\tFirst\nSecond", "Selection ending at next paragraph start excludes that paragraph")
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        grouped { view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        let marked = view.attributedString()
        grouped { view.changeParagraph(.heading1) }
        expect(view.attributedString().isEqual(to: marked), "Paragraph format preserves an active native composition")
        grouped { view.finishComposition() }
        var invalid = rich.richText!; invalid.runs[0].attributes.paragraph!.heading = 7
        rejects("unsupported heading level") { try invalid.validate(text: rich.text) }
    }

    @MainActor static func markdownEditing(board: NSPasteboard) throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        func grouped(_ action: () -> Void) { view.localUndo.beginUndoGrouping(); action(); view.localUndo.endUndoGrouping() }
        func load(_ string: String) {
            view.textStorage!.setAttributedString(EaselTextAppearance.attributed(string, style: .init(), color: "#252525"))
            view.typingAttributes = EaselTextAppearance.attributed("a", style: .init(), color: "#252525").attributes(at: 0, effectiveRange: nil)
            view.localUndo.removeAllActions(); view.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
        func type(_ string: String) {
            for character in string { grouped { view.insertText(String(character), replacementRange: view.selectedRange()) } }
        }
        for (source, emphasis) in [("*One café*", EaselStyledTextView.Emphasis.bold), ("_One café_", .italic), ("-One café-", .strikethrough)] {
            load(""); type(source)
            expect(view.string == "One café", "Typed original delimiter syntax consumes only its delimiters: \(source)")
            expect(view.selectedRange() == NSRange(location: 8, length: 0), "Inline conversion preserves the original UTF-16 caret")
            let finished = view.attributedString()
            let attrs = finished.attributes(at: 0, effectiveRange: nil)
            let styled = emphasis == .strikethrough ? (attrs[.strikethroughStyle] as? NSNumber)?.intValue == 1
                : (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(emphasis == .bold ? .bold : .italic) == true
            expect(styled, "Typed token creates the real native range attribute")
            expect(!view.hasEmphasis(emphasis), "Conversion immediately restores the original unstyled typing attributes")
            view.undo(nil)
            expect(view.string == String(source.dropLast()), "One input transaction undoes the closing character and its conversion")
            view.redo(nil)
            expect(view.attributedString().isEqual(to: finished), "Native redo restores converted text and attributes without a second transform")
            type(" after")
            view.setSelectedRange(NSRange(location: finished.length + 1, length: 5))
            expect(!view.hasEmphasis(emphasis), "Conversion restores original typing attributes for following text")
        }
        for literal in ["**bold**", "~~strike~~", "`code`", "[label](https://example.com)", "*incomplete", "*punctuation!*", "word*bold*", #"\*escaped*"#, "+ list", "2. list", "#### heading"] {
            load(""); type(literal)
            expect(view.string == literal, "Unsupported or incomplete syntax remains literal: \(literal)")
        }
        load("before *one"); type("*")
        expect(view.string == "before one", "A typed closer may complete an existing original range at a word boundary")
        load("*word* other"); type(" ")
        expect(view.string == "*word* other ", "An unrelated later edit never retrospectively interprets imported tokens")
        load("*word*"); view.setSelectedRange(NSRange(location: 0, length: 1)); type("*")
        expect(view.string == "*word*", "Replacing a selection does not reinterpret its surrounding literal text")
        load("*word")
        board.clearContents(); board.setString("*", forType: .string)
        grouped { expect(view.pasteContent(from: board), "Native plain paste succeeds") }
        expect(view.string == "*word*", "Even a one-character pasted closer remains literal")
        load("")
        try EaselStyledText(text: "# Heading\n*word*", style: .init(), color: "#252525").write(to: board)
        grouped { expect(view.pasteContent(from: board), "Native private rich paste succeeds") }
        expect(view.string == "# Heading\n*word*", "Private rich paste preserves literal syntax")
        let rtf = board.data(forType: .rtf)!
        board.clearContents(); board.setData(rtf, forType: .rtf); load("")
        grouped { expect(view.pasteContent(from: board), "Native RTF paste succeeds") }
        expect(view.string == "# Heading\n*word*", "Imported RTF text is not parsed as markdown")
        for (prefix, level, size) in [("# ", 1, 32.0), ("## ", 2, 26.0), ("### ", 3, 22.0)] {
            load(""); type(prefix)
            expect(view.string.isEmpty && view.selectedRange().location == 0, "Heading prefix transforms at the typed space")
            expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headerLevel == level, "Empty heading retains semantic typing state")
            type("Heading")
            expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == CGFloat(size), "Typed heading uses recovered paragraph size")
            grouped { view.insertNewline(nil) }; type("body")
            expect((view.attributedString().attribute(.paragraphStyle, at: view.attributedString().length - 1, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 0, "Heading Return retains existing body continuation")
        }
        for prefix in ["- ", "* ", "1. ", "1.\t", "1.\n"] {
            load(""); type(String(prefix.dropLast()))
            grouped {
                if prefix.last == "\t" { view.insertTab(nil) }
                else if prefix.last == "\n" { view.insertNewline(nil) }
                else { view.insertText(" ", replacementRange: view.selectedRange()) }
            }
            let numbered = prefix.hasPrefix("1.")
            expect(view.string == (numbered ? "\t1.\t" : "\t•\t"), "List prefix becomes an actual native marker: \(prefix.debugDescription)")
            type("Item"); grouped { view.insertNewline(nil) }
            expect(view.string.hasSuffix(numbered ? "\n\t2.\t" : "\n\t•\t"), "Typed list continues through existing paragraph authoring")
            grouped { view.insertNewline(nil) }
            expect(view.paragraphKind() == .text, "Empty item exits the typed list using the existing native command")
        }
        for depth in [1, 6] {
            load(String(repeating: "\t", count: depth)); type("- ")
            expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.count == depth + 1, "Recovered tab prefix maps to actual nested list depth")
        }
        load(String(repeating: "\t", count: 7)); type("- ")
        expect(view.string == String(repeating: "\t", count: 7) + "- ", "Unsupported eighth list depth remains literal")
        load("# "); grouped { view.changeParagraph(.heading1) }; type("- ")
        expect(view.string == "# - ", "Existing heading metadata guards list conversion")
        load("before\n*word\nafter")
        let link = URL(string: "https://example.com")!
        let linkedRange = (view.string as NSString).range(of: "word")
        view.textStorage!.addAttributes([.link: link, .foregroundColor: NSColor.systemBlue], range: linkedRange)
        let before = view.attributedString().attributedSubstring(from: NSRange(location: 0, length: 7))
        view.setSelectedRange(NSRange(location: NSMaxRange(linkedRange), length: 0)); type("*")
        expect(view.string == "before\nword\nafter", "Range conversion preserves unrelated paragraphs")
        expect(view.attributedString().attributedSubstring(from: NSRange(location: 0, length: 7)).isEqual(to: before), "Unrelated attributed content stays exact")
        expect(view.attributedString().attribute(.link, at: 7, effectiveRange: nil) as? URL == link, "Existing inline link survives automatic emphasis")
        expect(view.attributedString().attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor == NSColor.systemBlue, "Existing inline color survives automatic emphasis")
        let payload = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        try payload.write(to: board)
        expect(try! EaselStyledText.read(from: board) == payload, "Converted range attributes survive actual native copy and paste carrier")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Markdown component")
        try session.perform("Type markdown") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 200, height: 100), text: payload.text, richText: payload.richText)] }
        expect(try! EaselStore(directory: directory).load(session.document.id).document.items.first?.richText == payload.richText, "Actual file-backed document preserves typed markdown attributes")
        try session.undo(); expect(session.document.items.isEmpty, "Document undo owns the durable typed-text transaction")
        try session.redo(); expect(session.document.items.first?.richText == payload.richText, "Document redo restores original range formatting")
        load("*word")
        let refusingDelegate = MarkdownConversionRefusal()
        view.delegate = refusingDelegate
        type("*")
        expect(view.string == "*word*" && view.selectedRange().location == 6, "Delegate-refused conversion preserves the accepted literal input and caret")
        expect(refusingDelegate.refusals == 1, "The actual native delegate receives conversion admission")
        view.delegate = nil
        load("*word")
        grouped { view.setMarkedText("*", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        expect(view.hasMarkedText() && view.string == "*word*", "Input method retains literal marked text")
        grouped { view.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        expect(!view.hasMarkedText() && view.string == "*word*", "Composition commit is not intercepted as a markdown trigger")
        view.retire()
    }

}

@MainActor
private final class MarkdownConversionRefusal: NSObject, NSTextViewDelegate {
    var refusals = 0
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if affectedCharRange.length > 0, (replacementString?.count ?? 0) > 1 { refusals += 1; return false }
        return true
    }
}
