import AppKit

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
              "*_-` \t\n".contains(character), selection.length == 0, replacement == selection,
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
