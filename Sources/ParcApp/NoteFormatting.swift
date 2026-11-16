import AppKit
import CoreText
import UniformTypeIdentifiers

@MainActor
final class NoteFormattingTarget {
    let bodyID: UUID
    private(set) var revision: UInt64
    let range: NSRange
    let contents: NSAttributedString

    init?(text: NSTextView, document: NoteDocument, range: NSRange) {
        guard !document.deleted, text.isEditable, !text.hasMarkedText(),
              range.location != NSNotFound, range.location <= text.attributedString().length,
              range.length <= text.attributedString().length - range.location else { return nil }
        bodyID = document.body.id; revision = document.revision; self.range = range
        contents = NSAttributedString(attributedString: text.attributedString())
    }
    func matches(text: NSTextView, document: NoteDocument) -> Bool {
        !document.deleted && document.body.id == bodyID && document.revision == revision &&
        text.isEditable && !text.hasMarkedText() && contents.isEqual(to: text.attributedString())
    }
    func localBodyPublished(text: NSTextView, previous: NoteDocument, current: NoteDocument) {
        guard matches(text: text, document: previous), !current.deleted,
              current.body.id == bodyID, current.body.text == contents.string,
              let richText = try? EaselRichTextCodec.snapshot(contents),
              richText == current.body.richText else { return }
        revision = current.revision
    }
}

@MainActor
enum NoteParagraphGeometry {
    struct Target {
        let range: NSRange
        let iconRange: NSRange
        let firstLine: NSRect
        let bounds: NSRect
        let windowAnchor: NSPoint?
        let sourceIndex: Int
        let sourceRange: NSRange
        let afterNewline: Bool
    }

    static func target(in text: NSTextView, at point: NSPoint) -> Target? {
        guard let container = text.textContainer, let layout = text.layoutManager else { return nil }
        layout.ensureLayout(for: container)
        let origin = text.textContainerOrigin
        let p = NSPoint(x: max(0, point.x - origin.x), y: point.y - origin.y)
        let extent = layout.usedRect(for: container).union(layout.extraLineFragmentRect)
        guard p.y >= extent.minY, p.y <= extent.maxY else { return nil }
        let index = min(layout.characterIndex(for: p, in: container, fractionOfDistanceBetweenInsertionPoints: nil), text.string.utf16.count)
        guard let target = resolveHit(in: text, index: index, windowPoint: text.convert(point, to: nil)) else { return nil }
        if target.afterNewline { return target }
        if let end = Self.target(in: text, containing: text.string.utf16.count), end.range.length == 0,
           point.y >= end.bounds.minY, point.y <= end.bounds.maxY { return end }
        guard point.y >= target.bounds.minY, point.y <= target.bounds.maxY else { return nil }
        return target
    }

    static func resolveHit(in text: NSTextView, index: Int, windowPoint: NSPoint) -> Target? {
        guard let target = make(in: text, index: index, afterNewline: false) else { return nil }
        if let window = text.window, isNewline(in: text.string, at: index), let anchor = target.windowAnchor {
            let rect = window.convertFromScreen(text.firstRect(forCharacterRange: target.sourceRange, actualRange: nil))
            if windowPoint.y <= anchor.y - rect.height / 2 { return make(in: text, index: index, afterNewline: true) }
        }
        return target
    }

    static func target(in text: NSTextView, containing index: Int) -> Target? {
        make(in: text, index: index, afterNewline: false)
    }

    static func refresh(_ target: Target, in text: NSTextView) -> Target? {
        guard let next = make(in: text, index: target.sourceIndex, afterNewline: target.afterNewline),
              next.range == target.range, next.sourceRange == target.sourceRange else { return nil }
        return next
    }

    static func isNewline(in string: String, at index: Int) -> Bool {
        guard index >= 0, index < string.utf16.count,
              let range = Range(NSRange(location: index, length: 1), in: string),
              let scalar = string[range].unicodeScalars.first else { return false }
        return (10...13).contains(scalar.value) || scalar.value == 0x85 ||
            scalar.value == 0x2028 || scalar.value == 0x2029
    }

    private static func make(in text: NSTextView, index: Int, afterNewline: Bool) -> Target? {
        guard let container = text.textContainer, let layout = text.layoutManager,
              index >= 0, index <= text.string.utf16.count else { return nil }
        layout.ensureLayout(for: container)
        let string = text.string as NSString
        var start = 0, contentsEnd = 0
        string.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        var image = false
        text.attributedString().enumerateAttribute(.attachment, in: range) { value, _, stop in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? NSTextAttachmentCell, cell.image != nil {
                image = true; stop.pointee = true
            }
        }
        guard !image, !afterNewline || isNewline(in: text.string, at: index) else { return nil }
        let origin = text.textContainerOrigin
        var first: NSRect, all: NSRect
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        if start == string.length {
            first = layout.extraLineFragmentRect
            if first.height <= 0 {
                let height = layout.defaultLineHeight(for: (text.typingAttributes[.font] as? NSFont) ?? NoteDocumentAppearance.bodyFont)
                first = NSRect(x: 0, y: layout.usedRect(for: container).maxY, width: container.size.width, height: height)
            }
            all = first
        } else {
            let glyph = layout.glyphIndexForCharacter(at: start)
            guard glyph < layout.numberOfGlyphs else { return nil }
            first = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            all = glyphs.length == 0 ? first : layout.boundingRect(forGlyphRange: glyphs, in: container).union(first)
        }
        var anchor: NSPoint?
        if let window = text.window {
            let rect = window.convertFromScreen(text.firstRect(forCharacterRange: range, actualRange: nil))
            let fontOffset = start < string.length
                ? ((text.attributedString().attribute(.font, at: start, effectiveRange: nil) as? NSFont)?.pointSize ?? 18) / 2 - 9 : 0
            var y = rect.minY + fontOffset
            if afterNewline {
                var height: CGFloat = 0
                layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, _ in
                    if rect.height > 0 { height += rect.height }
                }
                y = y - height + 2 * fontOffset - 8
            }
            anchor = NSPoint(x: rect.minX, y: y)
        }
        return Target(range: afterNewline ? NSRange(location: index + 1, length: 0) : range,
                      iconRange: afterNewline ? NSRange(location: contentsEnd, length: 0) : range,
                      firstLine: first.offsetBy(dx: origin.x, dy: origin.y), bounds: all.offsetBy(dx: origin.x, dy: origin.y),
                      windowAnchor: anchor, sourceIndex: index, sourceRange: range, afterNewline: afterNewline)
    }
}

