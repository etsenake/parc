import AppKit
import ParcCore
import ParcNotes

@MainActor
enum EaselMarkdownEditing {
    struct Admission {
        let original: String
        let insertion: NSRange
        let character: String
        var expected: String { (original as NSString).replacingCharacters(in: insertion, with: character) }
        var caret: Int { insertion.location + (character as NSString).length }
    }
    static func admission(_ input: Any, text: String, selection: NSRange, replacement: NSRange) -> Admission? {
        guard let character = input as? String, character.count == 1,
              "*_-` \t\n~=$><".contains(character), selection.length == 0, replacement == selection,
              replacement.location != NSNotFound, replacement.location <= (text as NSString).length else { return nil }
        return Admission(original: text, insertion: replacement, character: character)
    }
    static func transform(_ original: NSAttributedString, admission: Admission,
                          selection: NSRange, typing: [NSAttributedString.Key: Any],
                          base: EaselTextStyle) -> EaselParagraphEditing.Edit? {
        guard original.string == admission.expected, selection == NSRange(location: admission.caret, length: 0),
              admission.insertion.location < original.length else { return nil }
        let line = (original.string as NSString).lineRange(for: NSRange(location: admission.insertion.location, length: 0))
        let local = original.attributedSubstring(from: line), source = local.string as NSString
        let inserted = admission.insertion.location - line.location
        let caret = admission.caret - line.location
        let attrs = local.attributes(at: min(inserted, local.length - 1), effectiveRange: nil)
        let paragraph = EaselParagraphEditing.style(attrs)
        var kind: EaselParagraphEditing.Kind?
        var prefix: NSRange?
        var depth = 0
        if paragraph.headerLevel == 0, paragraph.textLists.isEmpty {
            if let match = first(#"^(#{1,4}) "#, in: local.string), NSMaxRange(match.range) == caret {
                kind = [.heading1, .heading2, .heading3, .heading4][match.range(at: 1).length - 1]; prefix = match.range
            } else if let match = first(#"^> "#, in: local.string), NSMaxRange(match.range) == caret {
                kind = .quote; prefix = match.range
            } else if let match = first(#"^\[ ?\] "#, in: local.string), NSMaxRange(match.range) == caret {
                kind = .checklist; prefix = match.range
            } else if let match = first(#"^(\t{0,6})(-|\*) "#, in: local.string), NSMaxRange(match.range) == caret {
                kind = .bullets; prefix = match.range; depth = match.range(at: 1).length
            } else if let match = first(#"^(\t{0,6})1\.\s"#, in: local.string), NSMaxRange(match.range) == caret {
                kind = .numbers; prefix = match.range; depth = match.range(at: 1).length
            }
        }
        if let kind, let prefix {
            var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: local),
                                                  selection: NSRange(location: caret, length: 0), typing: typing)
            EaselParagraphEditing.replace(&edit, range: prefix, with: NSAttributedString(string: ""))
            edit = EaselParagraphEditing.apply(kind, to: edit.text, selection: edit.selection, typing: edit.typing, base: base)
            for _ in 0..<depth {
                guard let nested = EaselParagraphEditing.indent(edit.text, selection: edit.selection, typing: edit.typing, outdent: false, base: base) else { return nil }
                edit = nested
            }
            return replacing(line, in: original, with: edit)
        }
        if let edit = noteShortcut(original, admission: admission, typing: typing, base: base) { return edit }
        guard ["*", "_", "-", "`"].contains(admission.character) else { return nil }
        let delimiter = NSRegularExpression.escapedPattern(for: admission.character)
        let body = admission.character == "`" ? "[^`\\n\\x{FFFC}]+" : "\\w+(?:\\s\\w+)*"
        let pattern = "(?:^|\\s)(" + delimiter + body + delimiter + ")(?=\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: local.string, range: NSRange(location: 0, length: source.length))
                .first(where: { NSMaxRange($0.range(at: 1)) == caret }) else { return nil }
        let token = match.range(at: 1), content = NSRange(location: token.location + 1, length: token.length - 2)
        let result = NSMutableAttributedString(attributedString: local)
        var refused = false
        local.enumerateAttributes(in: content) { attrs, range, stop in
            var next = attrs
            if admission.character == "-" { next[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            else if admission.character == "`" {
                let font = (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(base)
                let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
                next[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: bold ? .bold : .regular)
                next[.backgroundColor] = EaselTextAppearance.inlineCodeFill
            } else {
                let font = (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(base)
                let trait: NSFontTraitMask = admission.character == "*" ? .boldFontMask : .italicFontMask
                let symbol: NSFontDescriptor.SymbolicTraits = admission.character == "*" ? .bold : .italic
                let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
                guard converted.fontDescriptor.symbolicTraits.contains(symbol) else { refused = true; stop.pointee = true; return }
                next[.font] = converted
            }
            result.setAttributes(next, range: range)
        }
        guard !refused else { return nil }
        var edit = EaselParagraphEditing.Edit(text: result, selection: NSRange(location: caret, length: 0), typing: typing)
        EaselParagraphEditing.replace(&edit, range: NSRange(location: NSMaxRange(token) - 1, length: 1), with: NSAttributedString(string: ""))
        EaselParagraphEditing.replace(&edit, range: NSRange(location: token.location, length: 1), with: NSAttributedString(string: ""))
        return replacing(line, in: original, with: edit)
    }
    static let easelTokens: Set<String> = ["*", "_", "`"]

    private static func blocked(_ value: NSAttributedString, _ range: Range<Int>, atoms: Bool, code: Bool) -> Bool {
        guard range.lowerBound >= 0, range.upperBound <= value.length, !range.isEmpty else { return false }
        var found = false
        value.enumerateAttributes(in: NSRange(location: range.lowerBound, length: range.count)) { attrs, _, stop in
            if (atoms && attrs[.attachment] != nil) || (code && EaselTextAppearance.isInlineCode(attrs)) { found = true; stop.pointee = true }
        }
        return found
    }

    static func noteShortcut(_ original: NSAttributedString, admission: Admission, typing: [NSAttributedString.Key: Any],
                             base: EaselTextStyle) -> EaselParagraphEditing.Edit? {
        guard let typed = admission.character.first, admission.caret <= original.length else { return nil }
        let caret = admission.caret
        if caret > 0, blocked(original, (caret - 1)..<caret, atoms: false, code: true), typed != "`" { return nil }
        let units = Array(original.string.utf16)
        if let found = NoteInputRules.inlineMatch(typed: typed, units: units, caret: caret, accepts: { token, isEquation, range in
            if easelTokens.contains(token) { return false }
            if !isEquation, blocked(original, range, atoms: false, code: true) { return false }
            if isEquation, blocked(original, range, atoms: true, code: false) { return false }
            return true
        }) {
            return inlineEdit(original, found, typing: typing, base: base)
        }
        let string = original.string as NSString
        guard let symbol = NoteInputRules.symbolMatch(typed: typed, string: string, caret: caret, blocked: { range in
            blocked(original, range, atoms: true, code: true)
        }) else { return nil }
        let result = NSMutableAttributedString(attributedString: original)
        var attrs = original.attributes(at: symbol.range.lowerBound, effectiveRange: nil)
        attrs.removeValue(forKey: .attachment)
        result.replaceCharacters(in: NSRange(location: symbol.range.lowerBound, length: symbol.range.count),
                                 with: NSAttributedString(string: symbol.shown, attributes: attrs))
        return .init(text: result, selection: NSRange(location: symbol.range.lowerBound + (symbol.shown as NSString).length, length: 0), typing: typing)
    }

    private static func inlineEdit(_ original: NSAttributedString, _ found: NoteInputRules.InlineMatch,
                                   typing: [NSAttributedString.Key: Any], base: EaselTextStyle) -> EaselParagraphEditing.Edit? {
        let content = NSRange(location: found.contentStart, length: found.closeStart - found.contentStart)
        let result = NSMutableAttributedString(attributedString: original)
        let closeLength = found.caret - found.closeStart, openLength = found.contentStart - found.open
        var nextTyping = typing
        if found.isEquation {
            let tex = (original.string as NSString).substring(with: content)
            var attrs = original.attributes(at: found.open, effectiveRange: nil)
            attrs.removeValue(forKey: .attachment)
            let inline = EaselRichText.Inline.equation(tex)
            guard (try? inline.validate()) != nil else { return nil }
            result.replaceCharacters(in: NSRange(location: found.open, length: found.caret - found.open),
                                     with: EaselInlineText.character(inline, attributes: attrs))
            return .init(text: result, selection: NSRange(location: found.open + 1, length: 0), typing: typing)
        }
        var refused = false
        original.enumerateAttributes(in: content) { attrs, range, stop in
            var next = attrs
            switch found.token {
            case "**", "__":
                let font = (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(base)
                let converted = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                guard converted.fontDescriptor.symbolicTraits.contains(.bold) else { refused = true; stop.pointee = true; return }
                next[.font] = converted
            case "~~", "~": next[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case "==": next[.backgroundColor] = EaselTextHighlight.color(.yellow)
            default: refused = true; stop.pointee = true; return
            }
            result.setAttributes(next, range: range)
        }
        guard !refused else { return nil }
        switch found.token {
        case "**", "__":
            if let font = nextTyping[.font] as? NSFont { nextTyping[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask) }
        case "~~", "~": nextTyping.removeValue(forKey: .strikethroughStyle)
        default: nextTyping.removeValue(forKey: .backgroundColor)
        }
        result.deleteCharacters(in: NSRange(location: found.closeStart, length: closeLength))
        result.deleteCharacters(in: NSRange(location: found.open, length: openLength))
        return .init(text: result, selection: NSRange(location: found.closeStart - openLength, length: 0), typing: nextTyping)
    }

    private static func first(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
    private static func replacing(_ range: NSRange, in original: NSAttributedString,
                                  with local: EaselParagraphEditing.Edit) -> EaselParagraphEditing.Edit {
        let result = NSMutableAttributedString(attributedString: original)
        result.replaceCharacters(in: range, with: local.text)
        return .init(text: result, selection: NSRange(location: range.location + local.selection.location, length: local.selection.length), typing: local.typing)
    }
}
