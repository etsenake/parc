import AppKit
import CoreText

/// The original object-wide font palette remains the base style for new text.
/// Range attributes are carried separately and are never flattened into it.
enum EaselTextAppearance {
    private static let registerFonts: Void = {
        let names = ["SpaceMono-Regular", "SpaceMono-Bold", "EBGaramond-VariableFont_wght",
                     "SohneBreit-Buch", "SohneBreit-Dreiviertelfett", "SohneBreit-Extrafett"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "EaselFonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func font(_ style: EaselTextStyle) -> NSFont {
        _ = registerFonts
        let size = style.pointSize
        switch style.family {
        case .clean:
            return .systemFont(ofSize: size, weight: style.size == .body ? .regular : style.size == .h2 ? .bold : .heavy)
        case .mono:
            return NSFont(name: style.size == .body ? "SpaceMono-Regular" : "SpaceMono-Bold", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: style.size == .body ? .regular : .bold)
        case .fancy:
            return NSFont(name: "EBGaramond-Regular", size: size) ?? .systemFont(ofSize: size)
        case .hip:
            let name = style.size == .body ? "SohneBreit-Buch" : style.size == .h2 ? "SohneBreit-Dreiviertelfett" : "SohneBreit-Extrafett"
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
        }
    }

    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x252525
        return NSColor(srgbRed: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }
    static func attributed(_ text: String, style: EaselTextStyle, color: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font(style), .foregroundColor: self.color(color)])
    }
    static func font(_ style: EaselTextStyle, preservingEmphasisFrom original: NSFont) throws -> NSFont {
        var traits: NSFontTraitMask = []
        if original.fontDescriptor.symbolicTraits.contains(.bold) { traits.insert(.boldFontMask) }
        if original.fontDescriptor.symbolicTraits.contains(.italic) { traits.insert(.italicFontMask) }
        let base = font(style), result = NSFontManager.shared.convert(base, toHaveTrait: traits)
        guard (!traits.contains(.boldFontMask) || result.fontDescriptor.symbolicTraits.contains(.bold)),
              (!traits.contains(.italicFontMask) || result.fontDescriptor.symbolicTraits.contains(.italic)) else {
            throw EaselTextClipboardError.unavailableFontStyle
        }
        return result
    }
    static func paletteFamily(_ font: NSFont) -> EaselTextStyle.Family? {
        EaselTextStyle.Family.allCases.first { family in
            EaselTextStyle.Size.allCases.contains { self.font(.init(family: family, size: $0)).familyName == font.familyName }
        }
    }
    static func paletteStyle(_ font: NSFont) -> EaselTextStyle? {
        for family in EaselTextStyle.Family.allCases {
            for size in EaselTextStyle.Size.allCases {
                let style = EaselTextStyle(family: family, size: size), candidate = self.font(style)
                if candidate.familyName == font.familyName, abs(candidate.pointSize - font.pointSize) < 0.1 { return style }
            }
        }
        return nil
    }
    static func matchingStyle(_ font: NSFont) -> EaselTextStyle? {
        for family in EaselTextStyle.Family.allCases {
            for size in EaselTextStyle.Size.allCases {
                let style = EaselTextStyle(family: family, size: size), candidate = self.font(style)
                if abs(candidate.pointSize - font.pointSize) < 0.1, candidate.fontName == font.fontName { return style }
            }
        }
        return nil
    }
}

/// A single TextKit geometry owner for canvas drawing and the native editor.
///
/// indexed caller discards that return value. Native glyph metrics remain real.
@MainActor
enum EaselTextLayout {
    static let inset = NSSize(width: 5, height: 4)
    static let fragmentPadding: CGFloat = 5
    static func radius(_ style: EaselTextStyle) -> CGFloat { [6, 8, 10, 10, 10][style.size.index] }

