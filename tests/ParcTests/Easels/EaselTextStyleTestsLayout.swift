import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselTextStyleTestsLayout {
    private typealias Editor = EaselTextStyleTestsSupport.Editor

    @Test
    func legacyTextStylesKeepFillOff() throws {
        let legacy = try JSONDecoder().decode(EaselTextStyle.self, from: Data(#"{"family":"clean","size":"body"}"#.utf8))
        #expect(legacy.resolvedFill == .none && legacy.fill == nil, "Existing style JSON keeps fill off without migration")
    }

    @Test
    func anUnknownFillIsRefused() {
        #expect(throws: (any Error).self, "Unknown fill refuses rather than silently dropping styling") {
            _ = try JSONDecoder().decode(EaselTextStyle.self, from: Data(#"{"family":"clean","size":"body","fill":"unrecognized"}"#.utf8))
        }
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func fillHugsEachVisibleLine(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let style = EaselTextStyle(fill: .contentHugging, family: family, size: size)
        let value = EaselTextAppearance.attributed("Metrics gj\nShort", style: style, color: "#194B93")
        let layout = EaselTextLayout.Layout(value, width: 1000)
        let rects = EaselTextLayout.lineRects(manager: layout.manager, container: layout.container)
        #expect(rects.count == 2 && rects.allSatisfy { $0.width > 0 && $0.height > 0 }, "Every actual bundled style produces visible glyph geometry")
        #expect(rects[0].width > rects[1].width, "Fill hugs unequal lines instead of the object frame")
        let path = EaselTextLayout.fillPath(rects: rects, radius: EaselTextLayout.radius(style))
        #expect(rects.allSatisfy { path.contains(NSPoint(x: $0.midX, y: $0.midY)) }, "Native rounded union contains each text line")
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func thePrivateCarrierKeepsTheFill(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let style = EaselTextStyle(fill: .contentHugging, family: family, size: size)
        let value = EaselTextAppearance.attributed("Metrics gj\nShort", style: style, color: "#194B93")
        let payload = try EaselStyledText.capture(value, style: style, color: "#194B93")
        try payload.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == payload, "Private clipboard preserves whole-object fill with original rich content")
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func editorAndCanvasShareFillGeometry(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let style = EaselTextStyle(fill: .contentHugging, family: family, size: size)
        let value = EaselTextAppearance.attributed("Metrics gj\nShort", style: style, color: "#194B93")
        let layout = EaselTextLayout.Layout(value, width: 1000)
        let rects = EaselTextLayout.lineRects(manager: layout.manager, container: layout.container)
        let editor = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        editor.usesEaselObjectLayout = true; editor.isRichText = true; editor.drawsBackground = false
        editor.textContainerInset = EaselTextLayout.inset
        editor.textContainer?.lineFragmentPadding = EaselTextLayout.fragmentPadding
        editor.textContainer?.widthTracksTextView = true
        editor.textStorage?.setAttributedString(value); editor.objectStyle = style
        let editorRects = EaselTextLayout.lineRects(manager: editor.layoutManager!, container: editor.textContainer!)
        #expect(editorRects == rects, "Editor and canvas share exact native line geometry for every family and size")
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func fillChangesOnlyPresentationInk(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let style = EaselTextStyle(fill: .contentHugging, family: family, size: size)
        let value = EaselTextAppearance.attributed("Metrics gj\nShort", style: style, color: "#194B93")
        let editor = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        editor.usesEaselObjectLayout = true; editor.isRichText = true; editor.drawsBackground = false
        editor.textContainerInset = EaselTextLayout.inset
        editor.textContainer?.lineFragmentPadding = EaselTextLayout.fragmentPadding
        editor.textContainer?.widthTracksTextView = true
        editor.textStorage?.setAttributedString(value); editor.objectStyle = style
        let before = try EaselRichTextCodec.snapshot(editor.attributedString())
        #expect(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor == .white,
               "Filled editor uses temporary white presentation ink")
        editor.objectStyle.fill = nil
        #expect(try! EaselRichTextCodec.snapshot(editor.attributedString()) == before,
               "Toggling fill never rewrites authored range colors or fonts")
        #expect(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil,
               "Turning fill off restores authored ink")
    }

    @MainActor @Test
    func whitespaceOnlyHasNoFill() {
        let blank = EaselTextLayout.Layout(EaselTextAppearance.attributed("  \n\t\n", style: .init(), color: "#252525"), width: 200)
        #expect(EaselTextLayout.lineRects(manager: blank.manager, container: blank.container).isEmpty, "Whitespace-only lines receive no fill")
    }

    @MainActor @Test
    func fillDoesNotBridgeEmptyParagraphs() {
        let value = EaselTextAppearance.attributed("First\n\nThird 👩🏽‍💻 שלום", style: .init(), color: "#252525")
        let native = EaselTextLayout.Layout(value, width: 250)
        let lines = EaselTextLayout.lineRects(manager: native.manager, container: native.container)
        #expect(lines.count == 2 && lines[1].minY > lines[0].maxY, "Empty line stays a real gap; Unicode and RTL use native glyph ranges")
        let gapPath = EaselTextLayout.fillPath(rects: lines, radius: 6)
        #expect(!gapPath.contains(NSPoint(x: lines[0].midX, y: (lines[0].maxY + lines[1].minY) / 2)), "Fill does not bridge empty paragraph gaps")
    }

    @MainActor @Test
    func fillUnionsOverlappingLinesAndRoundsItsOutside() {
        let stairs = [NSRect(x: 10, y: 10, width: 120, height: 30), NSRect(x: 10, y: 35, width: 60, height: 30)]
        let outline = EaselTextLayout.fillPath(rects: stairs, radius: 6)
        #expect(outline.contains(NSPoint(x: 30, y: 38)) && !outline.contains(NSPoint(x: 110, y: 55)), "Union removes internal edges while retaining the shorter-line contour")
        #expect(!outline.contains(NSPoint(x: 10.1, y: 10.1)), "Exterior corner is actually rounded")
    }

    @MainActor @Test
    func fillSmoothingExpandsNearNeighborEdges() {
        let smoothed = EaselTextLayout.smoothed([NSRect(x: 10, y: 0, width: 100, height: 25), NSRect(x: 12, y: 20, width: 100, height: 25)], radius: 6)
        #expect(smoothed.allSatisfy { $0.minX == 10 && $0.maxX == 112 }, "Near neighboring edges expand to their common extrema")
    }

    @MainActor @Test
    func fillSmoothingLeavesEdgesExactlyOneRadiusApart() {
        let strict = EaselTextLayout.smoothed([NSRect(x: 0, y: 0, width: 100, height: 25), NSRect(x: 6, y: 20, width: 100, height: 25)], radius: 6)
        #expect(strict[0].minX == 0 && strict[1].minX == 6, "Exact-radius difference does not smooth")
    }

    @MainActor @Test
    func fillSmoothingUsesOnlyOriginalNeighborEdges() {
        let cascade = EaselTextLayout.smoothed([20, 15, 10, 5, 10, 0].enumerated().map {
            NSRect(x: $0.element, y: $0.offset * 20, width: 100 - $0.element, height: 25)
        }, radius: 6)
        #expect(cascade.map(\.minX) == [5, 5, 5, 0, 0, 0], "Each smoothing pass compares original adjacent edges before accumulating extrema")
    }

    struct FillSelection: CustomTestStringConvertible {
        let testDescription: String
        let styles: [EaselTextStyle]
        let before: NSControl.StateValue
        let after: EaselTextStyle.Fill

        static let cases = [
            Self(testDescription: "Filled selection", styles: [.init(fill: .contentHugging)], before: .on, after: .none),
            Self(testDescription: "Unfilled selection", styles: [.init()], before: .off, after: .contentHugging),
            Self(testDescription: "Mixed selection", styles: [.init(), .init(fill: .contentHugging)], before: .mixed, after: .contentHugging),
        ]
    }

    @MainActor @Test(arguments: FillSelection.cases)
    func togglingFillAppliesToTheWholeSelection(_ selection: FillSelection) {
        #expect(EaselTextStyleState.fill(of: selection.styles) == selection.before)
        #expect(EaselTextStyleState.toggledFill(selection.styles) == selection.after)
    }

    @MainActor @Test(arguments: ["👩🏽‍💻", "漢字", "مرحبا"])
    func fallbackGlyphsKeepVisibleGeometry(_ string: String) {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let fallback = EaselTextLayout.Layout(EaselTextAppearance.attributed(string, style: .init(family: .mono), color: "#252525"), width: 500)
        let fallbackRects = EaselTextLayout.lineRects(manager: fallback.manager, container: fallback.container)
        #expect(fallbackRects.count == 1 && fallbackRects[0].width > 12, "Fallback glyphs retain real visible native geometry")
        var foundFallback = false
        for index in 0..<fallback.manager.numberOfGlyphs {
            let character = fallback.manager.characterIndexForGlyph(at: index)
            guard let font = fallback.storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont else { continue }
            var glyph = fallback.manager.cgGlyph(at: index)
            if glyph == 0xffff || fallback.manager.propertyForGlyph(at: index).contains(.null) { continue }
            let advance = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
            #expect(advance.isFinite && advance > 0, "The laid-out native font owns each fallback CGGlyph advance")
            foundFallback = foundFallback || font.fontName != EaselTextAppearance.font(.init(family: .mono)).fontName
        }
        #expect(foundFallback, "Native layout resolves the rendered fallback face before metrics are read")
    }

    @MainActor @Test
    func textLayoutClipsAtTheContainerHeight() {
        let value = EaselTextAppearance.attributed("First\n\nThird 👩🏽‍💻 שלום", style: .init(), color: "#252525")
        let clipped = EaselTextLayout.Layout(value, width: 250, height: 30)
        #expect(EaselTextLayout.lineRects(manager: clipped.manager, container: clipped.container).count == 1,
               "A resized short object renders only its actual text container's visible lines")
    }

    @MainActor @Test
    func textLayoutRewrapsAtTheContainerWidth() {
        let value = EaselTextAppearance.attributed("First\n\nThird 👩🏽‍💻 שלום", style: .init(), color: "#252525")
        let native = EaselTextLayout.Layout(value, width: 250)
        let narrow = EaselTextLayout.Layout(value, width: 65)
        #expect(narrow.height > native.height, "Measurement follows actual rewrapped native lines")
    }

    @MainActor @Test
    func inlineImageMetricsFollowTheCellBounds() throws {
        let source = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let bytes = source.representation(using: .png, properties: [:])!
        let image = try EaselTextAttachments.image(data: bytes)
        let attachment = EaselTextAttachments.character(image, attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let imageLayout = EaselTextLayout.Layout(attachment, width: 240)
        let imageRects = EaselTextLayout.lineRects(manager: imageLayout.manager, container: imageLayout.container)
        #expect(imageRects.count == 1 && imageRects[0].height >= 20, "Inline attachment uses its actual cell bounds without font-derived shrinking")
        #expect(try! EaselRichTextCodec.snapshot(imageLayout.storage).runs[0].attributes.image?.data == bytes, "Layout preserves original attachment bytes")
    }
}
