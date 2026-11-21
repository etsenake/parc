import AppKit
import CoreText

enum EaselTextAppearance {
    private static let registerFonts: Void = {
        let names = ["SpaceMono-Regular", "SpaceMono-Bold", "EBGaramond-VariableFont_wght",
                     "ParcWide-Regular", "ParcWide-SemiBold", "ParcWide-Black"]
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
            let name = style.size == .body ? "ParcWide-Regular" : style.size == .h2 ? "ParcWide-SemiBold" : "ParcWide-Black"
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
        }
    }

    static let inlineCodeFill = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.18)
    @MainActor static func isInlineCode(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let fill = attributes[.backgroundColor] as? NSColor, let font = attributes[.font] as? NSFont,
              font.fontDescriptor.symbolicTraits.contains(.monoSpace) else { return false }
        if EaselTextHighlight.note(of: fill) != nil { return isSystemMonospaced(font) }
        return (try? EaselRichTextCodec.hex(fill)) == (try? EaselRichTextCodec.hex(inlineCodeFill))
    }
    static func isSystemMonospaced(_ font: NSFont) -> Bool {
        font.fontName.hasPrefix(".AppleSystemUIFontMonospaced") || font.fontName.hasPrefix(".SFMono")
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

@MainActor
enum EaselTextLayout {
    static let inset = NSSize(width: 5, height: 4)
    static let fragmentPadding: CGFloat = 5
    static func scale(for item: EaselItem) -> Double { item.kind == .sticky ? EaselBoardObjects.textScale(item) : 1 }
    static func inset(scale: Double) -> NSSize { NSSize(width: inset.width * scale, height: inset.height * scale) }
    static func fragmentPadding(scale: Double) -> CGFloat { fragmentPadding * scale }
    static func radius(_ style: EaselTextStyle) -> CGFloat { [6, 8, 10, 10, 10][style.size.index] }

    @MainActor final class Layout {
        let storage: NSTextStorage
        let manager: NSLayoutManager = EaselChecklistLayoutManager()
        let container: NSTextContainer
        let inset: NSSize
        init(_ value: NSAttributedString, width: CGFloat, height: CGFloat = 1_000_000, scale: Double = 1) {
            storage = NSTextStorage(attributedString: value)
            let inset = EaselTextLayout.inset(scale: scale)
            self.inset = inset
            container = NSTextContainer(size: NSSize(width: max(1, width - inset.width * 2), height: max(1, height - inset.height * 2)))
            container.lineFragmentPadding = EaselTextLayout.fragmentPadding(scale: scale)
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

    static func sizeBadgeRect(_ label: String, below area: NSRect, scale: CGFloat) -> NSRect {
        let scale = max(scale, 0.05)
        let width = ceil((label as NSString).size(withAttributes: [.font: NoteTheme.chromeFont(11)]).width) + 18
        let size = NSSize(width: width / scale, height: 22 / scale)
        return NSRect(x: area.midX - size.width / 2, y: area.maxY + 10 / scale, width: size.width, height: size.height)
    }

    static func drawSizeBadge(_ label: String, in rect: NSRect, scale: CGFloat) {
        let scale = max(scale, 0.05)
        let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        EaselAppearance.surface.setFill(); pill.fill()
        EaselAppearance.outline.setStroke(); pill.lineWidth = 1 / scale; pill.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.chromeFont(11 / scale), .foregroundColor: EaselAppearance.text]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    static func drawLinkBadge(in rect: NSRect, scale: CGFloat) {
        let scale = max(scale, 0.05)
        let circle = NSBezierPath(ovalIn: rect)
        EaselAppearance.surface.setFill(); circle.fill()
        EaselAppearance.outline.setStroke(); circle.lineWidth = 1 / scale; circle.stroke()
        let configuration = NSImage.SymbolConfiguration(pointSize: 9 / scale, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [EaselAppearance.selection]))
        guard let symbol = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    static func drawWidthHandle(at point: NSPoint, scale: CGFloat) {
        let mark = NSRect(x: point.x - 3 / scale, y: point.y - 8 / scale, width: 6 / scale, height: 16 / scale)
        EaselAppearance.selection.setFill(); NSBezierPath(roundedRect: mark, xRadius: 3 / scale, yRadius: 3 / scale).fill()
        let inner = mark.insetBy(dx: 2 / scale, dy: 2.5 / scale)
        EaselAppearance.surface.setFill(); NSBezierPath(roundedRect: inner, xRadius: 1 / scale, yRadius: 1 / scale).fill()
    }

    static func naturalWidth(_ value: NSAttributedString) -> CGFloat {
        let storage = NSTextStorage(attributedString: value)
        EaselRichTextCodec.align(storage, to: .left)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100_000, height: 1_000_000))
        container.lineFragmentPadding = fragmentPadding
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        EaselTextAttachments.bind(storage, container: container)
        manager.ensureLayout(for: container)
        var width: CGFloat = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, used, _, _, _ in
            if used.width.isFinite { width = max(width, used.maxX) }
        }
        return ceil(width) + inset.width * 2
    }

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
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let font = characters.location < storage.length ? storage.attribute(.font, at: characters.location, effectiveRange: nil) as? NSFont : nil
            let padding = max(6, CTFontGetDescent(font ?? NSFont.systemFont(ofSize: 12)) * 1.3)
            result.append(line.insetBy(dx: -padding, dy: 0))
        }
        return result
    }

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
            default: break
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
        let value = EaselInlineText.readable(attributed)
        let images = EaselTextAttachments.hasImages(value)
        let native = try value.data(from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: images ? NSAttributedString.DocumentType.rtfd : NSAttributedString.DocumentType.rtf])
        guard encoded.count <= 8_388_608, native.count <= (images ? 8_388_608 : 4_194_304) else { throw EaselStoreError.tooLarge }
        let item = NSPasteboardItem()
        item.setData(encoded, forType: Self.pasteboardType)
        item.setData(native, forType: images ? .rtfd : .rtf)
        item.setString(EaselRichText.readable(text, rich: richText), forType: .string)
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