    @MainActor final class Layout {
        let storage: NSTextStorage
        let manager = NSLayoutManager()
        let container: NSTextContainer
        init(_ value: NSAttributedString, width: CGFloat, height: CGFloat = 1_000_000) {
            storage = NSTextStorage(attributedString: value)
            container = NSTextContainer(size: NSSize(width: max(1, width - inset.width * 2), height: max(1, height - inset.height * 2)))
            container.lineFragmentPadding = fragmentPadding
            manager.addTextContainer(container); storage.addLayoutManager(manager)
            EaselTextAttachments.bind(storage, container: container)
            manager.ensureLayout(for: container)
        }
        var height: CGFloat { ceil(max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)) + inset.height * 2 }
        func draw(at origin: NSPoint, style: EaselTextStyle) {
            let offset = NSPoint(x: origin.x + inset.width, y: origin.y + inset.height)
            if style.resolvedFill == .contentHugging {
                drawFill(manager: manager, container: container, origin: offset, style: style)
                manager.addTemporaryAttribute(.foregroundColor, value: NSColor.white, forCharacterRange: NSRange(location: 0, length: storage.length))
            }
            let range = manager.glyphRange(for: container)
            manager.drawBackground(forGlyphRange: range, at: offset)
            manager.drawGlyphs(forGlyphRange: range, at: offset)
            if style.resolvedFill == .contentHugging, storage.length > 0 {
                manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
            }
        }
    }

    ///
    /// native bounds, use cap height plus descent padding, then pad horizontally.
    /// Attachments keep their actual cell bounds; they are not font glyphs.
    static func lineRects(manager: NSLayoutManager, container: NSTextContainer) -> [NSRect] {
        guard let storage = manager.textStorage else { return [] }
        manager.ensureLayout(for: container)
        var result: [NSRect] = []
        let full = manager.glyphRange(for: container)
        manager.enumerateLineFragments(forGlyphRange: full) { _, _, _, glyphs, _ in
            var line = NSRect.null
            for index in glyphs.location..<NSMaxRange(glyphs) {
                let properties = manager.propertyForGlyph(at: index)
                let characters = manager.characterRange(forGlyphRange: NSRange(location: index, length: 1), actualGlyphRange: nil)
                guard characters.location < storage.length else { continue }
                let attrs = storage.attributes(at: characters.location, effectiveRange: nil)
                let bounds = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)
                guard bounds.width.isFinite, bounds.height.isFinite, !bounds.isEmpty else { continue }
                if attrs[.attachment] != nil { line = line.union(bounds); continue }
                guard !properties.contains(.controlCharacter), !properties.contains(.elastic), !properties.contains(.null) else { continue }
                let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
                var glyph = manager.cgGlyph(at: index)
                let advance = glyph == 0xffff ? bounds.width : CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
                let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
                let cap = CTFontGetCapHeight(font), leading = CTFontGetLeading(font), pad = max(6, descent * 1.3)
                let rect = NSRect(x: bounds.midX - advance / 2,
                    y: bounds.midY - (ascent + descent) / 2 + ascent - cap - pad + leading,
                    width: advance, height: cap + 2 * pad)
                if !rect.isEmpty { line = line.union(rect) }
            }
            guard !line.isNull, !line.isEmpty else { return }
            // The shipped plain-text owner takes its first native font here.
            // Per-line font selection extends that contract to mixed rich text.
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let font = characters.location < storage.length ? storage.attribute(.font, at: characters.location, effectiveRange: nil) as? NSFont : nil
            let padding = max(6, CTFontGetDescent(font ?? NSFont.systemFont(ofSize: 12)) * 1.3)
            result.append(line.insetBy(dx: -padding, dy: 0))
        }
        return result
    }

    ///
    /// compares only the previous pass's adjacent line edges, with strict <.
    static func smoothed(_ input: [NSRect], radius: CGFloat) -> [NSRect] {
        var rectangles = input
        for _ in 0..<3 {
            let previous = rectangles
            for index in previous.indices {
                var left = previous[index].minX, right = previous[index].maxX
                for neighbor in [index - 1, index + 1] where previous.indices.contains(neighbor) {
                    if abs(previous[index].minX - previous[neighbor].minX) < radius { left = min(left, previous[neighbor].minX) }
                    if abs(previous[index].maxX - previous[neighbor].maxX) < radius { right = max(right, previous[neighbor].maxX) }
                }
                rectangles[index] = NSRect(x: left, y: previous[index].minY, width: right - left, height: previous[index].height)
            }
        }
        return rectangles
    }

    static func fillPath(rects: [NSRect], radius: CGFloat) -> CGPath {
        let rectangles = CGMutablePath()
        for rect in smoothed(rects, radius: radius) where !rect.isEmpty && !rect.isNull {
            rectangles.addRect(rect)
        }
        //
        // All input rectangles share winding; normalization removes inner edges.
        let union = rectangles.normalized(using: .winding)
        let rounded = CGMutablePath()
        var vertices: [CGPoint] = []
        func finishContour() {
            if vertices.count > 1, vertices.first == vertices.last { vertices.removeLast() }
            guard vertices.count >= 3, let last = vertices.last else { vertices.removeAll(); return }
            let first = vertices[0]
            var midpoint = CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2)
            rounded.move(to: midpoint)
            for index in vertices.indices {
                let vertex = vertices[index], next = vertices[(index + 1) % vertices.count]
                let end = CGPoint(x: (vertex.x + next.x) / 2, y: (vertex.y + next.y) / 2)
                let incoming = abs(midpoint.x - vertex.x) + abs(midpoint.y - vertex.y)
                let outgoing = abs(end.x - vertex.x) + abs(end.y - vertex.y)
                rounded.addArc(tangent1End: vertex, tangent2End: end, radius: min(radius, incoming, outgoing))
                midpoint = end
            }
            rounded.closeSubpath(); vertices.removeAll()
        }
        union.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: finishContour(); vertices.append(element.pointee.points[0])
            case .addLineToPoint: vertices.append(element.pointee.points[0])
            case .closeSubpath: finishContour()
            default: break // Rectangular union contains only straight segments.
            }
        }
        finishContour()
        return rounded
    }

    static func drawFill(manager: NSLayoutManager, container: NSTextContainer, origin: NSPoint, style: EaselTextStyle) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let path = fillPath(rects: lineRects(manager: manager, container: container), radius: radius(style))
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: origin.x, y: origin.y)
        context.setFillColor(NSColor.black.cgColor); context.addPath(path); context.fillPath()
    }
}

enum EaselTextClipboardError: LocalizedError {
    case unsupportedFormatting, unsupportedAttachment, unavailableFontStyle
    var errorDescription: String? {
        switch self {
        case .unsupportedFormatting: return "That text includes formatting Parc cannot preserve yet. Choose Paste as Plain Text to keep the words."
        case .unsupportedAttachment: return "That attachment cannot be preserved as an image. Paste as Plain Text keeps only the surrounding words."
        case .unavailableFontStyle: return "That font does not provide the requested emphasis. Choose another font to preserve it."
        }
    }
}

