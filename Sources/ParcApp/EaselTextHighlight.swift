import AppKit

@MainActor
enum EaselTextHighlight {
    private static let namePrefix = "Parc.Easel.Mark."
    private static var colors: [NoteColor: NSColor] = [:]

    static func color(_ color: NoteColor) -> NSColor {
        if let cached = colors[color] { return cached }
        let light = EaselRichTextCodec.color(EaselPalette.mark(color, dark: false))
        let dark = EaselRichTextCodec.color(EaselPalette.mark(color, dark: true))
        let made = NSColor(name: NSColor.Name(namePrefix + color.rawValue)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        colors[color] = made
        return made
    }

    static func note(of color: NSColor) -> NoteColor? {
        guard color.type == .catalog else { return nil }
        let name = color.colorNameComponent
        guard name.hasPrefix(namePrefix) else { return nil }
        return NoteColor(rawValue: String(name.dropFirst(namePrefix.count)))
    }

    static func stored(_ color: NSColor) -> String? {
        note(of: color).map { EaselPalette.mark($0, dark: false) }
    }

    static func adapting(_ value: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        value.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: value.length)) { fill, range, _ in
            guard let fill = fill as? NSColor, fill.type != .catalog, let stored = try? EaselRichTextCodec.hex(fill),
                  let note = EaselPalette.markColor(for: stored) else { return }
            result.addAttribute(.backgroundColor, value: color(note), range: range)
        }
        return result
    }

    static func current(in attributes: [NSAttributedString.Key: Any]) -> NoteColor? {
        (attributes[.backgroundColor] as? NSColor).flatMap(note(of:))
    }
}

extension EaselStyledTextView {
    enum HighlightState: Equatable {
        case none
        case color(NoteColor)
        case mixed
    }

    func highlightState(ranges suppliedRanges: [NSRange]? = nil) -> HighlightState {
        let ranges = suppliedRanges ?? [selectedRange()]
        guard Self.validFormattingRanges(ranges, length: attributedString().length) else { return .none }
        var found = [NoteColor?]()
        if ranges.count == 1, ranges[0].length == 0 {
            found = [EaselTextHighlight.current(in: typingAttributes)]
        } else {
            for range in ranges {
                attributedString().enumerateAttribute(.backgroundColor, in: range) { fill, _, _ in
                    found.append((fill as? NSColor).flatMap(EaselTextHighlight.note(of:)))
                }
            }
        }
        guard let first = found.first else { return .none }
        guard found.allSatisfy({ $0 == first }) else { return .mixed }
        return first.map(HighlightState.color) ?? .none
    }

    func applyHighlight(_ color: NoteColor?) {
        format("Highlight") { attributes in
            var next = attributes
            if let color { next[.backgroundColor] = EaselTextHighlight.color(color) }
            else if (next[.backgroundColor] as? NSColor).flatMap(EaselTextHighlight.note(of:)) != nil { next.removeValue(forKey: .backgroundColor) }
            return next
        }
    }

    func hasInlineCode(ranges suppliedRanges: [NSRange]? = nil) -> Bool {
        let ranges = suppliedRanges ?? [selectedRange()]
        guard Self.validFormattingRanges(ranges, length: attributedString().length) else { return false }
        if ranges.count == 1, ranges[0].length == 0 { return EaselTextAppearance.isInlineCode(typingAttributes) }
        var result = true
        for range in ranges where range.length > 0 {
            attributedString().enumerateAttributes(in: range) { attributes, _, _ in result = result && EaselTextAppearance.isInlineCode(attributes) }
        }
        return result
    }

    func toggleInlineCode(ranges: [NSRange]? = nil) {
        let remove = hasInlineCode(ranges: ranges)
        let base = objectStyle
        format("Code", ranges: ranges) { attributes in
            var next = attributes
            let font = (attributes[.font] as? NSFont) ?? EaselTextAppearance.font(base)
            if remove {
                let plain = EaselTextAppearance.font(EaselTextStyle(family: base.family, size: base.size, customSize: font.pointSize))
                var traits: NSFontTraitMask = []
                if font.fontDescriptor.symbolicTraits.contains(.bold) { traits.insert(.boldFontMask) }
                if font.fontDescriptor.symbolicTraits.contains(.italic) { traits.insert(.italicFontMask) }
                next[.font] = traits.isEmpty ? plain : NSFontManager.shared.convert(plain, toHaveTrait: traits)
                next.removeValue(forKey: .backgroundColor)
            } else {
                let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
                next[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: bold ? .bold : .regular)
                next[.backgroundColor] = EaselTextAppearance.inlineCodeFill
            }
            return next
        }
    }
}