enum NoteFormatAction: Int, CaseIterable {
    case heading1, heading2, heading3, text, bullets, numbers
    case bold, italic, underline, strikethrough, image, link
    var title: String {
        ["Heading 1", "Heading 2", "Heading 3", "Text", "Bulleted List", "Numbered List",
         "Bold", "Italic", "Underline", "Strikethrough", "Insert Image", "Link"][rawValue]
    }
    var icon: String {
        ["H1", "H2", "H3", "T", "•", "1.", "B", "I", "U", "S", "+", "↗"][rawValue]
    }
    var paragraph: EaselParagraphEditing.Kind? {
        switch self {
        case .heading1: return .heading1
        case .heading2: return .heading2
        case .heading3: return .heading3
        case .text: return .text
        case .bullets: return .bullets
        case .numbers: return .numbers
        default: return nil
        }
    }
    var emphasis: EaselStyledTextView.Emphasis? {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        default: return nil
        }
    }
}

@MainActor
enum NoteGutterIcon: Equatable {
    case text, heading1, heading2, heading3, bullets, numbers, plus

    var paragraphKind: EaselParagraphEditing.Kind {
        switch self {
        case .text, .plus: .text
        case .heading1: .heading1
        case .heading2: .heading2
        case .heading3: .heading3
        case .bullets: .bullets
        case .numbers: .numbers
        }
    }
    static func resolve(in text: NSTextView, range: NSRange) -> Self {
        let contents = text.attributedString()
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= contents.length, range.length <= contents.length - range.location,
              let nativeRange = Range(range, in: contents.string) else { return .text }
        let value = String(contents.string[nativeRange])
        let prefix = Array(value.prefix(5))
        if prefix.count >= 3, prefix[0] == "\t", prefix[2] == "\t",
           prefix[1] == "●" || prefix[1] == "✺" { return .bullets }
        if prefix.first == "\t", let end = prefix.dropFirst().firstIndex(of: "\t"),
           Int(String(prefix[1..<end]), radix: 10) != nil { return .numbers }

        if range.length > 0 {
            let marker = EaselParagraphEditing.markerRange(contents, paragraph: range)
            if marker.location == range.location, marker.length > 0 {
                let kind = EaselParagraphEditing.kind(contents.attributes(at: range.location, effectiveRange: nil))
                if kind == .bullets { return .bullets }
                if kind == .numbers { return .numbers }
            }
        }
        var firstFont: NSFont?
        contents.enumerateAttribute(.font, in: range) { value, _, stop in
            if let font = value as? NSFont { firstFont = font; stop.pointee = true }
        }
        if let heading = heading(firstFont ?? NoteDocumentAppearance.bodyFont) { return heading }
        guard value.components(separatedBy: .newlines).joined().isEmpty else { return .text }
        let selection = text.selectedRange()
        if selection.length == 0, selection.location == range.location,
           let font = text.typingAttributes[.font] as? NSFont, let heading = heading(font) { return heading }
        return .plus
    }
    private static func heading(_ font: NSFont) -> Self? {
        switch font.pointSize { case 32: .heading1; case 26: .heading2; case 22: .heading3; default: nil }
    }
}