struct EaselStyledText: Codable, Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType("org.parc.easel-styled-text.v3")
    static let previousPasteboardType = NSPasteboard.PasteboardType("org.parc.easel-styled-text.v2")
    static let legacyPasteboardType = NSPasteboard.PasteboardType("org.parc.easel-styled-text.v1")
    var version = 3
    var text: String
    var style: EaselTextStyle
    var color: String
    var richText: EaselRichText?

    @MainActor var attributed: NSAttributedString {
        EaselRichTextCodec.attributed(text, richText: richText, style: style, color: color)
    }
    @MainActor static func capture(_ value: NSAttributedString, style: EaselTextStyle, color: String) throws -> Self {
        let rich = try EaselRichTextCodec.snapshot(value)
        let plain = try EaselRichTextCodec.snapshot(EaselTextAppearance.attributed(value.string, style: style, color: color))
        return Self(text: value.string, style: style, color: color, richText: rich == plain ? nil : rich)
    }
    func validate() throws {
        guard [1, 2, 3].contains(version), text.utf8.count <= 1_048_576,
              color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw EaselStoreError.invalidDocument("styled text clipboard content")
        }
        try richText?.validate(text: text)
    }
    @MainActor func write(to pasteboard: NSPasteboard) throws {
        try validate()
        let encoded = try JSONEncoder().encode(self)
        let value = attributed
        // AppKit's RTF exporter substitutes its private system font; the
        // versioned carrier remains authoritative for exact Clean styling.
        let images = EaselTextAttachments.hasImages(value)
        let native = try value.data(from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: images ? NSAttributedString.DocumentType.rtfd : NSAttributedString.DocumentType.rtf])
        guard encoded.count <= 8_388_608, native.count <= (images ? 8_388_608 : 4_194_304) else { throw EaselStoreError.tooLarge }
        let item = NSPasteboardItem()
        item.setData(encoded, forType: Self.pasteboardType)
        item.setData(native, forType: images ? .rtfd : .rtf)
        item.setString(EaselTextAttachments.plainString(text), forType: .string)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
    }
    @MainActor static func plainText(from pasteboard: NSPasteboard) throws -> String? {
        let text: String
        if let string = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL) { text = string }
        else if let data = pasteboard.data(forType: .rtfd) {
            guard data.count <= 8_388_608 else { throw EaselStoreError.tooLarge }
            text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil).string
        } else if let rtf = pasteboard.data(forType: .rtf) {
            guard rtf.count <= 4_194_304 else { throw EaselStoreError.tooLarge }
            text = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
        } else { return nil }
        guard text.utf8.count <= 1_048_576 else { throw EaselStoreError.tooLarge }
        return EaselTextAttachments.plainString(text)
    }
    @MainActor static func read(from pasteboard: NSPasteboard) throws -> EaselStyledText? {
        if let type = pasteboard.availableType(from: [pasteboardType, previousPasteboardType, legacyPasteboardType]), let data = pasteboard.data(forType: type) {
            guard data.count <= 8_388_608 else { throw EaselStoreError.tooLarge }
            var value = try JSONDecoder().decode(Self.self, from: data)
            try value.validate()
            for run in value.richText?.runs ?? [] { if let image = run.attributes.image { _ = try EaselTextAttachments.image(data: image.data) } }
            value.version = 3; return value
        }
        let type = pasteboard.availableType(from: [.rtfd, .rtf])
        guard let type, let data = pasteboard.data(forType: type) else { return nil }
        guard data.count <= (type == .rtfd ? 8_388_608 : 4_194_304) else { throw EaselStoreError.tooLarge }
        let decoded = try NSAttributedString(data: data,
            options: [.documentType: type == .rtfd ? NSAttributedString.DocumentType.rtfd : NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let value = try EaselTextAttachments.normalized(decoded)
        let attrs = value.length > 0 ? value.attributes(at: 0, effectiveRange: nil) : [:]
        let style = (attrs[.font] as? NSFont).flatMap(EaselTextAppearance.matchingStyle) ?? EaselTextStyle()
        let ink = try EaselRichTextCodec.hex((attrs[.foregroundColor] as? NSColor) ?? EaselTextAppearance.color("#252525"))
        let result = try capture(value, style: style, color: String(ink.prefix(7)))
        try result.validate(); return result
    }
}

/// A text object owns its local editing history, as in EaselTextView's
/// undoManagerForTextView:. Document-level undo stays with EaselSession.
final class EaselStyledTextView: LocalContentDropTextView {
    let localUndo = UndoManager()
    var hasLoadedDocument = false
    var usesEaselObjectLayout = false
    var onObjectLayoutChanged: (() -> Void)?
    var objectStyle = EaselTextStyle() { didSet { refreshObjectFill() } }
    func refreshObjectFill() {
        guard usesEaselObjectLayout, let layoutManager else { return }
        let range = NSRange(location: 0, length: (string as NSString).length)
        if objectStyle.resolvedFill == .contentHugging {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.white, forCharacterRange: range)
            insertionPointColor = .white
        } else {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            insertionPointColor = .textColor
        }
        needsDisplay = true; onObjectLayoutChanged?()
    }
    /// A document editor may own a different default body size than the Easel
    /// palette. Nil keeps the existing object palette behavior for canvas text.
    var paragraphBodyPointSize: CGFloat?
    var objectColor = "#252525"
    var onClipboardError: ((Error) -> Void)?
    var onUndoDocument: (() -> Void)?
    var onRedoDocument: (() -> Void)?
    var canUndoDocument: (() -> Bool)?
    var canRedoDocument: (() -> Bool)?
    override var undoManager: UndoManager? { localUndo }
    var onEditBoundary: (() -> Void)?
    private var linkPopover: NSPopover?
    var hasPendingRangeAction: Bool { linkPopover?.isShown == true }
    private var editRevision = UUID()
    private var suppressMarkdown = false

    func selectedPayload() throws -> EaselStyledText? {
        let range = selectedRange()
        guard range.length > 0 else { return nil }
        return try EaselStyledText.capture(attributedString().attributedSubstring(from: range), style: objectStyle, color: objectColor)
    }
    private func copySelection() -> Bool {
        do {
            guard let payload = try selectedPayload() else { return false }
            try payload.write(to: .general); return true
        } catch { onClipboardError?(error); return false }
    }
    override func didChangeText() {
        editRevision = UUID()
        EaselTextAttachments.bind(attributedString(), container: textContainer)
        typingAttributes.removeValue(forKey: .attachment)
        refreshObjectFill()
        super.didChangeText()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { retire() }; super.viewWillMove(toWindow: newWindow)
    }
    func finishComposition() {
        guard hasMarkedText() else { return }
        unmarkText(); didChangeText()
    }
    func retire() { linkPopover?.close(); linkPopover = nil; editRevision = UUID() }
    func resetEditingHistory() {
        // Shared-session rollback can run inside an active native event group.
        // Clear its actions while preserving the caller's balanced grouping.
        let level = localUndo.groupingLevel, automatic = localUndo.groupsByEvent
        localUndo.groupsByEvent = false
        localUndo.removeAllActions()
        for _ in 0..<level { localUndo.beginUndoGrouping() }
        localUndo.groupsByEvent = automatic
        if level > 0 {
            let revision = editRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editRevision == revision, self.localUndo.groupingLevel == 0 else { return }
                // Drop only empty replacement groups after their original
                // caller/event closes them. A newer edit keeps its own history.
                self.localUndo.removeAllActions()
            }
        }
    }

    func pasteContent(from board: NSPasteboard, plain: Bool = false) -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else { return false }
        let suppressed = suppressMarkdown; suppressMarkdown = true
        defer { suppressMarkdown = suppressed }
        do {
            if !plain, let url = try EaselClipboardURL.read(from: board) {
                return try pasteLink(url)
            }
            if !plain, let payload = try EaselStyledText.read(from: board) {
                insertText(payload.attributed, replacementRange: selectedRange()); return true
            }
            if !plain, let data = try EaselTextAttachments.pastedImageData(from: board) {
                return try insertImage(data)
            }
            if let text = try EaselStyledText.plainText(from: board) {
                return try pastePlainText(text)
            }
        } catch { onClipboardError?(error) }
        return false
    }
    private func pastePlainText(_ text: String) throws -> Bool {
        let before = attributedString(), range = selectedRange()
        guard Self.validFormattingRanges([range], length: before.length) else { return false }
        var typing = typingAttributes
        typing.removeValue(forKey: .attachment); typing.removeValue(forKey: .link)
        let input = NSAttributedString(string: text, attributes: typing)
        var replacement = range
        // Match native structured insertion when a paste joins list paragraphs.
        if (before.string as NSString).substring(with: range).contains("\n"), NSMaxRange(range) < before.length {
            let ending = (before.string as NSString).paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let prefix = EaselParagraphEditing.markerRange(before, paragraph: ending)
            if NSMaxRange(range) <= NSMaxRange(prefix) { replacement.length = NSMaxRange(prefix) - replacement.location }
        }
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: before), selection: replacement, typing: typing)
        EaselParagraphEditing.replace(&edit, range: replacement, with: input)
        edit.selection = NSRange(location: replacement.location + input.length, length: 0)
        if text.contains("\n") || (before.string as NSString).substring(with: range).contains("\n") { EaselParagraphEditing.renumber(&edit) }
        // Joining differently styled paragraphs makes NSTextStorage choose one
        // paragraph style. Validate and compare that native result, not the
        // pre-normalization ranges which would report failure after a real edit.
        let normalized = NSTextStorage(attributedString: edit.text)
        normalized.fixAttributes(in: NSRange(location: 0, length: normalized.length))
        edit.text = NSMutableAttributedString(attributedString: normalized)
        _ = try EaselRichTextCodec.snapshot(edit.text)
        // NSTextView's insertText preserves a replaced link even for an
        // attributed argument without .link. Commit the explicit plain candidate
        // through the existing delegate/Undo owner so that link cannot leak.
        commitParagraph(edit, name: "Paste text")
        return attributedString().isEqual(to: edit.text)
    }
    ///
    /// selected self-labelled link, which is replaced by the incoming URL.
    private func pasteLink(_ url: URL) throws -> Bool {
        let before = attributedString(), range = selectedRange()
        guard Self.validFormattingRanges([range], length: before.length) else { return false }
        let selected = before.attributedSubstring(from: range)
        // A URL must never replace an attachment's only byte-bearing character
        // merely to make it a label. Keep that unsupported edit atomic.
        guard !EaselTextAttachments.hasImages(selected) else { throw EaselTextClipboardError.unsupportedAttachment }
        var typing = typingAttributes
        typing.removeValue(forKey: .attachment); typing.removeValue(forKey: .link)
        let replacement: NSMutableAttributedString
        if selected.length == 0 || EaselClipboardURL.isSelfLabelled(selected) {
            replacement = NSMutableAttributedString(string: url.absoluteString, attributes: typing)
        } else { replacement = NSMutableAttributedString(attributedString: selected) }
        replacement.addAttribute(.link, value: url, range: NSRange(location: 0, length: replacement.length))
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: before), selection: range, typing: typing)
        EaselParagraphEditing.replace(&edit, range: range, with: replacement)
        edit.selection = NSRange(location: range.location + replacement.length, length: 0)
        // Validate the entire candidate before entering the native delegate and
        // single undo transaction; imported labels keep their original styles.
        _ = try EaselRichTextCodec.snapshot(edit.text)
        commitParagraph(edit, name: "Paste link")
        return attributedString().isEqual(to: edit.text)
    }
    @discardableResult
    func insertImage(_ data: Data) throws -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else { return false }
        let image = try EaselTextAttachments.image(data: data)
        let before = attributedString(), range = selectedRange()
        guard range.location <= before.length, range.length <= before.length - range.location else { return false }
        var typing = typingAttributes; typing.removeValue(forKey: .attachment)
        let replacement = NSMutableAttributedString(string: "")
        if range.location > 0,
           !(before.string as NSString).substring(with: NSRange(location: range.location - 1, length: 1)).unicodeScalars.allSatisfy(CharacterSet.newlines.contains) {
            replacement.append(NSAttributedString(string: "\n", attributes: typing))
        }
        let character = EaselTextAttachments.character(image, attributes: typing)
        replacement.append(character)
        // NSTextStorage makes paragraph attributes uniform through its newline.
        // Include that native normalization in the prepared transaction too.
        var boundary = character.attributes(at: 0, effectiveRange: nil); boundary.removeValue(forKey: .attachment)
        replacement.append(NSAttributedString(string: "\n", attributes: boundary))
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: before), selection: range, typing: typing)
        EaselParagraphEditing.replace(&edit, range: range, with: replacement)
        edit.selection = NSRange(location: range.location + replacement.length, length: 0)
        EaselParagraphEditing.renumber(&edit)
        // One undo includes the original range, line boundaries and image.
        commitParagraph(edit, name: "Insert image")
        return attributedString().isEqual(to: edit.text)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let markdown = markdownAdmission(insertString, replacement: range)
        defer { if let markdown { applyMarkdown(markdown) } }
        let value = attributedString()
        let input = (insertString as? NSAttributedString) ?? (insertString as? String).map { NSAttributedString(string: $0, attributes: typingAttributes) }
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, let input,
              range.location <= value.length, range.length <= value.length - range.location,
              input.string.contains("\n") || (value.string as NSString).substring(with: range).contains("\n") else {
            super.insertText(insertString, replacementRange: replacementRange); return
        }
        var hasList = false
        value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { p, _, _ in
            if (p as? NSParagraphStyle)?.textLists.isEmpty == false { hasList = true }
        }
        guard hasList else { super.insertText(insertString, replacementRange: replacementRange); return }
        var replacement = range
        // Joining paragraphs consumes the following structural marker, rather
        // than leaving an apparent second bullet in the middle of a sentence.
        if (value.string as NSString).substring(with: range).contains("\n"), NSMaxRange(range) < value.length {
            let ending = (value.string as NSString).paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let prefix = EaselParagraphEditing.markerRange(value, paragraph: ending)
            if NSMaxRange(range) <= NSMaxRange(prefix) { replacement.length = NSMaxRange(prefix) - replacement.location }
        }
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: value), selection: replacement, typing: typingAttributes)
        EaselParagraphEditing.replace(&edit, range: replacement, with: input)
        edit.selection.length = 0
        EaselParagraphEditing.renumber(&edit)
        commitParagraph(edit, name: input.length == 0 ? "Delete text" : "Insert text")
    }
    private func markdownAdmission(_ input: Any, replacement: NSRange) -> EaselMarkdownEditing.Admission? {
        guard isEditable, !suppressMarkdown, !hasMarkedText(), selectedRanges.count == 1,
              !localUndo.isUndoing, !localUndo.isRedoing else { return nil }
        return EaselMarkdownEditing.admission(input, text: string, selection: selectedRange(), replacement: replacement)
    }
    private func applyMarkdown(_ admission: EaselMarkdownEditing.Admission) {
        guard isEditable, !suppressMarkdown, !hasMarkedText(), selectedRanges.count == 1,
              !localUndo.isUndoing, !localUndo.isRedoing,
              let edit = EaselMarkdownEditing.transform(attributedString(), admission: admission,
                  selection: selectedRange(), typing: typingAttributes, base: objectStyle) else { return }
        suppressMarkdown = true; defer { suppressMarkdown = false }
        commitParagraph(edit, name: "Format Markdown")
    }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        guard let selected = try? selectedPayload() else { return [] }
        return [EaselStyledText.pasteboardType, EaselTextAttachments.hasImages(selected.attributed) ? .rtfd : .rtf, .string]
    }
    override func writeSelection(to board: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        do {
            guard let selected = try selectedPayload() else { return false }
            try selected.validate()
            if type == .string { return board.setString(EaselTextAttachments.plainString(selected.text), forType: type) }
            let data: Data
            if type == EaselStyledText.pasteboardType { data = try JSONEncoder().encode(selected) }
            else if type == .rtfd || (type == .rtf && !EaselTextAttachments.hasImages(selected.attributed)) {
                let value = selected.attributed
                data = try value.data(from: NSRange(location: 0, length: value.length),
                    documentAttributes: [.documentType: type == .rtfd ? NSAttributedString.DocumentType.rtfd : NSAttributedString.DocumentType.rtf])
            } else { return false }
            guard data.count <= (type == .rtf ? 4_194_304 : 8_388_608) else { throw EaselStoreError.tooLarge }
            return board.setData(data, forType: type)
        } catch { onClipboardError?(error); return false }
    }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType,
         .rtfd, .rtf, .fileURL, .png, .tiff, .URL, .string]
    }
    override func paste(_ sender: Any?) { _ = pasteContent(from: .general) }
    override func pasteAsPlainText(_ sender: Any?) { _ = pasteContent(from: .general, plain: true) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { pasteContent(from: pboard) }

    /// AppKit may replace a rendered glyph's font while retaining the authored
    /// face in NSOriginalFont. Edit that face, as the durable codec already does,
    /// then let layout choose a fresh fallback for the newly formatted glyph.
    private func authoredAttributes(_ attributes: [NSAttributedString.Key: Any]) throws -> [NSAttributedString.Key: Any] {
        let key = NSAttributedString.Key("NSOriginalFont")
        guard let value = attributes[key] else { return attributes }
        guard let font = value as? NSFont else { throw EaselTextClipboardError.unsupportedFormatting }
        var result = attributes
        result[.font] = font; result.removeValue(forKey: key)
        return result
    }

    /// Attribute edits use the same native text-storage/undo owner as typing.
    /// A collapsed selection changes typing attributes only, never other text.
    func format(_ name: String, ranges suppliedRanges: [NSRange]? = nil, _ change: ([NSAttributedString.Key: Any]) throws -> [NSAttributedString.Key: Any]) {
        guard isEditable, !hasMarkedText() else { return }
        let selections = selectedRanges.map(\.rangeValue)
        let ranges = suppliedRanges ?? [selectedRange()]
        guard Self.validFormattingRanges(ranges, length: attributedString().length) else { return }
        if ranges.count == 1, ranges[0].length == 0 {
            do { typingAttributes = try change(authoredAttributes(typingAttributes)) } catch { onClipboardError?(error) }
            window?.makeFirstResponder(self); return
        }
        let before = NSAttributedString(attributedString: attributedString())
        let result = NSMutableAttributedString(attributedString: before)
        var failure: Error?
        for range in ranges {
            before.enumerateAttributes(in: range) { attrs, part, stop in
                do { result.setAttributes(try change(authoredAttributes(attrs)), range: part) }
                catch { failure = error; stop.pointee = true }
            }
            if failure != nil { break }
        }
        do { if let failure { throw failure }; _ = try EaselRichTextCodec.snapshot(result) }
        catch { onClipboardError?(error); return }
        guard !result.isEqual(to: before) else { return }
        localUndo.disableUndoRegistration()
        let accepted = shouldChangeText(inRanges: ranges.map(NSValue.init(range:)), replacementStrings: nil)
        localUndo.enableUndoRegistration()
        guard accepted else { selectedRanges = selections.map(NSValue.init(range:)); return }
        breakUndoCoalescing(); onEditBoundary?()
        restoreFormatting(result, selections: selections, name: name, replacingSelection: selections)
        window?.makeFirstResponder(self)
    }
    private func restoreFormatting(_ value: NSAttributedString, selections: [NSRange], name: String, replacingSelection: [NSRange]? = nil) {
        // Native shouldChangeText may temporarily select its combined edit
        // span. Undo belongs to the selection before that delegate preflight.
        let original = NSAttributedString(attributedString: attributedString()), originalSelections = replacingSelection ?? selectedRanges.map(\.rangeValue)
        localUndo.registerUndo(withTarget: self) { view in view.restoreFormatting(original, selections: originalSelections, name: name) }
        localUndo.setActionName(name)
        textStorage?.setAttributedString(value); selectedRanges = selections.map(NSValue.init(range:)); didChangeText()
    }
    static func validFormattingRanges(_ ranges: [NSRange], length: Int) -> Bool {
        guard !ranges.isEmpty else { return false }
        let sorted = ranges.sorted { $0.location < $1.location }
        var end = 0
        for (index, range) in sorted.enumerated() {
            guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
                  range.location <= length, range.length <= length - range.location,
                  index == 0 || range.location >= end else { return false }
            end = NSMaxRange(range)
        }
        return true
    }
    func paragraphKind() -> EaselParagraphEditing.Kind? {
        let value = attributedString(), selection = selectedRange()
        let ranges = EaselParagraphEditing.ranges(string, selection: selection)
        let kinds = ranges.map { range in
            EaselParagraphEditing.kind(range.location < value.length ? value.attributes(at: range.location, effectiveRange: nil) : typingAttributes)
        }
        guard let first = kinds.first, kinds.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    func changeParagraph(_ kind: EaselParagraphEditing.Kind, ranges suppliedRanges: [NSRange]? = nil) {
        let ranges = suppliedRanges ?? [selectedRange()]
        guard isEditable, !hasMarkedText(), suppliedRanges != nil || selectedRanges.count == 1,
              Self.validFormattingRanges(ranges, length: attributedString().length) else { return }
        commitParagraph(EaselParagraphEditing.apply(kind, to: attributedString(), selections: ranges, typing: typingAttributes, base: objectStyle, bodyPointSize: paragraphBodyPointSize), name: kind.rawValue)
    }
    private func commitParagraph(_ edit: EaselParagraphEditing.Edit, name: String) {
        do { _ = try EaselRichTextCodec.snapshot(edit.text) } catch { onClipboardError?(error); return }
        // Ask the native delegate before mutation, but own one complete undo
        // record; NSTextView otherwise also records its replace-characters undo.
        let originalSelections = selectedRanges.map(\.rangeValue)
        localUndo.disableUndoRegistration()
        let accepted = shouldChangeText(in: NSRange(location: 0, length: (string as NSString).length), replacementString: edit.text.string)
        localUndo.enableUndoRegistration()
        guard accepted else { selectedRanges = originalSelections.map(NSValue.init(range:)); return }
        breakUndoCoalescing(); onEditBoundary?()
        restoreParagraph(edit.text, selections: edit.selections, typing: edit.typing, name: name, replacingSelection: originalSelections)
        window?.makeFirstResponder(self)
    }
    private func restoreParagraph(_ value: NSAttributedString, selections: [NSRange], typing: [NSAttributedString.Key: Any], name: String, replacingSelection: [NSRange]? = nil) {
        let original = NSAttributedString(attributedString: attributedString()), oldSelections = replacingSelection ?? selectedRanges.map(\.rangeValue), oldTyping = typingAttributes
        localUndo.registerUndo(withTarget: self) { view in view.restoreParagraph(original, selections: oldSelections, typing: oldTyping, name: name) }
        localUndo.setActionName(name)
        localUndo.disableUndoRegistration()
        textStorage?.setAttributedString(value); selectedRanges = selections.map(NSValue.init(range:)); typingAttributes = typing
        localUndo.enableUndoRegistration()
        // The durable edit delegate may reject a save and clear native history.
        // Restore registration before that reentrant owner runs.
        didChangeText()
    }
    func changeListIndent(outdent: Bool) -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else { return false }
        if let edit = EaselParagraphEditing.indent(attributedString(), selection: selectedRange(), typing: typingAttributes, outdent: outdent, base: objectStyle) {
            commitParagraph(edit, name: outdent ? "Decrease list indent" : "Increase list indent"); return true
        }
        // A list at the recovered maximum depth consumes Tab without inserting
        // an unstructured tab into its marker. Ordinary text keeps native Tab.
        return paragraphKind() == .bullets || paragraphKind() == .numbers
    }
    override func insertTab(_ sender: Any?) {
        let markdown = markdownAdmission("\t", replacement: selectedRange())
        defer { if let markdown { applyMarkdown(markdown) } }
        if !changeListIndent(outdent: false) { super.insertTab(sender) }
    }
    override func insertBacktab(_ sender: Any?) {
        if !changeListIndent(outdent: true) { super.insertBacktab(sender) }
    }
    override func insertNewline(_ sender: Any?) {
        let markdown = markdownAdmission("\n", replacement: selectedRange())
        defer { if let markdown { applyMarkdown(markdown) } }
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1,
              let edit = EaselParagraphEditing.newline(attributedString(), selection: selectedRange(), typing: typingAttributes, base: objectStyle, bodyPointSize: paragraphBodyPointSize) else {
            super.insertNewline(sender); return
        }
        commitParagraph(edit, name: "New paragraph")
    }
    override func deleteBackward(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else { super.deleteBackward(sender); return }
        let selection = selectedRange(), value = attributedString()
        if selection.length > 0 {
            insertText("", replacementRange: selection); return
        }
        guard let range = EaselParagraphEditing.ranges(string, selection: selection).first else { super.deleteBackward(sender); return }
        let prefix = EaselParagraphEditing.markerRange(value, paragraph: range)
        let attrs = range.location < value.length ? value.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        if selection.location <= NSMaxRange(prefix), !EaselParagraphEditing.style(attrs).textLists.isEmpty {
            _ = changeListIndent(outdent: true); return
        }
        if selection.location == range.location, EaselParagraphEditing.style(attrs).headerLevel > 0 {
            changeParagraph(.text); return
        }
        if selection.location > 0, (string as NSString).substring(with: NSRange(location: selection.location - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil {
            insertText("", replacementRange: NSRange(location: selection.location - 1, length: 1)); return
        }
        super.deleteBackward(sender)
    }
    override func deleteForward(_ sender: Any?) {
        let selection = selectedRange(), length = (string as NSString).length
        if isEditable, !hasMarkedText(), selectedRanges.count == 1,
           selection.length > 0 || (selection.location < length && (string as NSString).substring(with: NSRange(location: selection.location, length: 1)).rangeOfCharacter(from: .newlines) != nil) {
            insertText("", replacementRange: selection.length > 0 ? selection : NSRange(location: selection.location, length: 1)); return
        }
        super.deleteForward(sender)
    }
    func changeStyle(preservingSize: Bool = false, _ mutation: (inout EaselTextStyle) -> Void) {
        format("Style text") { attrs in
            var next = attrs
            let current = (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(self.objectStyle)
            let matched = EaselTextAppearance.paletteStyle(current)
            var style = matched ?? EaselTextStyle(family: EaselTextAppearance.paletteFamily(current) ?? self.objectStyle.family, size: .body)
            mutation(&style)
            let replacement = try EaselTextAppearance.font(style, preservingEmphasisFrom: current)
            // Changing family must not replace a paragraph heading's actual
            // 32/26/22-point size with the object palette's unrelated Body size.
            next[.font] = matched == nil && preservingSize
                ? NSFontManager.shared.convert(replacement, toSize: current.pointSize) : replacement
            return next
        }
    }
    enum Emphasis: String, CaseIterable { case bold, italic, underline, strikethrough }
    func hasEmphasis(_ emphasis: Emphasis) -> Bool { hasEmphasis(emphasis, ranges: nil) }
    func hasEmphasis(_ emphasis: Emphasis, ranges suppliedRanges: [NSRange]?) -> Bool {
        let ranges = suppliedRanges ?? [selectedRange()]
        guard Self.validFormattingRanges(ranges, length: attributedString().length) else { return false }
        func contains(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
            guard let attrs = try? authoredAttributes(attributes) else { return false }
            switch emphasis {
            case .bold: return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
            case .italic: return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true
            case .underline: return (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0
            case .strikethrough: return (attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0 != 0
            }
        }
        if ranges.count == 1, ranges[0].length == 0 { return contains(typingAttributes) }
        var result = true
        for range in ranges { attributedString().enumerateAttributes(in: range) { attrs, _, _ in result = result && contains(attrs) } }
        return result
    }
    func toggle(_ emphasis: Emphasis, ranges: [NSRange]? = nil) {
        let remove = hasEmphasis(emphasis, ranges: ranges)
        format(emphasis.rawValue.capitalized, ranges: ranges) { attrs in
            var next = attrs
            switch emphasis {
            case .bold, .italic:
                let font = (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(self.objectStyle)
                let trait: NSFontTraitMask = emphasis == .bold ? .boldFontMask : .italicFontMask
                let replacement = remove ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
                let symbolic: NSFontDescriptor.SymbolicTraits = emphasis == .bold ? .bold : .italic
                guard replacement.fontDescriptor.symbolicTraits.contains(symbolic) != remove else { throw EaselTextClipboardError.unavailableFontStyle }
                next[.font] = replacement
            case .underline: next[.underlineStyle] = remove ? nil : NSUnderlineStyle.single.rawValue
            case .strikethrough: next[.strikethroughStyle] = remove ? nil : NSUnderlineStyle.single.rawValue
            }
            return next
        }
    }
    func editLink(relativeTo anchor: NSView, ranges suppliedRanges: [NSRange]? = nil, validate: (() -> Bool)? = nil) {
        let ranges = suppliedRanges ?? [selectedRange()], originalSelections = selectedRanges
        guard Self.validFormattingRanges(ranges, length: attributedString().length), ranges.allSatisfy({ $0.length > 0 }),
              !hasMarkedText(), window != nil else { return }
        linkPopover?.close()
        let range = ranges[0], revision = editRevision
        let value = attributedString().attribute(.link, at: range.location, effectiveRange: nil)
        let controller = EaselLinkEditor(value: (value as? URL)?.absoluteString ?? value as? String ?? "")
        let popover = NSPopover(); popover.behavior = .transient; popover.contentViewController = controller
        linkPopover = popover
        controller.onCommit = { [weak self, weak popover] link in
            guard let self, self.editRevision == revision, self.selectedRanges == originalSelections, self.window != nil, validate?() != false else { popover?.close(); return }
            self.format(link == nil ? "Remove link" : "Edit link", ranges: ranges) { attrs in var next = attrs; next[.link] = link; return next }
            popover?.close(); self.linkPopover = nil
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    @objc func undo(_ sender: Any?) {
        if localUndo.canUndo { localUndo.undo() } else { onUndoDocument?() }
    }
    @objc func redo(_ sender: Any?) {
        if localUndo.canRedo { localUndo.redo() } else { onRedoDocument?() }
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return localUndo.canUndo || canUndoDocument?() == true }
        if item.action == #selector(redo(_:)) { return localUndo.canRedo || canRedoDocument?() == true }
        return super.validateUserInterfaceItem(item)
    }
    override func copy(_ sender: Any?) { _ = copySelection() }
    override func cut(_ sender: Any?) {
        guard isEditable, copySelection() else { return }
        insertText("", replacementRange: selectedRange())
    }

}

/// Recovered 50×88 TextMenu rail. The inline disclosure preserves native rich
/// formatting/fill controls in the same responder subtree as the text owner.
final class EaselTextStyleBar: NSView {
    var onVisibilityChange: ((Bool) -> Void)?
    private let details = EaselSurfaceView(frame: .zero)
    private let fontButton = EaselPaletteButton(title: "Aa", target: nil, action: nil)
    private var expanded = false
    var onLayoutChange: (() -> Void)?
    private let families = PointingHandPopUpButton(frame: .zero, pullsDown: false)
    private let sizes = PointingHandPopUpButton(frame: .zero, pullsDown: false)
    private let smaller = EaselPaletteButton(title: "−", target: nil, action: nil)
    private let larger = EaselPaletteButton(title: "+", target: nil, action: nil)
    private var emphasisButtons: [NSButton] = []
    private let link = EaselPaletteButton(title: "Link…", target: nil, action: nil)
    private let paragraphs = PointingHandPopUpButton(frame: .zero, pullsDown: false)
    private let fill = PointingHandButton(checkboxWithTitle: "Text fill", target: nil, action: nil)
    private var displayedFillState: NSControl.StateValue = .off
    var onFill: ((EaselTextStyle.Fill) -> Void)?
    private var isEditing = false
    var onParagraph: ((EaselParagraphEditing.Kind) -> Void)?
    var onEmphasis: ((EaselStyledTextView.Emphasis) -> Void)?
    var onLink: ((NSView) -> Void)?
    var onFamily: ((EaselTextStyle.Family) -> Void)?
    var onSize: ((EaselTextStyle.Size) -> Void)?
    var onResize: ((Int) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(details); details.isHidden = true
        fontButton.target = self; fontButton.action = #selector(toggleDetails)
        fontButton.setAccessibilityLabel("Text formatting"); fontButton.setAccessibilityHelp("Show font, size, fill and range formatting controls")
        fontButton.setButtonType(.pushOnPushOff); addSubview(fontButton)
        fill.target = self; fill.action = #selector(selectFill); fill.allowsMixedState = true
        fill.setAccessibilityLabel("Content-hugging text fill"); details.addSubview(fill)
        families.addItems(withTitles: ["Mono", "Fancy", "Hip", "Clean"])
        sizes.addItems(withTitles: ["Body", "Heading 2", "Heading 1", "Title", "Display"])
        families.target = self; families.action = #selector(selectFamily)
        sizes.target = self; sizes.action = #selector(selectSize)
        smaller.target = self; smaller.action = #selector(decrease)
        larger.target = self; larger.action = #selector(increase)
        for button in [smaller, larger] { button.font = .systemFont(ofSize: 14) }
        for popup in [families, sizes, paragraphs] { popup.isBordered = false; popup.font = .systemFont(ofSize: 12) }
        families.setAccessibilityLabel("Text family"); sizes.setAccessibilityLabel("Text size")
        smaller.setAccessibilityLabel("Decrease text size"); larger.setAccessibilityLabel("Increase text size")
        [families, sizes].forEach(details.addSubview)
        [smaller, larger].forEach(addSubview)
        for (index, emphasis) in EaselStyledTextView.Emphasis.allCases.enumerated() {
            let button = EaselPaletteButton(title: ["B", "I", "U", "S̶"][index], target: self, action: #selector(formatSelection(_:)))
            button.tag = index; button.bezelStyle = .texturedRounded; button.setButtonType(.pushOnPushOff)
            button.setAccessibilityLabel(emphasis.rawValue.capitalized); button.toolTip = emphasis.rawValue.capitalized
            details.addSubview(button); emphasisButtons.append(button)
        }
        link.bezelStyle = .texturedRounded; link.target = self; link.action = #selector(editLink)
        link.setAccessibilityLabel("Edit link for selected text"); details.addSubview(link)
        paragraphs.addItems(withTitles: EaselParagraphEditing.Kind.allCases.map(\.rawValue))
        paragraphs.target = self; paragraphs.action = #selector(chooseParagraph)
        paragraphs.setAccessibilityLabel("Paragraph format"); paragraphs.toolTip = "Format current paragraphs. Tab and Shift-Tab change list indentation."; details.addSubview(paragraphs)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func layout() {
        super.layout()
        // The rail keeps its original dimensions even when the rich disclosure
        // is taller; controls are 24pt with 4pt inter-control spacing.
        let railY = (bounds.height - 88) / 2
        larger.frame = NSRect(x: 13, y: railY + 60, width: 24, height: 24)
        fontButton.frame = NSRect(x: 13, y: railY + 32, width: 24, height: 24)
        smaller.frame = NSRect(x: 13, y: railY + 4, width: 24, height: 24)
        details.frame = NSRect(x: 54, y: 0, width: isEditing ? 280 : 200, height: isEditing ? 124 : 85)
        families.frame = NSRect(x: 6, y: isEditing ? 94 : 50, width: isEditing ? 116 : 90, height: 25)
        sizes.frame = NSRect(x: isEditing ? 132 : 100, y: isEditing ? 94 : 50, width: isEditing ? 142 : 94, height: 25)
        fill.frame = NSRect(x: 8, y: isEditing ? 69 : 12, width: isEditing ? 264 : 184, height: 25)
        for (index, button) in emphasisButtons.enumerated() { button.frame = NSRect(x: 6 + index * 37, y: 37, width: 33, height: 25) }
        link.frame = NSRect(x: 164, y: 37, width: 110, height: 25)
        paragraphs.frame = NSRect(x: 6, y: 5, width: 268, height: 25)
    }
    var preferredWidth: CGFloat { expanded ? (isEditing ? 334 : 254) : 50 }
    var preferredHeight: CGFloat { expanded && isEditing ? 124 : 88 }
    func collapse() {
        guard expanded else { return }
        if let responder = window?.firstResponder as? NSView, responder === details || responder.isDescendant(of: details) {
            window?.makeFirstResponder(superview)
        }
        expanded = false; details.isHidden = true; fontButton.state = .off; needsLayout = true
    }
    @objc private func toggleDetails() {
        if expanded { collapse() }
        else { expanded = true; details.isHidden = false; fontButton.state = .on; needsLayout = true }
        onLayoutChange?()
    }
    func update(styles: [EaselTextStyle], editor: EaselStyledTextView? = nil) {
        isEditing = editor != nil
        paragraphs.isHidden = !isEditing
        paragraphs.isEnabled = editor?.hasMarkedText() == false && editor?.selectedRanges.count == 1
        paragraphs.selectItem(at: editor?.paragraphKind().flatMap { EaselParagraphEditing.Kind.allCases.firstIndex(of: $0) } ?? -1)
        for (index, button) in emphasisButtons.enumerated() {
            button.isHidden = !isEditing; button.isEnabled = editor?.hasMarkedText() == false
            button.state = editor?.hasEmphasis(EaselStyledTextView.Emphasis.allCases[index]) == true ? .on : .off
        }
        link.isHidden = !isEditing; link.isEnabled = editor != nil && editor!.selectedRange().length > 0 && !editor!.hasMarkedText()
        needsLayout = true
        if let onVisibilityChange { onVisibilityChange(styles.isEmpty) }
        else { isHidden = styles.isEmpty }
        if styles.isEmpty { collapse() }
        guard let first = styles.first else { return }
        fill.state = styles.allSatisfy { $0.resolvedFill == first.resolvedFill } ? (first.resolvedFill == .contentHugging ? .on : .off) : .mixed
        displayedFillState = fill.state
        fill.isEnabled = editor?.hasMarkedText() != true
        families.selectItem(at: styles.allSatisfy { $0.family == first.family } ? EaselTextStyle.Family.allCases.firstIndex(of: first.family)! : -1)
        sizes.selectItem(at: styles.allSatisfy { $0.size == first.size } ? first.size.index : -1)
        smaller.isEnabled = styles.contains { $0.size != .body }; larger.isEnabled = styles.contains { $0.size != .ultra }
        if let editor {
            var selected: [EaselTextStyle?] = []
            let range = editor.selectedRange()
            if range.length == 0 { selected = [(editor.typingAttributes[.font] as? NSFont).flatMap(EaselTextAppearance.paletteStyle)] }
            else { editor.attributedString().enumerateAttribute(.font, in: range) { face, _, _ in selected.append((face as? NSFont).flatMap(EaselTextAppearance.paletteStyle)) } }
            let first = selected.first.flatMap { $0 }
            var selectedFamilies: [EaselTextStyle.Family?] = []
            if range.length == 0 { selectedFamilies = [(editor.typingAttributes[.font] as? NSFont).flatMap(EaselTextAppearance.paletteFamily)] }
            else { editor.attributedString().enumerateAttribute(.font, in: range) { face, _, _ in selectedFamilies.append((face as? NSFont).flatMap(EaselTextAppearance.paletteFamily)) } }
            let family = selectedFamilies.first.flatMap { $0 }
            families.selectItem(at: family != nil && selectedFamilies.allSatisfy({ $0 == family }) ? EaselTextStyle.Family.allCases.firstIndex(of: family!)! : -1)
            sizes.selectItem(at: first != nil && selected.allSatisfy({ $0?.size == first!.size }) ? first!.size.index : -1)
            smaller.isEnabled = !editor.hasMarkedText() && !selected.allSatisfy { $0?.size == .body }
            larger.isEnabled = !editor.hasMarkedText() && !selected.allSatisfy { $0?.size == .ultra }
            families.isEnabled = !editor.hasMarkedText(); sizes.isEnabled = !editor.hasMarkedText()
        } else { families.isEnabled = true; sizes.isEnabled = true }
    }
    @objc private func selectFill() {
        // AppKit cycles on → mixed for a tristate checkbox. Mixed is only a
        // selection summary here; activation toggles the displayed on state.
        onFill?(displayedFillState == .on ? .none : .contentHugging)
        fill.state = displayedFillState
    }
    @objc private func formatSelection(_ sender: NSButton) { onEmphasis?(EaselStyledTextView.Emphasis.allCases[sender.tag]) }
    @objc private func editLink() { onLink?(link) }
    @objc private func chooseParagraph() { guard paragraphs.indexOfSelectedItem >= 0 else { return }; onParagraph?(EaselParagraphEditing.Kind.allCases[paragraphs.indexOfSelectedItem]) }
    @objc private func selectFamily() { guard families.indexOfSelectedItem >= 0 else { return }; onFamily?(EaselTextStyle.Family.allCases[families.indexOfSelectedItem]) }
    @objc private func selectSize() { guard sizes.indexOfSelectedItem >= 0 else { return }; onSize?(EaselTextStyle.Size.allCases[sizes.indexOfSelectedItem]) }
    @objc private func decrease() { onResize?(-1) }
    @objc private func increase() { onResize?(1) }
}
