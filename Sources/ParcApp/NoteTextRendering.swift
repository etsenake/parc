import AppKit

extension NSAttributedString.Key {
    static let noteMarks = NSAttributedString.Key("parc.note.marks")
    static let noteHighlight = NSAttributedString.Key("parc.note.highlight")
    static let noteInlineCode = NSAttributedString.Key("parc.note.inlineCode")
}

final class NoteMarksValue: NSObject {
    let marks: NoteMarks

    init(_ marks: NoteMarks) { self.marks = marks }

    override func isEqual(_ object: Any?) -> Bool { (object as? NoteMarksValue)?.marks == marks }

    override var hash: Int { marks.hashValue }
}

struct NoteTextPresentation: Hashable {
    var role: NoteTextRole = .body
    var pageFont: NotePageFont = .standard
    var small = false
    var color: NoteColorStyle?
    var completed = false

    init(role: NoteTextRole = .body, pageFont: NotePageFont = .standard, small: Bool = false,
         color: NoteColorStyle? = nil, completed: Bool = false) {
        self.role = role
        self.pageFont = pageFont
        self.small = small
        self.color = color
        self.completed = completed
    }

    init(block: NoteBlock, settings: NotePageSettings) {
        self.init(role: Self.role(for: block), pageFont: settings.font, small: settings.smallText,
                  color: block.color, completed: block.kind == .todo && block.props.checked)
    }

    static func role(for block: NoteBlock) -> NoteTextRole {
        switch block.kind {
        case .heading: return .heading(min(max(block.props.level, 1), 6))
        case .quote: return .quote
        case .callout: return .callout
        default: return .body
        }
    }
}

struct NoteTextMetrics {
    var font: NSFont
    var ink: NSColor
    var lineHeight: CGFloat
    var baselineOffset: CGFloat
    var kern: CGFloat
}

@MainActor
enum NoteTextRendering {
    private struct FontKey: Hashable {
        var role: NoteTextRole
        var pageFont: NotePageFont
        var small: Bool
        var bold: Bool
        var italic: Bool
        var code: Bool
    }

    private struct StyleKey: Hashable {
        var lineHeight: CGFloat
        var flexible: Bool
    }

    private static var metricsCache: [NoteTextPresentation: NoteTextMetrics] = [:]
    private static var fontCache: [FontKey: NSFont] = [:]
    private static var paragraphCache: [StyleKey: NSParagraphStyle] = [:]

    static func metrics(_ presentation: NoteTextPresentation) -> NoteTextMetrics {
        if let cached = metricsCache[presentation] { return cached }
        let style = NoteTheme.textStyle(presentation.role, font: presentation.pageFont, small: presentation.small)
        let natural = ceil(style.font.ascender - style.font.descender + style.font.leading)
        let lineHeight = max(style.lineHeight, natural)
        var ink = style.ink
        if presentation.completed { ink = NoteTheme.todoDoneInk }
        else if let color = presentation.color, !color.isBackground { ink = NoteTheme.color(color) }
        let metrics = NoteTextMetrics(font: style.font, ink: ink, lineHeight: lineHeight,
                                      baselineOffset: max(0, ((lineHeight - natural) / 2).rounded(.down)), kern: style.kern)
        metricsCache[presentation] = metrics
        return metrics
    }

    static func lineHeight(_ presentation: NoteTextPresentation) -> CGFloat { metrics(presentation).lineHeight }

    static func paragraphStyle(lineHeight: CGFloat, flexible: Bool) -> NSParagraphStyle {
        let key = StyleKey(lineHeight: lineHeight, flexible: flexible)
        if let cached = paragraphCache[key] { return cached }
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = flexible ? 0 : lineHeight
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        paragraphCache[key] = style
        return style
    }

    static func needsFlexibleLines(_ text: NoteText) -> Bool {
        text.spans.contains { span in
            if case .equation = span.marks.atom { return true }
            return false
        }
    }

    static func font(for marks: NoteMarks, _ presentation: NoteTextPresentation) -> NSFont {
        let key = FontKey(role: presentation.role, pageFont: presentation.pageFont, small: presentation.small,
                          bold: marks.bold, italic: marks.italic, code: marks.code)
        if let cached = fontCache[key] { return cached }
        let base = metrics(presentation).font
        var font: NSFont
        if marks.code {
            let size = NoteTheme.inlineCodeFont(relativeTo: base).pointSize
            font = marks.bold ? NoteTheme.boldCodeFont(size: size) : NoteTheme.codeFont(size: size)
            if marks.italic { font = oblique(font) }
        } else if case .heading = presentation.role {
            font = marks.italic ? italic(base) : base
        } else if marks.bold || marks.italic {
            font = base
            if marks.bold {
                let variant = NoteTheme.bodyFont(presentation.pageFont, small: presentation.small, bold: true)
                font = abs(variant.pointSize - base.pointSize) < 0.01 ? variant : resized(variant, to: base.pointSize)
                if !font.fontDescriptor.symbolicTraits.contains(.bold) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
            }
            if marks.italic { font = italic(font) }
        } else {
            font = base
        }
        fontCache[key] = font
        return font
    }