enum EaselTextRequest {
    case mention(dates: Bool)
    case inlineEquation
    case activate(Int)
    case customEmoji(String, NSRange)
}

@MainActor
protocol EaselTextCompletion: AnyObject {
    func attach(_ view: EaselStyledTextView)
    func textDidChange(in view: EaselStyledTextView)
    func handle(_ selector: Selector, in view: EaselStyledTextView) -> Bool
    func perform(_ request: EaselTextRequest, in view: EaselStyledTextView) -> Bool
    func dismiss()
    func detach()
}

extension EaselTextCompletion {
    func perform(_ request: EaselTextRequest, in view: EaselStyledTextView) -> Bool { false }
}

final class EaselStyledTextView: LocalContentDropTextView {
    var completion: EaselTextCompletion? {
        didSet { if completion !== oldValue { oldValue?.detach(); completion?.attach(self) } }
    }
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
            insertionPointColor = caretColor
        }
        needsDisplay = true; onObjectLayoutChanged?()
    }
    var paragraphBodyPointSize: CGFloat?
    nonisolated(unsafe) var fontScale = 1.0
    nonisolated func authoredFont(_ font: NSFont?) -> NSFont? { Self.authoredFont(font, scale: fontScale) }
    nonisolated static func authoredFont(_ font: NSFont?, scale: Double) -> NSFont? { font.map { resizedFont($0, by: 1 / scale) } }
    private nonisolated static func resizedFont(_ font: NSFont, by factor: Double) -> NSFont {
        guard factor.isFinite, factor > 0, abs(factor - 1) > 0.0005 else { return font }
        return CTFontCreateCopyWithAttributes(font, CGFloat((Double(font.pointSize) * factor * 1000).rounded() / 1000), nil, nil) as NSFont
    }
    private func scalingFonts(_ attributes: [NSAttributedString.Key: Any], by factor: Double) -> [NSAttributedString.Key: Any] {
        guard let font = attributes[.font] as? NSFont else { return attributes }
        var result = attributes
        result[.font] = Self.resizedFont(font, by: factor)
        return result
    }
    var objectColor = EaselInk.automatic
    var adaptsInk = false
    var caretColor: NSColor = .textColor { didSet { refreshObjectFill() } }
    var onClipboardError: ((Error) -> Void)?
    var onUndoDocument: (() -> Void)?
    var onRedoDocument: (() -> Void)?
    var canUndoDocument: (() -> Bool)?
    var canRedoDocument: (() -> Bool)?
    override var undoManager: UndoManager? { localUndo }
    var onEditBoundary: (() -> Void)?
    private var linkPanel: EaselPanelHandle?
    weak var pendingPanel: EaselPanelHandle?
    var hasPendingRangeAction: Bool { linkPanel?.isOpen == true || pendingPanel?.isOpen == true }
    private var editRevision = UUID()
    private var suppressMarkdown = false
    var onAlign: ((EaselTextStyle.Alignment) -> Void)?
    var onBlockEquation: (() -> Bool)?
    var onRepeatLastTint: (() -> Bool)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installChecklistLayout()
    }
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        installChecklistLayout()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installChecklistLayout()
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addChecklistCursorRects()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, isEditable, !hasMarkedText(), selectedRanges.count == 1, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        if handleChecklistKey(event) { return true }
        if NoteFormatShortcut.lastColor.matches(event) { return onRepeatLastTint?() ?? false }
        if NoteFormatShortcut.code.matches(event) { toggleInlineCode(); return true }
        if NoteFormatShortcut.equation.matches(event), completion?.perform(.inlineEquation, in: self) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func alignLeft(_ sender: Any?) { if let onAlign { onAlign(.left) } else { super.alignLeft(sender) } }
    override func alignCenter(_ sender: Any?) { if let onAlign { onAlign(.center) } else { super.alignCenter(sender) } }
    override func alignRight(_ sender: Any?) { if let onAlign { onAlign(.right) } else { super.alignRight(sender) } }
    override func alignJustified(_ sender: Any?) { if onAlign == nil { super.alignJustified(sender) } }

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
        window?.invalidateCursorRects(for: self)
        super.didChangeText()
        if !suppressMarkdown, !localUndo.isUndoing, !localUndo.isRedoing { completion?.textDidChange(in: self) }
    }
    override func doCommand(by selector: Selector) {
        if completion?.handle(selector, in: self) == true { return }
        super.doCommand(by: selector)
    }
    func insertCompletion(_ value: String, replacing range: NSRange, name: String) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1,
              Self.validFormattingRanges([range], length: attributedString().length) else { return }
        let suppressed = suppressMarkdown; suppressMarkdown = true
        defer { suppressMarkdown = suppressed }
        breakUndoCoalescing()
        insertText(value, replacementRange: range)
        localUndo.setActionName(name)
        breakUndoCoalescing()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { retire(); completion = nil }; super.viewWillMove(toWindow: newWindow)
    }
    func beginMention() { _ = completion?.perform(.mention(dates: false), in: self) }
    func beginDate() { _ = completion?.perform(.mention(dates: true), in: self) }
    func insertInlineEquation() { _ = completion?.perform(.inlineEquation, in: self) }
    func insertCustomEmoji(_ reference: String, replacing range: NSRange) -> Bool {
        completion?.perform(.customEmoji(reference, range), in: self) == true
    }
    @discardableResult
    func replace(_ range: NSRange, with inline: EaselRichText.Inline?, name: String) -> Bool {
        let before = attributedString()
        guard isEditable, !hasMarkedText(), Self.validFormattingRanges([range], length: before.length) else { return false }
        var typing = range.location < before.length ? before.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        if range.length == 0, range.location > 0, range.location <= before.length {
            typing = before.attributes(at: range.location - 1, effectiveRange: nil)
        }
        typing.removeValue(forKey: .attachment)
        let replacement = inline.map { EaselInlineText.character($0, attributes: typing) } ?? NSAttributedString()
        var after = typing; after.removeValue(forKey: .link)
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: before), selection: range, typing: after)
        EaselParagraphEditing.replace(&edit, range: range, with: replacement)
        edit.selection = NSRange(location: range.location + replacement.length, length: 0)
        let suppressed = suppressMarkdown; suppressMarkdown = true
        defer { suppressMarkdown = suppressed }
        commitParagraph(edit, name: name)
        return attributedString().isEqual(to: edit.text)
    }
    func previewInline(_ inline: EaselRichText.Inline, at index: Int) {
        guard let storage = textStorage, index >= 0, index < storage.length,
              storage.attribute(.attachment, at: index, effectiveRange: nil) is EaselInlineAttachment else { return }
        localUndo.disableUndoRegistration()
        storage.addAttribute(.attachment, value: EaselInlineAttachment(inline: inline), range: NSRange(location: index, length: 1))
        localUndo.enableUndoRegistration()
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        needsDisplay = true
        onObjectLayoutChanged?()
    }
    func inlineIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, (string as NSString).length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.contains(local) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return EaselInlineText.inline(at: index, in: attributedString()) == nil ? nil : index
    }
    override func mouseDown(with event: NSEvent) {
        if checklistPress(atWindowPoint: event.locationInWindow) { return }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
           let index = inlineIndex(at: convert(event.locationInWindow, from: nil)),
           completion?.perform(.activate(index), in: self) == true { return }
        super.mouseDown(with: event)
    }
    func finishComposition() {
        guard hasMarkedText() else { return }
        unmarkText(); didChangeText()
    }
    func retire() { linkPanel?.close(); linkPanel = nil; completion?.dismiss(); editRevision = UUID() }
    func resetEditingHistory() {
        let level = localUndo.groupingLevel, automatic = localUndo.groupsByEvent
        localUndo.groupsByEvent = false
        localUndo.removeAllActions()
        for _ in 0..<level { localUndo.beginUndoGrouping() }
        localUndo.groupsByEvent = automatic
        if level > 0 {
            let revision = editRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editRevision == revision, self.localUndo.groupingLevel == 0 else { return }
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
            if !plain, let styled = EaselClipboardText.attributed(from: board, typing: typingAttributes, base: objectStyle) {
                return try pastePlainText(styled.string, styled: styled)
            }
            if !plain, let payload = try EaselStyledText.read(from: board) {
                insertText(adaptsInk ? EaselInk.adapting(payload.attributed) : payload.attributed, replacementRange: selectedRange()); return true
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
    private func pastePlainText(_ text: String, styled: NSAttributedString? = nil) throws -> Bool {
        let before = attributedString(), range = selectedRange()
        guard Self.validFormattingRanges([range], length: before.length) else { return false }
        var typing = typingAttributes
        typing.removeValue(forKey: .attachment); typing.removeValue(forKey: .link)
        let input = styled ?? NSAttributedString(string: text, attributes: typing)
        var replacement = range
        if (before.string as NSString).substring(with: range).contains("\n"), NSMaxRange(range) < before.length {
            let ending = (before.string as NSString).paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let prefix = EaselParagraphEditing.markerRange(before, paragraph: ending)
            if NSMaxRange(range) <= NSMaxRange(prefix) { replacement.length = NSMaxRange(prefix) - replacement.location }
        }
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: before), selection: replacement, typing: typing)
        EaselParagraphEditing.replace(&edit, range: replacement, with: input)
        edit.selection = NSRange(location: replacement.location + input.length, length: 0)
        if text.contains("\n") || (before.string as NSString).substring(with: range).contains("\n") { EaselParagraphEditing.renumber(&edit) }
        let normalized = NSTextStorage(attributedString: edit.text)
        normalized.fixAttributes(in: NSRange(location: 0, length: normalized.length))
        edit.text = NSMutableAttributedString(attributedString: normalized)
        _ = try EaselRichTextCodec.snapshot(edit.text)
        commitParagraph(edit, name: "Paste text")
        return attributedString().isEqual(to: edit.text)
    }
    private func pasteLink(_ url: URL) throws -> Bool {
        let before = attributedString(), range = selectedRange()
        guard Self.validFormattingRanges([range], length: before.length) else { return false }
        let selected = before.attributedSubstring(from: range)
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
        var boundary = character.attributes(at: 0, effectiveRange: nil); boundary.removeValue(forKey: .attachment)
        replacement.append(NSAttributedString(string: "\n", attributes: boundary))
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: before), selection: range, typing: typing)
        EaselParagraphEditing.replace(&edit, range: range, with: replacement)
        edit.selection = NSRange(location: range.location + replacement.length, length: 0)
        EaselParagraphEditing.renumber(&edit)
        commitParagraph(edit, name: "Insert image")
        return attributedString().isEqual(to: edit.text)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound { _ = leaveDivider() }
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
              !localUndo.isUndoing, !localUndo.isRedoing else { return }
        if admission.character == "$", string == "$$", let onBlockEquation {
            var cleared = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: attributedString()),
                                                     selection: NSRange(location: 0, length: 0), typing: typingAttributes)
            EaselParagraphEditing.replace(&cleared, range: NSRange(location: 0, length: cleared.text.length), with: NSAttributedString())
            suppressMarkdown = true; defer { suppressMarkdown = false }
            commitParagraph(cleared, name: "Block equation")
            if !onBlockEquation() { localUndo.undo() }
            return
        }
        if admission.character == "-" {
            let source = string as NSString
            let line = source.lineRange(for: NSRange(location: admission.insertion.location, length: 0))
            let content = source.substring(with: line).trimmingCharacters(in: .newlines)
            if content == "---" || content == "\u{2014}-", paragraphKind() == .text,
               !EaselTextAppearance.isInlineCode(attributedString().attributes(at: line.location, effectiveRange: nil)) {
                suppressMarkdown = true; defer { suppressMarkdown = false }
                applySlashDivider(removing: NSRange(location: line.location, length: (content as NSString).length))
                return
            }
        }
        guard let edit = EaselMarkdownEditing.transform(attributedString(), admission: admission,
                  selection: selectedRange(), typing: typingAttributes, base: objectStyle) else { return }
        suppressMarkdown = true; defer { suppressMarkdown = false }
        commitParagraph(edit, name: "Format Markdown")
    }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        guard let selected = try? selectedPayload() else { return [] }
        return [EaselStyledText.pasteboardType, EaselTextAttachments.hasImages(selected.attributed) ? .rtfd : .rtf, .string,
                .html, NoteClipboard.markdownType]
    }
    override func writeSelection(to board: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        do {
            guard let selected = try selectedPayload() else { return false }
            try selected.validate()
            if type == .string { return board.setString(EaselRichText.readable(selected.text, rich: selected.richText), forType: type) }
            if type == .html || type == NoteClipboard.markdownType {
                let blocks = EaselMarkdown.blocks(text: selected.text, richText: selected.richText)
                let item = NSPasteboardItem()
                EaselClipboardText.writeFlavours(for: blocks, into: item)
                guard let value = item.string(forType: type) else { return false }
                return board.setString(value, forType: type)
            }
            let data: Data
            if type == EaselStyledText.pasteboardType { data = try JSONEncoder().encode(selected) }
            else if type == .rtfd || (type == .rtf && !EaselTextAttachments.hasImages(selected.attributed)) {
                let value = EaselInlineText.readable(selected.attributed)
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

    private func authoredAttributes(_ attributes: [NSAttributedString.Key: Any]) throws -> [NSAttributedString.Key: Any] {
        let key = NSAttributedString.Key("NSOriginalFont")
        guard let value = attributes[key] else { return attributes }
        guard let font = value as? NSFont else { throw EaselTextClipboardError.unsupportedFormatting }
        var result = attributes
        result[.font] = font; result.removeValue(forKey: key)
        return result
    }

    func format(_ name: String, ranges suppliedRanges: [NSRange]? = nil, _ authoredChange: ([NSAttributedString.Key: Any]) throws -> [NSAttributedString.Key: Any]) {
        guard isEditable, !hasMarkedText() else { return }
        let selections = selectedRanges.map(\.rangeValue)
        let ranges = suppliedRanges ?? [selectedRange()]
        guard Self.validFormattingRanges(ranges, length: attributedString().length) else { return }
        let scale = fontScale
        func change(_ attrs: [NSAttributedString.Key: Any]) throws -> [NSAttributedString.Key: Any] {
            scalingFonts(try authoredChange(scalingFonts(attrs, by: 1 / scale)), by: scale)
        }
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
    func paragraphKind(ranges suppliedRanges: [NSRange]? = nil) -> EaselParagraphEditing.Kind? {
        let value = attributedString()
        let ranges = (suppliedRanges ?? [selectedRange()]).flatMap { EaselParagraphEditing.ranges(string, selection: $0) }
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
    func commitParagraph(_ edit: EaselParagraphEditing.Edit, name: String) {
        do { _ = try EaselRichTextCodec.snapshot(edit.text) } catch { onClipboardError?(error); return }
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
        didChangeText()
    }
    func canChangeListIndent(outdent: Bool) -> Bool {
        isEditable && !hasMarkedText() && selectedRanges.count == 1 &&
            EaselParagraphEditing.canIndent(attributedString(), selection: selectedRange(), typing: typingAttributes, outdent: outdent)
    }
    func hasLink(ranges suppliedRanges: [NSRange]? = nil) -> Bool {
        let value = attributedString()
        guard let range = (suppliedRanges ?? [selectedRange()]).first, range.length > 0, NSMaxRange(range) <= value.length else { return false }
        return value.attribute(.link, at: range.location, effectiveRange: nil) != nil
    }
    func formatState(_ command: TextFormatCommand, ranges: [NSRange]? = nil) -> NSControl.StateValue {
        if let emphasis = command.emphasis { return hasEmphasis(emphasis, ranges: ranges) ? .on : .off }
        if let kind = command.paragraph { return paragraphKind(ranges: ranges) == kind ? .on : .off }
        return .off
    }
    func changeListIndent(outdent: Bool) -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else { return false }
        if let edit = EaselParagraphEditing.indent(attributedString(), selection: selectedRange(), typing: typingAttributes, outdent: outdent, base: objectStyle) {
            commitParagraph(edit, name: outdent ? "Decrease list indent" : "Increase list indent"); return true
        }
        return [.bullets, .numbers, .checklist, .quote].contains(paragraphKind())
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
        if leaveDivider() { return }
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
        if deleteAdjacentDivider(forward: false) { return }
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
        if deleteAdjacentDivider(forward: true) { return }
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
            var style = matched ?? EaselTextStyle(family: EaselTextAppearance.paletteFamily(current) ?? self.objectStyle.family, size: .body,
                                                  customSize: current.pointSize)
            mutation(&style)
            let replacement = try EaselTextAppearance.font(style, preservingEmphasisFrom: current)
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
    func applyTextColor(_ color: NSColor) {
        format("Text color") { attrs in
            var next = attrs
            next[.foregroundColor] = color
            return next
        }
    }
    func revealedSelectionRect() -> NSRect {
        let selection = selectedRange()
        scrollRangeToVisible(selection)
        guard let layout = layoutManager, let container = textContainer else { return bounds }
        let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y).intersection(visibleRect)
        return rect.isEmpty ? (visibleRect.isEmpty ? bounds : visibleRect) : rect
    }
    func removeLink(in range: NSRange) {
        guard Self.validFormattingRanges([range], length: attributedString().length), range.length > 0, !hasMarkedText() else { return }
        format("Remove link", ranges: [range]) { attrs in var next = attrs; next[.link] = nil; return next }
    }
    func editLink(relativeTo anchor: NSView, rect: NSRect? = nil, ranges suppliedRanges: [NSRange]? = nil,
                  presenter: EaselPanelPresenting?, validate: (() -> Bool)? = nil) {
        let ranges = suppliedRanges ?? [selectedRange()], originalSelections = selectedRanges
        guard Self.validFormattingRanges(ranges, length: attributedString().length), ranges.allSatisfy({ $0.length > 0 }),
              !hasMarkedText(), window != nil, let presenter else { return }
        linkPanel?.close()
        let range = ranges[0], revision = editRevision
        let value = attributedString().attribute(.link, at: range.location, effectiveRange: nil)
        let existing = (value as? URL)?.absoluteString ?? value as? String
        let request = EaselLinkRequest(link: existing, webOnly: false, host: anchor, anchor: rect ?? anchor.bounds) { [weak self] link in
            guard let self, self.editRevision == revision, self.selectedRanges == originalSelections, self.window != nil,
                  validate?() != false else { return }
            self.format(link == nil ? "Remove link" : "Edit link", ranges: ranges) { attrs in var next = attrs; next[.link] = link; return next }
            self.linkPanel = nil
        }
        linkPanel = presenter.presentLinkEditor(request)
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

extension TextFormatCommand {
    var emphasis: EaselStyledTextView.Emphasis? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .strikethrough: .strikethrough
        default: nil
        }
    }
    var paragraph: EaselParagraphEditing.Kind? {
        switch self {
        case .heading1: .heading1
        case .heading2: .heading2
        case .heading3: .heading3
        case .body: .text
        case .bulletedList: .bullets
        case .numberedList: .numbers
        default: nil
        }
    }
}

enum EaselTextStyleState {
    static func selectedStyles(in editor: EaselStyledTextView) -> [EaselTextStyle?] {
        let range = editor.selectedRange()
        if range.length == 0 { return [editor.authoredFont(editor.typingAttributes[.font] as? NSFont).flatMap(EaselTextAppearance.paletteStyle)] }
        var selected: [EaselTextStyle?] = []
        let scale = editor.fontScale
        editor.attributedString().enumerateAttribute(.font, in: range) { face, _, _ in
            selected.append(EaselStyledTextView.authoredFont(face as? NSFont, scale: scale).flatMap(EaselTextAppearance.paletteStyle))
        }
        return selected
    }
    static func canResize(by delta: Int, styles: [EaselTextStyle], editor: EaselStyledTextView?) -> Bool {
        let limit: EaselTextStyle.Size = delta < 0 ? .body : .ultra
        guard let editor else { return styles.contains { EaselTextSizing.stepped($0, by: delta) != nil } }
        return !editor.hasMarkedText() && !selectedStyles(in: editor).allSatisfy { $0?.size == limit }
    }
    static func family(of styles: [EaselTextStyle], editor: EaselStyledTextView?) -> EaselTextStyle.Family? {
        guard let editor else {
            guard let first = styles.first, styles.allSatisfy({ $0.family == first.family }) else { return nil }
            return first.family
        }
        let range = editor.selectedRange()
        var families: [EaselTextStyle.Family?] = []
        if range.length == 0 { families = [(editor.typingAttributes[.font] as? NSFont).flatMap(EaselTextAppearance.paletteFamily)] }
        else { editor.attributedString().enumerateAttribute(.font, in: range) { face, _, _ in families.append((face as? NSFont).flatMap(EaselTextAppearance.paletteFamily)) } }
        guard let first = families.first, let family = first, families.allSatisfy({ $0 == family }) else { return nil }
        return family
    }
    static func size(of styles: [EaselTextStyle], editor: EaselStyledTextView?) -> EaselTextStyle.Size? {
        guard let editor else {
            guard let first = styles.first, styles.allSatisfy({ $0.size == first.size && $0.customSize == nil }) else { return nil }
            return first.size
        }
        let selected = selectedStyles(in: editor)
        guard let first = selected.first, let style = first, selected.allSatisfy({ $0?.size == style.size }) else { return nil }
        return style.size
    }
    static func points(of styles: [EaselTextStyle], editor: EaselStyledTextView?) -> Double? {
        var sizes: [Double] = []
        if let editor {
            let range = editor.selectedRange()
            if range.length == 0 { sizes = [Double(editor.authoredFont(editor.typingAttributes[.font] as? NSFont)?.pointSize ?? 0)] }
            else {
                let scale = editor.fontScale
                editor.attributedString().enumerateAttribute(.font, in: range) { face, _, _ in
                    sizes.append(Double(EaselStyledTextView.authoredFont(face as? NSFont, scale: scale)?.pointSize ?? 0))
                }
            }
        } else { sizes = styles.map(\.pointSize) }
        guard let first = sizes.first, first > 0, sizes.allSatisfy({ abs($0 - first) < 0.01 }) else { return nil }
        return first
    }
    static func sizeTitle(of styles: [EaselTextStyle], editor: EaselStyledTextView?) -> String {
        if let size = size(of: styles, editor: editor) { return size.title }
        return points(of: styles, editor: editor).map { "\(Int($0.rounded())) pt" } ?? "Mixed"
    }
    static func isCustomSize(_ styles: [EaselTextStyle], editor: EaselStyledTextView?) -> Bool {
        size(of: styles, editor: editor) == nil && points(of: styles, editor: editor) != nil
    }
    static func fill(of styles: [EaselTextStyle]) -> NSControl.StateValue {
        guard let first = styles.first else { return .off }
        guard styles.allSatisfy({ $0.resolvedFill == first.resolvedFill }) else { return .mixed }
        return first.resolvedFill == .contentHugging ? .on : .off
    }
    static func toggledFill(_ styles: [EaselTextStyle]) -> EaselTextStyle.Fill {
        fill(of: styles) == .on ? .none : .contentHugging
    }
}