@MainActor
enum NoteListGlyph {
    static func image(numbered: Bool) -> NSImage {
        NSImage(size: NSSize(width: 14.4, height: 14.4), flipped: true) { _ in
            let transform = AffineTransform(scale: 14.4 / 20)
            (transform as NSAffineTransform).concat()
            NSColor.black.set()
            let lines = NSBezierPath()
            lines.lineWidth = 1.7; lines.lineCapStyle = .round; lines.lineJoinStyle = .round
            for y in [5.0, 10.0, 15.0] {
                lines.move(to: NSPoint(x: 6.66663, y: y)); lines.line(to: NSPoint(x: 17.5, y: y))
            }
            lines.stroke()
            if numbered { numbers().fill() }
            else {
                for y in [4.16675, 9.16675, 14.1667] {
                    NSBezierPath(roundedRect: NSRect(x: 1.66663, y: y, width: 1.7, height: 1.7), xRadius: 0.85, yRadius: 0.85).fill()
                }
            }
            return true
        }
    }
    private static func numbers() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 2.44531, y: 6.5))
        path.line(to: NSPoint(x: 3.27344, y: 6.5))
        path.line(to: NSPoint(x: 3.27344, y: 3.68164))
        path.line(to: NSPoint(x: 2.44531, y: 3.68164))
        path.line(to: NSPoint(x: 1.73828, y: 4.1543))
        path.line(to: NSPoint(x: 1.73828, y: 4.84766))
        path.line(to: NSPoint(x: 2.40625, y: 4.40625))
        path.line(to: NSPoint(x: 2.44531, y: 4.40625))
        path.line(to: NSPoint(x: 2.44531, y: 6.5))
        path.close()
        path.move(to: NSPoint(x: 1.70703, y: 9.59766))
        path.line(to: NSPoint(x: 2.46094, y: 9.59766))
        path.curve(to: NSPoint(x: 2.83203, y: 9.2168), controlPoint1: NSPoint(x: 2.46094, y: 9.38086), controlPoint2: NSPoint(x: 2.5957, y: 9.2168))
        path.curve(to: NSPoint(x: 3.16797, y: 9.52148), controlPoint1: NSPoint(x: 3.05273, y: 9.2168), controlPoint2: NSPoint(x: 3.16797, y: 9.35938))
        path.curve(to: NSPoint(x: 2.7793, y: 10.0723), controlPoint1: NSPoint(x: 3.16797, y: 9.66406), controlPoint2: NSPoint(x: 3.125, y: 9.77734))
        path.line(to: NSPoint(x: 1.75586, y: 10.9492))
        path.line(to: NSPoint(x: 1.75586, y: 11.5))
        path.line(to: NSPoint(x: 3.99609, y: 11.5))
        path.line(to: NSPoint(x: 3.99609, y: 10.8672))
        path.line(to: NSPoint(x: 2.85742, y: 10.8672))
        path.line(to: NSPoint(x: 2.85742, y: 10.8281))
        path.line(to: NSPoint(x: 3.38672, y: 10.375))
        path.curve(to: NSPoint(x: 3.9668, y: 9.45312), controlPoint1: NSPoint(x: 3.81836, y: 10.0059), controlPoint2: NSPoint(x: 3.9668, y: 9.78906))
        path.curve(to: NSPoint(x: 2.87305, y: 8.60352), controlPoint1: NSPoint(x: 3.9668, y: 8.96094), controlPoint2: NSPoint(x: 3.57617, y: 8.60352))
        path.curve(to: NSPoint(x: 1.70703, y: 9.59766), controlPoint1: NSPoint(x: 2.17773, y: 8.60352), controlPoint2: NSPoint(x: 1.70703, y: 9.00195))
        path.close()
        path.move(to: NSPoint(x: 2.52148, y: 15.3281))
        path.line(to: NSPoint(x: 2.88672, y: 15.3281))
        path.curve(to: NSPoint(x: 3.26953, y: 15.6328), controlPoint1: NSPoint(x: 3.125, y: 15.3281), controlPoint2: NSPoint(x: 3.26953, y: 15.4414))
        path.curve(to: NSPoint(x: 2.88867, y: 15.9355), controlPoint1: NSPoint(x: 3.26953, y: 15.8145), controlPoint2: NSPoint(x: 3.11719, y: 15.9355))
        path.curve(to: NSPoint(x: 2.49219, y: 15.625), controlPoint1: NSPoint(x: 2.64648, y: 15.9355), controlPoint2: NSPoint(x: 2.49609, y: 15.8164))
        path.line(to: NSPoint(x: 1.70312, y: 15.625))
        path.curve(to: NSPoint(x: 2.90234, y: 16.5781), controlPoint1: NSPoint(x: 1.72852, y: 16.2031), controlPoint2: NSPoint(x: 2.20117, y: 16.5781))
        path.curve(to: NSPoint(x: 4.11133, y: 15.7207), controlPoint1: NSPoint(x: 3.61523, y: 16.5781), controlPoint2: NSPoint(x: 4.11133, y: 16.2324))
        path.curve(to: NSPoint(x: 3.45898, y: 15.0469), controlPoint1: NSPoint(x: 4.11133, y: 15.3555), controlPoint2: NSPoint(x: 3.87891, y: 15.1035))
        path.line(to: NSPoint(x: 3.45898, y: 15.0078))
        path.curve(to: NSPoint(x: 3.99609, y: 14.373), controlPoint1: NSPoint(x: 3.77539, y: 14.9375), controlPoint2: NSPoint(x: 3.99609, y: 14.7148))
        path.curve(to: NSPoint(x: 2.92969, y: 13.6035), controlPoint1: NSPoint(x: 3.99609, y: 13.9453), controlPoint2: NSPoint(x: 3.62109, y: 13.6035))
        path.curve(to: NSPoint(x: 1.77539, y: 14.5332), controlPoint1: NSPoint(x: 2.23047, y: 13.6035), controlPoint2: NSPoint(x: 1.7793, y: 13.9648))
        path.line(to: NSPoint(x: 2.52344, y: 14.5332))
        path.curve(to: NSPoint(x: 2.89258, y: 14.209), controlPoint1: NSPoint(x: 2.53125, y: 14.332), controlPoint2: NSPoint(x: 2.66406, y: 14.209))
        path.curve(to: NSPoint(x: 3.23438, y: 14.4941), controlPoint1: NSPoint(x: 3.10547, y: 14.209), controlPoint2: NSPoint(x: 3.23438, y: 14.3262))
        path.curve(to: NSPoint(x: 2.89062, y: 14.7891), controlPoint1: NSPoint(x: 3.23438, y: 14.6699), controlPoint2: NSPoint(x: 3.10352, y: 14.7891))
        path.line(to: NSPoint(x: 2.52148, y: 14.7891))
        path.line(to: NSPoint(x: 2.52148, y: 15.3281))
        path.close()
        return path
    }
}

@MainActor
enum NoteFormattingAppearance {
    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("Parc.Note.Format." + name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
    static let text = adaptive("FormatMenuText",
        light: NSColor(srgbRed: 0.431, green: 0.404, blue: 0.553, alpha: 1),
        dark: NSColor(srgbRed: 0.529, green: 0.584, blue: 0.757, alpha: 1))
    static let selectedInk = adaptive("SelectedMenuItem",
        light: NSColor(srgbRed: 0.153, green: 0.008, blue: 0.761, alpha: 1),
        dark: NSColor(srgbRed: 0.714, green: 0.788, blue: 0.980, alpha: 1))
    static let hover = adaptive("HoveredMenuItemBackground",
        light: NSColor(srgbRed: 0.922, green: 0.922, blue: 0.925, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.15))
    static let selected = adaptive("SelectedMenuItemBackground",
        light: NSColor(srgbRed: 0.153, green: 0.008, blue: 0.761, alpha: 0.1),
        dark: NSColor(srgbRed: 0.024, green: 0.180, blue: 0.475, alpha: 1))
    static let gutterSelected = adaptive("GutterMenuItemSelected",
        light: NSColor(srgbRed: 0.851, green: 0.851, blue: 0.878, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.3))
    static let background = adaptive("FormatMenuBackground", light: .white,
        dark: NSColor(srgbRed: 0.071, green: 0.059, blue: 0.180, alpha: 1))
    static let border = adaptive("FormatMenuBorder",
        light: NSColor(srgbRed: 0.804, green: 0.800, blue: 0.875, alpha: 1),
        dark: NSColor(srgbRed: 0.204, green: 0.200, blue: 0.302, alpha: 1))

    static func ink(for item: NoteFormatMenu.Item, checked: Bool) -> NSColor {
        switch item {
        case .action(.text), .action(.heading1), .action(.heading2), .action(.heading3): text
        default: checked ? selectedInk : text
        }
    }

    static func gutterFill(selected: Bool, hovered: Bool) -> NSColor? {
        if selected { return gutterSelected }
        if hovered { return hover }
        return nil
    }

    static func itemFill(checked: Bool, hovered: Bool) -> NSColor? {
        if checked { return selected }
        if hovered { return hover }
        return nil
    }
}

@MainActor
enum NoteFormatGlyph {
    static let size: CGFloat = 14.4
    static let iconCacheSize: CGFloat = 20
    static let insertImageCode: UInt32 = 0xE981
    static let formattedHyperlinkCode: UInt32 = 0xE998

    static let iconFontDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker", isDirectory: true)
    private static var iconDescriptor: CTFontDescriptor?
    private static var featherCache: [UInt32: NSImage] = [:]