    private static func resized(_ font: NSFont, to size: CGFloat) -> NSFont {
        NSFont(descriptor: font.fontDescriptor, size: size) ?? font
    }

    private static func italic(_ font: NSFont) -> NSFont {
        let converted = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        if converted.fontDescriptor.symbolicTraits.contains(.italic) { return converted }
        return oblique(font)
    }

    private static func oblique(_ font: NSFont) -> NSFont {
        var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        return CTFontCreateCopyWithAttributes(font as CTFont, font.pointSize, &skew, nil) as NSFont
    }

    static func ink(for marks: NoteMarks, _ presentation: NoteTextPresentation) -> NSColor {
        let base = metrics(presentation).ink
        if presentation.completed { return base }
        if let color = marks.color, !color.isBackground { return NoteTheme.color(color) }
        if marks.code { return NoteTheme.inlineCodeInk }
        if marks.link != nil { return NoteTheme.link }
        return base
    }

    static func attributes(for marks: NoteMarks, _ presentation: NoteTextPresentation,
                           flexible: Bool = false) -> [NSAttributedString.Key: Any] {
        let metrics = self.metrics(presentation)
        let ink = self.ink(for: marks, presentation)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: marks, presentation),
            .foregroundColor: ink,
            .paragraphStyle: paragraphStyle(lineHeight: metrics.lineHeight, flexible: flexible),
            .baselineOffset: metrics.baselineOffset,
            .noteMarks: NoteMarksValue(marks),
        ]
        if metrics.kern != 0, !marks.code { attributes[.kern] = metrics.kern }
        if marks.link != nil {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = presentation.completed ? ink : NoteTheme.linkUnderline
        } else if marks.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = ink
        }
        if marks.strikethrough || presentation.completed {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = ink
        }
        if marks.code { attributes[.noteInlineCode] = true }
        if let color = marks.color, color.isBackground, !presentation.completed {
            attributes[.noteHighlight] = NoteTheme.color(color)
        }
        return attributes
    }

    static func typingAttributes(_ marks: NoteMarks, _ presentation: NoteTextPresentation,
                                 flexible: Bool = false) -> [NSAttributedString.Key: Any] {
        attributes(for: marks.withoutAtom, presentation, flexible: flexible)
    }

    static func attributedString(_ text: NoteText, _ presentation: NoteTextPresentation,
                                 now: Date = Date()) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let flexible = needsFlexibleLines(text)
        let characters = text.string as NSString
        for run in text.runs() {
            var attributes = self.attributes(for: run.marks, presentation, flexible: flexible)
            let segment = characters.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            if run.marks.atom != nil || segment.utf16.contains(0xFFFC) {
                for unit in segment.utf16 {
                    var local = attributes
                    if unit == 0xFFFC {
                        local[.attachment] = NoteAtomRendering.attachment(for: run.marks.atom, font: font(for: run.marks, presentation),
                                                                          ink: ink(for: run.marks, presentation), now: now)
                    }
                    result.append(NSAttributedString(string: String(utf16CodeUnits: [unit], count: 1), attributes: local))
                }
                attributes.removeValue(forKey: .attachment)
            } else {
                result.append(NSAttributedString(string: segment, attributes: attributes))
            }
        }
        return result
    }

    static func noteText(from attributed: NSAttributedString) -> NoteText {
        var result = NoteText()
        let characters = attributed.string as NSString
        attributed.enumerateAttribute(.noteMarks, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let marks = (value as? NoteMarksValue)?.marks ?? .plain
            let segment = characters.substring(with: range)
            guard let atom = marks.atom else {
                result.append(NoteText(segment, marks: marks))
                return
            }
            let plain = marks.withoutAtom
            var pending = ""
            for unit in segment.utf16 {
                if unit == 0xFFFC {
                    if !pending.isEmpty { result.append(NoteText(pending, marks: plain)); pending = "" }
                    result.append(NoteText.atom(atom, marks: plain))
                } else {
                    pending += String(utf16CodeUnits: [unit], count: 1)
                }
            }
            if !pending.isEmpty { result.append(NoteText(pending, marks: plain)) }
        }
        return result
    }

    static func placeholder(_ text: String, _ presentation: NoteTextPresentation) -> NSAttributedString {
        let metrics = self.metrics(presentation)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: metrics.font,
            .foregroundColor: NoteTheme.placeholderInk,
            .paragraphStyle: paragraphStyle(lineHeight: metrics.lineHeight, flexible: false),
            .baselineOffset: metrics.baselineOffset,
        ]
        if metrics.kern != 0 { attributes[.kern] = metrics.kern }
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func height(of text: NoteText, _ presentation: NoteTextPresentation, width: CGFloat) -> CGFloat {
        let lineHeight = metrics(presentation).lineHeight
        guard !text.isEmpty else { return lineHeight }
        return NoteTextMeasurer.shared.height(of: attributedString(text, presentation), width: width, emptyHeight: lineHeight)
    }

    static func height(of attributed: NSAttributedString, width: CGFloat, emptyHeight: CGFloat) -> CGFloat {
        guard attributed.length > 0 else { return emptyHeight }
        return NoteTextMeasurer.shared.height(of: attributed, width: width, emptyHeight: emptyHeight)
    }
}

