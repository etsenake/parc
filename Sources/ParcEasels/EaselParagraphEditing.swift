import AppKit
import ParcCore

@MainActor
enum EaselParagraphEditing {
    package enum Kind: String, CaseIterable {
        case text = "Text", heading1 = "Heading 1", heading2 = "Heading 2", heading3 = "Heading 3", heading4 = "Heading 4"
        case bullets = "Bulleted List", numbers = "Numbered List", checklist = "To-do List", quote = "Quote"
        var level: Int { switch self { case .heading1: 1; case .heading2: 2; case .heading3: 3; case .heading4: 4; default: 0 } }
        var marker: NSTextList.MarkerFormat? {
            switch self {
            case .bullets: .disc
            case .numbers: NSTextList.MarkerFormat(rawValue: "{decimal}.")
            case .quote: EaselParagraphEditing.quoteMarker
            case .checklist: EaselParagraphEditing.openMarker
            default: nil
            }
        }
    }
    nonisolated static let quoteMarker = NSTextList.MarkerFormat(rawValue: "\u{258E}")
    nonisolated static let openMarker = NSTextList.MarkerFormat(rawValue: EaselChecklist.openMarker)
    nonisolated static let doneMarker = NSTextList.MarkerFormat(rawValue: EaselChecklist.doneMarker)
    nonisolated static let dividerMarker = NSTextList.MarkerFormat(rawValue: EaselChecklist.dividerMarker)
    static func checklistMarker(_ list: NSTextList) -> EaselChecklist.Marker? { EaselChecklist.marker(list.markerFormat.rawValue) }
    static func isDivider(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        style(attrs).textLists.last.flatMap(checklistMarker) == .divider
    }
    static let headingSizes: [CGFloat] = [32, 26, 22, 19]
    static func isQuote(_ list: NSTextList) -> Bool { list.markerFormat == quoteMarker }
    struct Edit {
        var text: NSMutableAttributedString
        var selection: NSRange
        var typing: [NSAttributedString.Key: Any]
        var additionalSelections: [NSRange] = []
        var selections: [NSRange] { [selection] + additionalSelections }
    }
    static func style(_ attrs: [NSAttributedString.Key: Any]) -> NSMutableParagraphStyle {
        ((attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    }
    static func ranges(_ text: String, selection: NSRange) -> [NSRange] {
        let source = text as NSString
        guard selection.location != NSNotFound, selection.location <= source.length,
              selection.length <= source.length - selection.location else { return [] }
        if source.length == 0 { return [NSRange(location: 0, length: 0)] }
        if selection.length == 0, selection.location == source.length,
           source.substring(from: source.length - 1).rangeOfCharacter(from: .newlines) != nil {
            return [NSRange(location: source.length, length: 0)]
        }
        let end = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        var current = source.paragraphRange(for: NSRange(location: selection.location, length: 0)), result = [NSRange]()
        repeat {
            result.append(current)
            let next = NSMaxRange(current)
            if next > end || next >= source.length { break }
            current = source.paragraphRange(for: NSRange(location: next, length: 0))
        } while current.length > 0
        return result
    }
    static func attributes(_ edit: Edit, at range: NSRange) -> [NSAttributedString.Key: Any] {
        range.location < edit.text.length ? edit.text.attributes(at: range.location, effectiveRange: nil) : edit.typing
    }
    static func kind(_ attrs: [NSAttributedString.Key: Any]) -> Kind? {
        let paragraph = style(attrs)
        if let list = paragraph.textLists.last {
            if list.markerFormat == .disc { return .bullets }
            if isNumbered(list) { return .numbers }
            if isQuote(list) { return .quote }
            if checklistMarker(list)?.isItem == true { return .checklist }
            return nil
        }
        switch paragraph.headerLevel {
        case 0: return .text
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        default: return nil
        }
    }
    static func isNumbered(_ list: NSTextList) -> Bool { list.markerFormat == .decimal || list.markerFormat.rawValue == "{decimal}." }
    static func markerRange(_ text: NSAttributedString, paragraph: NSRange) -> NSRange {
        guard paragraph.length > 0,
              let p = text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
              !p.textLists.isEmpty else { return NSRange(location: paragraph.location, length: 0) }
        let value = (text.string as NSString).substring(with: paragraph)
        guard let list = p.textLists.last,
              let match = value.range(of: "^\\t[^\\t\\r\\n]+\\t", options: .regularExpression) else {
            return NSRange(location: paragraph.location, length: 0)
        }
        let prefix = String(value[match]), marker = String(prefix.dropFirst().dropLast())
        let isMarker: Bool
        if list.markerFormat == .disc || isQuote(list) || checklistMarker(list) != nil {
            isMarker = marker == list.marker(forItemNumber: 1)
        } else if isNumbered(list) {
            let digits = list.markerFormat == .decimal ? marker : String(marker.dropLast())
            isMarker = !digits.isEmpty && digits.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
                && Int(digits).map { list.marker(forItemNumber: $0) == marker } == true
        } else {
            isMarker = false
        }
        guard isMarker else { return NSRange(location: paragraph.location, length: 0) }
        return NSRange(location: paragraph.location, length: (prefix as NSString).length)
    }
    static func replace(_ edit: inout Edit, range: NSRange, with replacement: NSAttributedString) {
        func mapped(_ position: Int) -> Int {
            if position < range.location { return position }
            if position <= NSMaxRange(range) { return range.location + replacement.length }
            return position + replacement.length - range.length
        }
        edit.additionalSelections = edit.additionalSelections.map { range in
            let start = mapped(range.location), end = mapped(NSMaxRange(range))
            return NSRange(location: start, length: max(0, end - start))
        }
        let start = mapped(edit.selection.location), end = mapped(NSMaxRange(edit.selection))
        edit.text.replaceCharacters(in: range, with: replacement)
        edit.selection = NSRange(location: start, length: max(0, end - start))
    }
    static func formatted(_ attrs: [NSAttributedString.Key: Any], kind: Kind, base: EaselTextStyle, bodyPointSize: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        var result = attrs
        let paragraph = style(attrs)
        paragraph.headerLevel = kind.level
        paragraph.lineHeightMultiple = 1.25
        paragraph.paragraphSpacingBefore = 4; paragraph.paragraphSpacing = 8
        paragraph.textLists = []
        paragraph.firstLineHeadIndent = 0; paragraph.headIndent = 0
        if let marker = kind.marker {
            paragraph.textLists = [NSTextList(markerFormat: marker, options: 0)]
            paragraph.firstLineHeadIndent = 0; paragraph.headIndent = 24
            paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 16), NSTextTab(textAlignment: .left, location: 24)]
        }
        let current = (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(base)
        if kind.level > 0 {
            result[.font] = NSFontManager.shared.convert(current, toSize: headingSizes[min(kind.level, headingSizes.count) - 1])
        } else if style(attrs).headerLevel > 0 {
            let body = EaselTextStyle(family: EaselTextAppearance.paletteFamily(current) ?? base.family, size: .body)
            result[.font] = NSFontManager.shared.convert(current, toSize: bodyPointSize ?? body.pointSize)
        }
        result[.paragraphStyle] = paragraph
        return result
    }
    static func apply(_ kind: Kind, to original: NSAttributedString, selection: NSRange,
                      typing: [NSAttributedString.Key: Any], base: EaselTextStyle, bodyPointSize: CGFloat? = nil) -> Edit {
        apply(kind, to: original, selections: [selection], typing: typing, base: base, bodyPointSize: bodyPointSize)
    }
    static func apply(_ kind: Kind, to original: NSAttributedString, selections: [NSRange],
                      typing: [NSAttributedString.Key: Any], base: EaselTextStyle, bodyPointSize: CGFloat? = nil) -> Edit {
        let first = selections.first ?? NSRange(location: 0, length: 0)
        var edit = Edit(text: NSMutableAttributedString(attributedString: original), selection: first, typing: typing,
                        additionalSelections: Array(selections.dropFirst()))
        var paragraphs: [NSRange] = []
        for selection in selections {
            for range in ranges(original.string, selection: selection) where !paragraphs.contains(range) { paragraphs.append(range) }
        }
        paragraphs.sort { $0.location < $1.location }
        for range in paragraphs.reversed() {
            let attrs = attributes(edit, at: range)
            let prefix = markerRange(edit.text, paragraph: range)
            if range.length > 0 {
                edit.text.enumerateAttributes(in: range) { attrs, part, _ in
                    edit.text.setAttributes(formatted(attrs, kind: kind, base: base, bodyPointSize: bodyPointSize), range: part)
                }
            }
            let next = formatted(attrs, kind: kind, base: base, bodyPointSize: bodyPointSize)
            let marker = kind.marker.map { "\t" + NSTextList(markerFormat: $0, options: 0).marker(forItemNumber: 1) + "\t" } ?? ""
            if prefix.length > 0 || !marker.isEmpty { replace(&edit, range: prefix, with: NSAttributedString(string: marker, attributes: next)) }
            edit.typing = next
        }
        renumber(&edit)
        return edit
    }
    static func renumber(_ edit: inout Edit) {
        var position = 0, counters: [Int] = [], formats: [String] = []
        while position < edit.text.length {
            let range = (edit.text.string as NSString).paragraphRange(for: NSRange(location: position, length: 0))
            let attrs = edit.text.attributes(at: position, effectiveRange: nil), p = style(attrs)
            let prefix = markerRange(edit.text, paragraph: range), depth = p.textLists.count
            guard depth > 0, let list = p.textLists.last,
                  isNumbered(list) || list.markerFormat == .disc else {
                counters = []; formats = []; position = NSMaxRange(range); continue
            }
            let keys = p.textLists.map { $0.markerFormat.rawValue }
            if counters.count > depth { counters = Array(counters.prefix(depth)); formats = Array(formats.prefix(depth)) }
            if counters.count == depth, formats == keys { counters[depth - 1] += 1 }
            else {
                while counters.count < depth { counters.append(0) }
                counters[depth - 1] = max(1, list.startingItemNumber); formats = keys
            }
            let marker = "\t" + list.marker(forItemNumber: counters[depth - 1]) + "\t"
            if (edit.text.string as NSString).substring(with: prefix) != marker {
                replace(&edit, range: prefix, with: NSAttributedString(string: marker, attributes: attrs))
            }
            position = NSMaxRange((edit.text.string as NSString).paragraphRange(for: NSRange(location: position, length: 0)))
        }
    }
    static func canIndent(_ original: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any], outdent: Bool) -> Bool {
        let paragraphs = ranges(original.string, selection: selection)
        return !paragraphs.isEmpty && paragraphs.allSatisfy { range in
            let p = style(range.location < original.length ? original.attributes(at: range.location, effectiveRange: nil) : typing)
            return !p.textLists.isEmpty && (outdent || (p.textLists.count < 7 && p.textLists.last.flatMap(checklistMarker) != .divider))
        }
    }
    static func indent(_ original: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any],
                       outdent: Bool, base: EaselTextStyle) -> Edit? {
        guard canIndent(original, selection: selection, typing: typing, outdent: outdent) else { return nil }
        var edit = Edit(text: NSMutableAttributedString(attributedString: original), selection: selection, typing: typing)
        let paragraphs = ranges(original.string, selection: selection)
        for range in paragraphs.reversed() {
            var attrs = attributes(edit, at: range)
            let p = style(attrs), prefix = markerRange(edit.text, paragraph: range)
            if outdent { p.textLists.removeLast() }
            else if let last = p.textLists.last { p.textLists.append(NSTextList(markerFormat: last.markerFormat, options: Int(last.listOptions.rawValue))) }
            let depth = p.textLists.count
            p.firstLineHeadIndent = CGFloat(max(0, depth - 1)) * 24; p.headIndent = CGFloat(depth) * 24
            p.tabStops = depth == 0 ? NSParagraphStyle.default.tabStops : [NSTextTab(textAlignment: .right, location: p.headIndent - 8), NSTextTab(textAlignment: .left, location: p.headIndent)]
            attrs[.paragraphStyle] = p
            if range.length > 0 { edit.text.addAttribute(.paragraphStyle, value: p, range: range) }
            let marker = p.textLists.last.map { "\t" + $0.marker(forItemNumber: 1) + "\t" } ?? ""
            replace(&edit, range: prefix, with: NSAttributedString(string: marker, attributes: attrs))
            edit.typing = attrs
        }
        renumber(&edit); return edit
    }
    static func newline(_ original: NSAttributedString, selection: NSRange,
                        typing: [NSAttributedString.Key: Any], base: EaselTextStyle, bodyPointSize: CGFloat? = nil) -> Edit? {
        guard let range = ranges(original.string, selection: NSRange(location: selection.location, length: 0)).first else { return nil }
        var edit = Edit(text: NSMutableAttributedString(attributedString: original), selection: selection, typing: typing)
        let attrs = attributes(edit, at: range), p = style(attrs)
        guard !p.textLists.isEmpty || p.headerLevel > 0 else { return nil }
        let prefix = markerRange(original, paragraph: range)
        let content = (original.string as NSString).substring(with: NSRange(location: NSMaxRange(prefix), length: NSMaxRange(range) - NSMaxRange(prefix)))
        if !p.textLists.isEmpty, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return indent(original, selection: selection, typing: typing, outdent: true, base: base)
        }
        if let list = p.textLists.last, checklistMarker(list) == .done {
            p.textLists = Array(p.textLists.dropLast()) + [NSTextList(markerFormat: openMarker, options: Int(list.listOptions.rawValue))]
        }
        var next = typing
        next[.paragraphStyle] = p
        if p.headerLevel > 0 { next = formatted(next, kind: .text, base: base, bodyPointSize: bodyPointSize) }
        let marker = p.textLists.last.map { "\t" + $0.marker(forItemNumber: 1) + "\t" } ?? ""
        let inserted = NSMutableAttributedString(string: "\n", attributes: attrs)
        inserted.append(NSAttributedString(string: marker, attributes: next))
        replace(&edit, range: selection, with: inserted)
        edit.selection.length = 0; edit.typing = next
        if edit.selection.location < edit.text.length {
            let following = (edit.text.string as NSString).paragraphRange(for: edit.selection)
            edit.text.addAttribute(.paragraphStyle, value: style(next), range: following)
            if p.headerLevel > 0, following.length > 0 {
                edit.text.enumerateAttribute(.font, in: following) { value, part, _ in
                    let font = (value as? NSFont) ?? EaselTextAppearance.font(base)
                    edit.text.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: bodyPointSize ?? EaselTextStyle(family: EaselTextAppearance.paletteFamily(font) ?? base.family, size: .body).pointSize), range: part)
                }
            }
        }
        renumber(&edit); return edit
    }
}