    static func font(for action: NoteFormatAction) -> NSFont {
        _ = NoteDocumentAppearance.bodyFont
        let named: String
        switch action {
        case .heading1, .heading2, .heading3, .bold: named = "Nunito-Bold"
        case .italic: named = "Nunito-Italic"
        default: named = "Nunito-Regular"
        }
        if let font = NSFont(name: named, size: size) { return font }
        var fallback = NoteDocumentAppearance.bodyFont
        if named == "Nunito-Bold" {
            fallback = NSFontManager.shared.convert(fallback, toHaveTrait: .boldFontMask)
        } else if named == "Nunito-Italic" {
            fallback = NSFontManager.shared.convert(fallback, toHaveTrait: .italicFontMask)
        }
        return NSFontManager.shared.convert(fallback, toSize: size)
    }
    static func letter(for action: NoteFormatAction) -> String? {
        switch action {
        case .heading1: NSLocalizedString("H1", comment: "Short text for 'Heading 1'")
        case .heading2: NSLocalizedString("H2", comment: "Short text for 'Heading 2'")
        case .heading3: NSLocalizedString("H3", comment: "Short text for 'Heading 3'")
        case .text: NSLocalizedString("Aa", comment: "Short text for 'Text'")
        case .bold: NSLocalizedString("B", comment: "Short text for 'Bold'")
        case .italic: NSLocalizedString("I", comment: "Short text for 'Italic'")
        case .underline: NSLocalizedString("U", comment: "Short text for 'Underline'")
        case .strikethrough: NSLocalizedString("S", comment: "Short text for 'Strikethrough'")
        default: nil
        }
    }
    static func decoration(for action: NoteFormatAction) -> NSAttributedString.Key? {
        switch action {
        case .underline: .underlineStyle
        case .strikethrough: .strikethroughStyle
        default: nil
        }
    }
    static func disclosure() -> NSImage? {
        NSImage(systemSymbolName: "arrowtriangle.down.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 6, weight: .bold))
    }
    static func plus() -> NSImage? {
        NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
    }
    static func textFormatting() -> NSImage? {
        NSImage(systemSymbolName: "bold.italic.underline", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
    }
    static func insertImage() -> NSImage { feather(insertImageCode) }
    static func formattedHyperlink() -> NSImage { feather(formattedHyperlinkCode) }

    static func feather(_ code: UInt32) -> NSImage {
        if let cached = featherCache[code] { return cached }
        if iconDescriptor == nil,
           let url = iconFontDirectory?.appendingPathComponent("feather.ttf"),
           let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = found.first {
            iconDescriptor = first
        }
        let font: NSFont
        if let descriptor = iconDescriptor {
            font = CTFontCreateWithFontDescriptor(descriptor, iconCacheSize, nil) as NSFont
        } else {
            font = .systemFont(ofSize: iconCacheSize)
        }
        let scalar = Unicode.Scalar(code).map { String(Character($0)) } ?? ""
        let text = NSAttributedString(string: scalar, attributes: [.font: font, .foregroundColor: NSColor.black])
        let image = NSImage(size: NSSize(width: iconCacheSize, height: iconCacheSize), flipped: false) { rect in
            let measured = text.size()
            text.draw(at: NSPoint(x: (rect.width - measured.width) * 0.5, y: (rect.height - measured.height) * 0.5))
            return true
        }
        image.isTemplate = true
        featherCache[code] = image
        return image
    }
    static func draw(_ image: NSImage, at origin: NSPoint, color: NSColor) {
        let tinted = NSImage(size: image.size, flipped: true) { rect in
            image.draw(in: rect); color.withAlphaComponent(1).setFill(); rect.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(origin: origin, size: image.size), from: .zero, operation: .sourceOver,
                    fraction: color.alphaComponent, respectFlipped: true, hints: nil)
    }
}

@MainActor
private enum NoteFormatControl {
    static func configure(_ button: NSButton) {
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .none
        (button.cell as? NSButtonCell)?.highlightsBy = []
        (button.cell as? NSButtonCell)?.showsStateBy = []
    }
}

@MainActor
final class NoteGutterButton: PointingHandButton {
    static let controlSize = NSSize(width: 42, height: 30)
    static let textGap: CGFloat = 5
    private var tracking: NSTrackingArea?
    private(set) var hovered = false
    var paragraphKind: EaselParagraphEditing.Kind = .text { didSet { needsDisplay = true } }
    var showsPlus = true { didSet { needsDisplay = true } }
    var showsSelected = false { didSet { needsDisplay = true } }
    var contentOpacity: CGFloat { hovered || isHighlighted || showsSelected ? 1 : 0.33 }
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.controlSize))
        NoteFormatControl.configure(self)
        NoteAccessibility.configureGutter(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === tracking else { super.mouseEntered(with: event); return }
        hovered = true; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === tracking else { super.mouseExited(with: event); return }
        clearHover()
    }
    func clearHover() { hovered = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if let fill = NoteFormattingAppearance.gutterFill(selected: showsSelected, hovered: hovered || isHighlighted) {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let foreground = NoteFormattingAppearance.text.withAlphaComponent(contentOpacity)
        let arrow = showsPlus ? nil : NoteFormatGlyph.disclosure()
        var label: String?, image: NSImage?, action = NoteFormatAction.text
        if showsPlus { image = NoteFormatGlyph.plus() }
        else {
            switch paragraphKind {
            case .heading1: action = .heading1; label = NoteFormatGlyph.letter(for: action)
            case .heading2: action = .heading2; label = NoteFormatGlyph.letter(for: action)
            case .heading3: action = .heading3; label = NoteFormatGlyph.letter(for: action)
            case .text: label = NoteFormatGlyph.letter(for: .text)
            case .bullets: image = NoteListGlyph.image(numbered: false)
            case .numbers: image = NoteListGlyph.image(numbered: true)
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteFormatGlyph.font(for: action), .foregroundColor: foreground]
        let labelSize = label.map { ($0 as NSString).size(withAttributes: attributes) }
        let iconSize = labelSize ?? image?.size ?? .zero
        let arrowSize = arrow?.size ?? .zero
        let width = iconSize.width + (arrow == nil ? 0 : 2 + arrowSize.width)
        let origin = NSPoint(x: (bounds.width - width) / 2, y: (bounds.height - iconSize.height) / 2)
        if let label { (label as NSString).draw(at: origin, withAttributes: attributes) }
        else if let image { NoteFormatGlyph.draw(image, at: origin, color: foreground) }
        if let arrow {
            NoteFormatGlyph.draw(arrow, at: NSPoint(x: origin.x + iconSize.width + 2, y: (bounds.height - arrowSize.height) / 2), color: foreground)
        }
    }
}

@MainActor
final class NoteFormattingView: NSView {
    private weak var text: EaselStyledTextView?
    private let session: NoteSession
    private let gutter = NoteGutterButton()
    private var hoverAdmission: NoteFormattingTarget?
    private var pointerInside = false
    private var hover: NoteParagraphGeometry.Target?
    private var formatMenu: NoteFormatMenu?
    private var target: NoteFormattingTarget?
    private weak var ownerWindow: NSWindow?
    private var geometry = NSRect.zero
    private var changingSelection = false
    private var tracking: NSTrackingArea?
    nonisolated(unsafe) private var clickMonitor: Any?
    nonisolated(unsafe) private var linkPopoverObserver: NoteAccessibility.PopoverCloseObserver?
    private var imagePanel: NSOpenPanel?
    private var imageRequest: UUID?
    private(set) lazy var selection = NoteSelectionFormatting(text: text, session: session, host: self)
    var onError: ((Error) -> Void)?
    override var isFlipped: Bool { true }
    var isPresentingMenu: Bool { formatMenu != nil || selection.isPresenting }
    var blocksSelectionMenu: Bool { formatMenu != nil || imagePanel != nil }

    init(text: EaselStyledTextView, session: NoteSession) {
        self.text = text; self.session = session
        super.init(frame: .zero)
        gutter.target = self; gutter.action = #selector(openHoveredParagraph)
        gutter.isHidden = true; addSubview(gutter)
        setAccessibilityElement(false)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResigned(_:)), name: NSWindow.didResignKeyNotification, object: nil)
    }
    func bindMotion() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reduceMotionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    @objc private func reduceMotionChanged() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { formatMenu?.settleMotion(); selection.settleMotion() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        linkPopoverObserver?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        if let hit = selection.hitTest(local) { return hit }
        if let formatMenu, formatMenu.frame.contains(local) { return formatMenu.hitTest(local) }
        if !gutter.isHidden, gutter.frame.contains(local) { return gutter.hitTest(local) }
        return nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard formatMenu == nil, !selection.isPresenting, imagePanel == nil else { return }
        guard let text, canHover, (superview ?? self).isTopmost(atWindowPoint: event.locationInWindow) else { hideGutter(); return }
        let point = text.convert(event.locationInWindow, from: nil)
        guard let next = NoteParagraphGeometry.target(in: text, at: point),
              let admitted = NoteFormattingTarget(text: text, document: session.document, range: next.range) else { hideGutter(); return }
        pointerInside = true; hover = next; hoverAdmission = admitted; positionGutter(next)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === tracking else { super.mouseEntered(with: event); return }
        pointerInside = true
        if let hover, validHover, (superview ?? self).isTopmost(atWindowPoint: event.locationInWindow) { positionGutter(hover) }
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === tracking else { super.mouseExited(with: event); return }
        pointerInside = false; gutter.clearHover()
        gutter.isHidden = formatMenu == nil || !validHover || !visibleRect.intersects(gutter.frame)
    }
    private var canHover: Bool {
        guard let text else { return false }
        return text.isEditable && !text.hasMarkedText() && !session.document.deleted &&
            window?.isKeyWindow == true && window?.attachedSheet == nil && !isHiddenOrHasHiddenAncestor
    }
    private var validHover: Bool {
        guard let text, let hoverAdmission else { return false }
        return canHover && hoverAdmission.matches(text: text, document: session.document)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { retire() }
        super.viewWillMove(toWindow: newWindow)
    }