@MainActor
final class NoteTextMeasurer {
    static let shared = NoteTextMeasurer()
    private let storage = NSTextStorage()
    private let layoutManager = NoteLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))

    private init() {
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    func height(of attributed: NSAttributedString, width: CGFloat, emptyHeight: CGFloat) -> CGFloat {
        guard attributed.length > 0 else { return emptyHeight }
        container.size = NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        storage.setAttributedString(attributed)
        layoutManager.ensureLayout(for: container)
        let height = ceil(layoutManager.usedRect(for: container).height)
        storage.setAttributedString(NSAttributedString())
        return max(emptyHeight, height)
    }
}

final class NoteLayoutManager: NSLayoutManager {
    var crossBlockHighlight: Range<Int>?
    var crossBlockColor: NSColor = .selectedTextBackgroundColor
    var inlineCodeFill: NSColor = .quaternaryLabelColor

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first, storage.length > 0 {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(.noteHighlight, in: characters) { value, range, _ in
                guard let color = value as? NSColor else { return }
                fillRuns(range, storage: storage, container: container, origin: origin, color: color,
                         horizontal: 1, vertical: 1, radius: 3)
            }
            storage.enumerateAttribute(.noteInlineCode, in: characters) { value, range, _ in
                guard (value as? Bool) == true else { return }
                fillRuns(range, storage: storage, container: container, origin: origin, color: inlineCodeFill,
                         horizontal: 3, vertical: 1.5, radius: 4)
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawCrossBlockHighlight(at: origin)
    }

    override func drawUnderline(forGlyphRange glyphRange: NSRange, underlineType: NSUnderlineStyle, baselineOffset: CGFloat,
                                lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange,
                                containerOrigin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first, glyphRange.length > 0 else {
            super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineType, baselineOffset: baselineOffset,
                                lineFragmentRect: lineRect, lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
            return
        }
        var range = glyphRange
        while range.length > 0, isTrailingBreak(glyphAt: NSMaxRange(range) - 1, storage: storage) { range.length -= 1 }
        guard range.length > 0 else { return }
        let index = characterIndexForGlyph(at: range.location)
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let color = temporaryAttribute(.underlineColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor
            ?? storage.attribute(.underlineColor, at: index, effectiveRange: nil) as? NSColor
            ?? storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor ?? .textColor
        let bounds = boundingRect(forGlyphRange: range, in: container)
        let baseline = lineRect.minY + location(forGlyphAt: range.location).y
        let scale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2
        let thickness = max(1, (font.pointSize / 16 * scale).rounded() / scale)
        let offset = max(2, (-font.descender * 0.42 * scale).rounded() / scale)
        color.setFill()
        NSRect(x: bounds.minX + containerOrigin.x, y: baseline + offset + containerOrigin.y, width: bounds.width, height: thickness).fill()
    }

    private func fillRuns(_ characters: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: NSPoint,
                          color: NSColor, horizontal: CGFloat, vertical: CGFloat, radius: CGFloat) {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        color.setFill()
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, lineGlyphs, _ in
            var part = NSIntersectionRange(glyphs, lineGlyphs)
            while part.length > 0, self.isTrailingBreak(glyphAt: NSMaxRange(part) - 1, storage: storage) { part.length -= 1 }
            guard part.length > 0 else { return }
            let bounds = self.boundingRect(forGlyphRange: part, in: container)
            let index = self.characterIndexForGlyph(at: part.location)
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 14)
            let baseline = rect.minY + self.location(forGlyphAt: part.location).y
            let top = baseline - font.ascender - vertical
            let bottom = baseline - font.descender + vertical
            let pill = NSRect(x: bounds.minX - horizontal + origin.x, y: top + origin.y,
                              width: bounds.width + horizontal * 2, height: bottom - top)
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func isTrailingBreak(glyphAt glyph: Int, storage: NSTextStorage) -> Bool {
        let index = characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return true }
        let unit = (storage.string as NSString).character(at: index)
        return unit == 10 || unit == 13 || unit == 0x2028
    }

    private func drawCrossBlockHighlight(at origin: NSPoint) {
        guard let range = crossBlockHighlight, let storage = textStorage, let container = textContainers.first else { return }
        crossBlockColor.setFill()
        let length = storage.length
        let lower = min(max(0, range.lowerBound), length), upper = min(max(lower, range.upperBound), length)
        if lower < upper {
            let glyphs = glyphRange(forCharacterRange: NSRange(location: lower, length: upper - lower), actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, _ in
                rect.offsetBy(dx: origin.x, dy: origin.y).fill()
            }
        }
        guard upper == length else { return }
        let extra = extraLineFragmentRect
        let tail: NSRect
        if length == 0 || extra.height > 0 {
            tail = NSRect(x: extra.minX, y: extra.minY, width: max(extra.width, container.size.width - extra.minX), height: extra.height)
        } else {
            let glyph = glyphIndexForCharacter(at: length - 1)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            tail = NSRect(x: used.maxX, y: line.minY, width: max(0, line.maxX - used.maxX), height: line.height)
        }
        tail.offsetBy(dx: origin.x, dy: origin.y).fill()
    }
}

enum NoteListMarker {
    static let bullets = ["•", "◦", "▪"]