    func reconcileGeometry() {
        selection.reconcileGeometry()
        guard let text else { return }
        if formatMenu != nil, convert(text.bounds, from: text) != geometry { dismiss() }
        if hover != nil, formatMenu == nil {
            guard validHover, let hover,
                  let next = NoteParagraphGeometry.refresh(hover, in: text) else { hideGutter(); return }
            self.hover = next; positionGutter(next)
        }
    }
    func localBodyPublished(previous: NoteDocument) {
        guard let text else { return }
        selection.localBodyPublished(previous: previous)
        hoverAdmission?.localBodyPublished(text: text, previous: previous, current: session.document)
        target?.localBodyPublished(text: text, previous: previous, current: session.document)
    }
    func contentsChanged() { dismissParagraph(); selection.contentsChanged(); hideGutter(); cancelImage() }
    func selectionChanged() {
        guard !changingSelection else { return }
        dismissParagraph(); selection.selectionChanged(); hideGutter()
        if let target, text?.selectedRange() != target.range { cancelImage() }
    }
    func retire() { dismiss(); hideGutter(); cancelImage(); stopLinkPopoverObserver(); selection.stopLinkPopoverObserver() }
    @objc private func windowResigned(_ notification: Notification) {
        if notification.object as? NSWindow === window { dismiss(restoreFocus: false); hideGutter() }
    }
    private func hideGutter() {
        hover = nil; hoverAdmission = nil; gutter.isHidden = true; gutter.clearHover()
        gutter.showsSelected = formatMenu != nil
    }
    private func positionGutter(_ value: NoteParagraphGeometry.Target) {
        guard let text, let window else { return }
        let range = value.iconRange
        let first = window.convertFromScreen(text.firstRect(forCharacterRange: value.sourceRange, actualRange: nil))
        let fontOffset = value.sourceRange.location < text.attributedString().length
            ? ((text.attributedString().attribute(.font, at: value.sourceRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 18) / 2 - 9 : 0
        let point = value.windowAnchor ?? NSPoint(x: first.minX, y: first.minY + fontOffset)
        let size = NoteGutterButton.controlSize
        let anchor = NSRect(x: point.x - size.width - NoteGutterButton.textGap,
                            y: point.y, width: size.width, height: size.height)
        gutter.frame = convert(anchor, from: nil)
        let icon = NoteGutterIcon.resolve(in: text, range: range)
        gutter.paragraphKind = icon.paragraphKind; gutter.showsPlus = icon == .plus
        gutter.isHidden = !pointerInside || !validHover || !visibleRect.intersects(gutter.frame)
    }
    @objc private func openHoveredParagraph() {
        guard validHover, !gutter.isHidden, let hover else { hideGutter(); return }
        present(range: hover.range, source: hover)
    }

    @objc func formatSelection(_ sender: Any? = nil) {
        guard let text, let paragraph = NoteParagraphGeometry.target(in: text, containing: text.selectedRange().location) else { return }
        if text.selectedRange().length > 0 {
            dismissParagraph(); selection.present(focus: true)
        } else { present(range: paragraph.range, focus: true) }
    }
    func present(range: NSRange, source: NoteParagraphGeometry.Target? = nil, focus: Bool = false) {
        guard let text, let window, window.isKeyWindow, window.attachedSheet == nil else { return }
        retire()
        changingSelection = true
        let focused = window.makeFirstResponder(text)
        changingSelection = false
        let refreshed: NoteParagraphGeometry.Target?
        if let source { refreshed = NoteParagraphGeometry.refresh(source, in: text) }
        else { refreshed = NoteParagraphGeometry.target(in: text, containing: range.location) }
        guard focused, let admitted = NoteFormattingTarget(text: text, document: session.document, range: range),
              let paragraph = refreshed, source == nil || paragraph.range == range else { return }
        ownerWindow = window; target = admitted; geometry = convert(text.bounds, from: text)
        changingSelection = true; text.setSelectedRange(range); changingSelection = false
        hover = paragraph; hoverAdmission = admitted
        if focus { NoteAccessibility.reveal(range, in: text) }
        positionGutter(paragraph)
        let formatMenu = NoteFormatMenu(text: text,
            canInteract: { [weak self] in
                guard let self, let target = self.target, let window = self.ownerWindow,
                      window.isKeyWindow, window.attachedSheet == nil else { return false }
                return self.admitted(target, in: window)
            },
            onAction: { [weak self] action in self?.perform(action) },
            onCancel: { [weak self] in self?.dismiss() },
            onResize: { [weak self] in self?.positionParagraphMenu() })
        self.formatMenu = formatMenu
        NoteMotion.presentImmediately(formatMenu, in: self)
        positionParagraphMenu(); gutter.isHidden = true
        gutter.showsSelected = true
        if focus { window.makeFirstResponder(formatMenu) }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.formatMenu != nil else { return }
                if event.window !== self.ownerWindow ||
                    self.formatMenu?.frame.contains(self.convert(event.locationInWindow, from: nil)) != true { self.dismiss(restoreFocus: false) }
            }
            return event
        }
    }
    private func positionParagraphMenu() {
        guard let formatMenu else { return }
        formatMenu.frame = NoteFormatMenu.frame(anchoredTo: gutter.frame, in: visibleRect,
                                                preferredHeight: formatMenu.preferredHeight)
        formatMenu.needsLayout = true; formatMenu.layoutSubtreeIfNeeded()
    }
    func pressEnter() {
        if formatMenu != nil { formatMenu?.pressEnter(); return }
        if selection.isPresenting { selection.pressEnter() }
    }
    func dismiss(restoreFocus: Bool = true) {
        selection.dismiss(restoreFocus: restoreFocus); dismissParagraph(restoreFocus: restoreFocus)
    }
    private func dismissParagraph(restoreFocus: Bool = true) {
        let owned = formatMenu
        formatMenu?.invalidate(); NoteMotion.dismissImmediately(formatMenu); formatMenu = nil
        gutter.showsSelected = false
        gutter.isHidden = !pointerInside || !validHover || !visibleRect.intersects(gutter.frame)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        if imagePanel == nil { target = nil; ownerWindow = nil }
        if restoreFocus, let text { NoteAccessibility.restoreBodyIfMenuRelinquished(text, owned: owned) }
    }
    private func admitted(_ target: NoteFormattingTarget, in window: NSWindow) -> Bool {
        guard self.target === target, ownerWindow === window,
              let text, self.window === window, text.window === window, !isHiddenOrHasHiddenAncestor,
              target.matches(text: text, document: session.document), text.selectedRange() == target.range else { return false }
        return true
    }
    func perform(_ action: NoteFormatAction) {
        guard let target, let window = ownerWindow, let text, window.isKeyWindow,
              admitted(target, in: window) else { retire(); return }
        if action == .image { chooseImage(target: target, window: window); return }
        if action == .link {
            guard target.range.length > 0 else { return }
            hover = NoteParagraphGeometry.target(in: text, containing: target.range.location)
            hoverAdmission = target; pointerInside = true
            if let hover { positionGutter(hover) }
            dismiss(); text.editLink(relativeTo: gutter)
            observeLinkPopover(anchor: gutter, text: text)
            return
        }
        dismiss()
        if let paragraph = action.paragraph { text.changeParagraph(paragraph) }
        if let emphasis = action.emphasis { text.toggle(emphasis) }
    }
    func performMenuCommand(_ command: TextFormatCommand) {
        guard let text else { return }
        if formatMenu != nil { dismissParagraph() }
        if command == .link { selection.editLinkFromMenu(); return }
        if selection.performMenuCommand(command) { return }
        let ranges = text.selectedRanges.map(\.rangeValue)
        if command == .increaseIndent || command == .decreaseIndent { _ = text.changeListIndent(outdent: command == .decreaseIndent) }
        if let emphasis = command.emphasis { text.toggle(emphasis, ranges: ranges) }
        if let kind = command.paragraph { text.changeParagraph(kind, ranges: ranges) }
    }
    private func chooseImage(target: NoteFormattingTarget, window: NSWindow) {
        let panel = NoteImageImport.makePanel()
        let request = UUID(); imageRequest = request; imagePanel = panel
        dismiss(); self.target = target; ownerWindow = window
        panel.beginSheetModal(for: window) { [weak self, weak panel, weak window] response in
            guard let self, self.imageRequest == request else { return }
            self.imageRequest = nil; self.imagePanel = nil
            defer { if self.target === target { self.target = nil; self.ownerWindow = nil } }
            guard let window, let text = self.text else { return }
            NoteAccessibility.returnFocus(to: text, in: window)
            guard response == .OK, let url = panel?.url, self.admitted(target, in: window) else { return }
            do {
                let data = try NoteImageImport.attachmentData(from: url)
                guard window.firstResponder === text, self.admitted(target, in: window) else { return }
                _ = try text.insertImage(data)
                NoteAccessibility.reveal(text.selectedRange(), in: text)
            } catch { self.onError?(error) }
        }
    }
    private func cancelImage() {
        imageRequest = nil
        let panel = imagePanel; imagePanel = nil; target = nil; ownerWindow = nil
        let text = self.text
        panel?.cancel(nil)
        if panel != nil, let text { NoteAccessibility.returnFocus(to: text, in: text.window) }
    }
    private func observeLinkPopover(anchor: NSView, text: EaselStyledTextView) {
        stopLinkPopoverObserver()
        linkPopoverObserver = NoteAccessibility.observePopoverClose(positioning: anchor, restore: text)
    }
    private func stopLinkPopoverObserver() {
        linkPopoverObserver?.invalidate(); linkPopoverObserver = nil
    }
}

@MainActor
final class NoteFormatMenu: NSView {
    enum Item: Equatable {
        case action(NoteFormatAction), emphasis, separator
        var title: String {
            switch self { case .action(let action): return action.title
            case .emphasis: return "Text Formatting"
            case .separator: return "" }
        }
    }
    static let width: CGFloat = 34
    static let itemHeight: CGFloat = 34
    static let spacing: CGFloat = 2
    static let padding: CGFloat = 2
    private let scroll = NSScrollView()
    private let rows = NoteFormatRows()
    private var buttons: [NoteFormatButton] = []
    private var highlights: [NSView] = []
    private var separators: [NSView] = []
    private let canInteract: () -> Bool
    private let onAction: (NoteFormatAction) -> Void
    private let onCancel: () -> Void
    private let onResize: () -> Void
    private let checked: Set<NoteFormatAction>
    private let canLink: Bool
    private var active = true
    private(set) var selectedIndex: Int?
    private(set) var items: [Item] = [.action(.heading1), .action(.heading2), .action(.heading3), .action(.text),
        .action(.bullets), .action(.numbers), .separator, .emphasis, .separator, .action(.image), .action(.link)]
    var preferredHeight: CGFloat {
        2 * Self.padding + items.reduce(0) { $0 + ($1 == .separator ? 5 : Self.itemHeight) } +
            CGFloat(max(0, items.count - 1)) * Self.spacing
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(text: EaselStyledTextView, canInteract: @escaping () -> Bool,
         onAction: @escaping (NoteFormatAction) -> Void, onCancel: @escaping () -> Void,
         onResize: @escaping () -> Void) {
        self.canInteract = canInteract; self.onAction = onAction; self.onCancel = onCancel; self.onResize = onResize
        canLink = text.selectedRange().length > 0
        checked = Set(NoteFormatAction.allCases.filter {
            $0.paragraph.map { $0 == text.paragraphKind() } ?? $0.emphasis.map(text.hasEmphasis) ?? false
        })
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 7
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.12; layer?.shadowRadius = 7
        NoteAccessibility.configureParagraphMenu(self)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false; scroll.documentView = rows; addSubview(scroll)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshAppearance()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); refreshAppearance()
    }
    private func refreshAppearance() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NoteFormattingAppearance.background.cgColor
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer?.borderColor = (dark ? NoteFormattingAppearance.border : NSColor.clear).cgColor
            layer?.borderWidth = 0.5
            for separator in separators {
                separator.layer?.backgroundColor = NoteFormattingAppearance.border.withAlphaComponent(0.2).cgColor
            }
        }
        CATransaction.commit()
        highlights.forEach(NoteMotion.refreshHighlight)
        buttons.forEach { $0.needsDisplay = true }
    }
    static func frame(anchoredTo anchor: NSRect, in visible: NSRect, preferredHeight: CGFloat) -> NSRect {
        let inset = min(10, max(0, visible.height / 2))
        let available = visible.insetBy(dx: 0, dy: inset)
        let size = NSSize(width: min(width, max(0, available.width)), height: min(preferredHeight, max(0, available.height)))
        return NSRect(x: min(max(available.minX, anchor.midX - size.width / 2), available.maxX - size.width),
                      y: min(max(available.minY, anchor.midY - size.height / 2), available.maxY - size.height),
                      width: size.width, height: size.height)
    }
    func invalidate() {
        active = false; settleMotion()
        buttons.forEach { $0.isEnabled = false }
    }
    override func layout() {
        super.layout(); scroll.frame = bounds
        rows.frame = NSRect(x: 0, y: 0, width: bounds.width, height: preferredHeight)
        var y = Self.padding, separatorIndex = 0
        for (index, item) in items.enumerated() {
            let height: CGFloat = item == .separator ? 5 : Self.itemHeight
            if item == .separator {
                separators[separatorIndex].frame = NSRect(x: 2, y: y + 2, width: max(0, bounds.width - 4), height: 1)
                separatorIndex += 1
            } else if let button = buttons.first(where: { $0.tag == index }) {
                button.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
                if let highlightIndex = buttons.firstIndex(where: { $0 === button }), highlights.indices.contains(highlightIndex) {
                    NoteMotion.layoutHighlight(highlights[highlightIndex], over: button)
                }
            }
            y += height + Self.spacing
        }
    }
    private func rebuild(animated: Bool = false) {
        retireOrphanedRows()
        let previousButtons = buttons
        let previousHighlights = highlights
        var nextButtons: [NoteFormatButton] = []
        var nextHighlights: [NSView] = []
        var nextSeparators: [NSView] = []
        var consumed: Set<ObjectIdentifier> = []
        for (index, item) in items.enumerated() {
            if item == .separator {
                let separator = NSView(); separator.wantsLayer = true
                separator.setAccessibilityElement(false); rows.addSubview(separator); nextSeparators.append(separator)
            } else if let existing = previousButtons.first(where: { $0.item == item && !consumed.contains(ObjectIdentifier($0)) }) {
                consumed.insert(ObjectIdentifier(existing))
                existing.tag = index; existing.isEnabled = item != .action(.link) || canLink
                nextButtons.append(existing)
                if let highlightIndex = previousButtons.firstIndex(where: { $0 === existing }),
                   previousHighlights.indices.contains(highlightIndex) {
                    nextHighlights.append(previousHighlights[highlightIndex])
                } else {
                    let highlight = NoteMotion.makeHighlight()
                    rows.addSubview(highlight, positioned: .below, relativeTo: existing)
                    nextHighlights.append(highlight)
                }
            } else {
                let button = NoteFormatButton(item: item, target: self, action: #selector(activate(_:)))
                button.tag = index; button.isEnabled = item != .action(.link) || canLink
                if case .action(let action) = item { button.state = checked.contains(action) ? .on : .off }
                let highlight = NoteMotion.makeHighlight()
                rows.addSubview(button); rows.addSubview(highlight, positioned: .below, relativeTo: button)
                nextButtons.append(button); nextHighlights.append(highlight)
                if animated {
                    button.alphaValue = 0
                    NoteMotion.fadeItem(button, visible: true)
                    NoteMotion.fadeItem(highlight, visible: highlightOwns(button))
                }
            }
        }
        for (index, old) in previousButtons.enumerated() where !consumed.contains(ObjectIdentifier(old)) {
            old.isEnabled = false; old.target = nil; old.action = nil
            let highlight = previousHighlights.indices.contains(index) ? previousHighlights[index] : nil
            if animated {
                NoteMotion.fadeItem(old, visible: false) { [weak old] in
                    old?.removeFromSuperview()
                }
                if let highlight {
                    NoteMotion.fadeItem(highlight, visible: false) { [weak highlight] in
                        highlight?.removeFromSuperview()
                    }
                }
            } else {
                old.removeFromSuperview(); highlight?.removeFromSuperview()
            }
        }
        separators.forEach { $0.removeFromSuperview() }
        buttons = nextButtons; highlights = nextHighlights; separators = nextSeparators
        refreshAppearance(); refreshHighlight(animated: animated); needsLayout = true
    }
    private func retireOrphanedRows() {
        var owned = Set(buttons.map { ObjectIdentifier($0) })
        owned.formUnion(highlights.map(ObjectIdentifier.init))
        owned.formUnion(separators.map(ObjectIdentifier.init))
        for subview in rows.subviews where !owned.contains(ObjectIdentifier(subview)) {
            NoteMotion.settle(subview)
            subview.removeFromSuperview()
        }
    }
    func pressEnter() {
        guard let selectedIndex, let button = buttons.first(where: { $0.tag == selectedIndex }) else { return }
        activate(button)
    }
    @objc private func activate(_ sender: NSButton) {
        guard active, buttons.contains(where: { $0 === sender }), sender.isEnabled,
              items.indices.contains(sender.tag) else { return }
        guard canInteract() else { onCancel(); return }
        let index = sender.tag
        switch items[index] {
        case .action(let action): onAction(action)
        case .emphasis:
            items.replaceSubrange(index...index, with: [.action(.bold), .action(.italic), .action(.underline), .action(.strikethrough)])
            rebuild(animated: true); onResize()
            if let selectedIndex, let button = buttons.first(where: { $0.tag == selectedIndex }) {
                NoteAccessibility.reveal(button)
            }
        case .separator: break
        }
    }
    override func keyDown(with event: NSEvent) {
        guard active else { return }
        guard canInteract() else { onCancel(); return }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53, 48: onCancel()
        case 125, 126:
            let enabled = buttons.filter(\.isEnabled).map(\.tag)
            guard let next = NoteAccessibility.nextIndex(from: selectedIndex, enabled: enabled, step: event.keyCode == 125 ? 1 : -1),
                  let button = buttons.first(where: { $0.tag == next }) else { return }
            selectedIndex = next; refreshHighlight(animated: true); NoteAccessibility.reveal(button)
        case 36, 76, 49:
            if let selectedIndex, let button = buttons.first(where: { $0.tag == selectedIndex }) { activate(button) }
        default: super.keyDown(with: event)
        }
    }
    func settleMotion() {
        NoteMotion.settle(self)
        retireOrphanedRows()
        for (index, button) in buttons.enumerated() {
            button.alphaValue = 1
            if highlights.indices.contains(index) {
                highlights[index].alphaValue = highlightOwns(button) ? 1 : 0
            }
        }
    }
    private func highlightOwns(_ button: NoteFormatButton) -> Bool {
        button.tag == selectedIndex && button.state != .on
    }
    private func refreshHighlight(animated: Bool = false) {
        for (index, button) in buttons.enumerated() {
            button.keyboardSelected = button.tag == selectedIndex
            if highlights.indices.contains(index) {
                NoteMotion.setHighlight(highlights[index], selected: highlightOwns(button), animated: animated)
            }
        }
    }
}

@MainActor
private final class NoteFormatRows: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteFormatButton: NSButton {
    let item: NoteFormatMenu.Item
    let showsDisclosure: Bool
    var keyboardSelected = false { didSet { needsDisplay = true } }
    private(set) var hovered = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    init(item: NoteFormatMenu.Item, target: AnyObject?, action: Selector?, showsDisclosure: Bool = false) {
        self.item = item; self.showsDisclosure = showsDisclosure
        super.init(frame: .zero); self.target = target; self.action = action
        NoteFormatControl.configure(self)
        NoteAccessibility.configureItem(self, item: item)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = next; addTrackingArea(next)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === tracking, isEnabled else { super.mouseEntered(with: event); return }
        hovered = isTopmost(atWindowPoint: event.locationInWindow); needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isEnabled && isTopmost(atWindowPoint: event.locationInWindow)
        guard value != hovered else { return }
        hovered = value; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === tracking else { super.mouseExited(with: event); return }
        hovered = false; needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let content = bounds.insetBy(dx: 2, dy: 2)
        let pointer = !keyboardSelected && (hovered || isHighlighted)
        if let fill = NoteFormattingAppearance.itemFill(checked: state == .on, hovered: pointer) {
            fill.setFill(); NSBezierPath(roundedRect: content, xRadius: 4, yRadius: 4).fill()
        }
        let color = NoteFormattingAppearance.ink(for: item, checked: state == .on)
            .withAlphaComponent(isEnabled ? 1 : 0.33)
        var label: String?, image: NSImage?
        var decoration: NSAttributedString.Key?
        var font = NoteFormatGlyph.font(for: .text)
        switch item {
        case .emphasis: image = NoteFormatGlyph.textFormatting()
        case .separator: return
        case .action(let action):
            if let letter = NoteFormatGlyph.letter(for: action) {
                label = letter; font = NoteFormatGlyph.font(for: action); decoration = NoteFormatGlyph.decoration(for: action)
            } else {
                switch action {
                case .bullets: image = NoteListGlyph.image(numbered: false)
                case .numbers: image = NoteListGlyph.image(numbered: true)
                case .image: image = NoteFormatGlyph.insertImage()
                case .link: image = NoteFormatGlyph.formattedHyperlink()
                default: break
                }
            }
        }
        if let label {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let decoration { attributes[decoration] = NSUnderlineStyle.single.rawValue }
            let size = (label as NSString).size(withAttributes: attributes)
            let disclosure = showsDisclosure ? NoteFormatGlyph.disclosure() : nil
            let extra = disclosure.map { $0.size.width + 2 } ?? 0
            (label as NSString).draw(at: NSPoint(x: bounds.midX - (size.width + extra) / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
            if let disclosure {
                NoteFormatGlyph.draw(disclosure, at: NSPoint(x: bounds.midX + (size.width - extra) / 2 + 2,
                                                            y: bounds.midY - disclosure.size.height / 2), color: color)
            }
        } else if let image {
            NoteFormatGlyph.draw(image, at: NSPoint(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2), color: color)
        }
    }
}