    static func bullet(level: Int) -> String { bullets[max(0, level) % bullets.count] }

    static func level(of id: NoteBlockID, kind: NoteBlockKind, in page: NotePage) -> Int {
        guard let path = page.path(of: id), path.count > 1 else { return 0 }
        var count = 0
        var list = page.blocks
        for index in path.dropLast() {
            guard list.indices.contains(index) else { break }
            let ancestor = list[index]
            if ancestor.kind == kind { count += 1 }
            list = ancestor.children
        }
        return count
    }

    static func number(of id: NoteBlockID, in page: NotePage) -> Int? {
        let siblings = page.siblings(of: id)
        guard let index = siblings.firstIndex(where: { $0.id == id }), siblings[index].kind == .numberedItem else { return nil }
        var start = index
        while start > 0, siblings[start - 1].kind == .numberedItem { start -= 1 }
        return (siblings[start].props.listStart ?? 1) + (index - start)
    }

    static func numberLabel(_ value: Int, level: Int, delimiter: String? = nil) -> String {
        let mark = delimiter == ")" ? ")" : "."
        switch level % 3 {
        case 1: return (letters(value) ?? String(value)) + mark
        case 2: return (roman(value) ?? String(value)) + mark
        default: return String(value) + mark
        }
    }

    static func label(for block: NoteBlock, in page: NotePage) -> String? {
        switch block.kind {
        case .bulletedItem:
            return bullet(level: level(of: block.id, kind: .bulletedItem, in: page))
        case .numberedItem:
            guard let value = number(of: block.id, in: page) else { return nil }
            let siblings = page.siblings(of: block.id)
            var first = siblings.firstIndex { $0.id == block.id } ?? 0
            while first > 0, siblings[first - 1].kind == .numberedItem { first -= 1 }
            return numberLabel(value, level: level(of: block.id, kind: .numberedItem, in: page),
                               delimiter: siblings.indices.contains(first) ? siblings[first].props.orderedDelimiter : nil)
        default:
            return nil
        }
    }

    static func letters(_ value: Int) -> String? {
        guard value > 0 else { return nil }
        var remaining = value
        var result = ""
        while remaining > 0 {
            remaining -= 1
            result = String(UnicodeScalar(UInt8(97 + remaining % 26))) + result
            remaining /= 26
        }
        return result
    }

    static func roman(_ value: Int) -> String? {
        guard value > 0, value < 4000 else { return nil }
        let table: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                                      (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var remaining = value
        var result = ""
        for (amount, symbol) in table {
            while remaining >= amount { result += symbol; remaining -= amount }
        }
        return result
    }
}
