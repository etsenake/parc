import AppKit
import ParcCore

@MainActor
enum EaselTextPresentation {
    static func displayed(_ value: NSAttributedString, for item: EaselItem) -> NSAttributedString {
        guard let alignment = EaselTextPlacement.alignment(for: item) else { return value }
        let result = NSMutableAttributedString(attributedString: value)
        apply(alignment, to: result)
        if item.kind != .text { EaselTextAttachments.bind(result, width: max(1, EaselTextPlacement.box(for: item).width - 20)) }
        return result
    }

    static func stored(_ value: NSAttributedString, for item: EaselItem) -> NSAttributedString {
        guard EaselTextPlacement.alignment(for: item) != nil else { return value }
        let result = NSMutableAttributedString(attributedString: value)
        var changes: [(NSRange, NSParagraphStyle)] = []
        result.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle, style.alignment != .natural else { return }
            style.alignment = .natural
            changes.append((range, style))
        }
        for (range, style) in changes { result.addAttribute(.paragraphStyle, value: style, range: range) }
        return result
    }

    static func typingAttributes(_ attributes: [NSAttributedString.Key: Any], for item: EaselItem) -> [NSAttributedString.Key: Any] {
        guard let alignment = EaselTextPlacement.alignment(for: item) else { return attributes }
        let target = textAlignment(alignment)
        let style = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        guard style.alignment != target || attributes[.paragraphStyle] == nil else { return attributes }
        style.alignment = target
        var result = attributes
        result[.paragraphStyle] = style
        return result
    }

    static func enforce(_ item: EaselItem, in editor: NSTextView) {
        guard let alignment = EaselTextPlacement.alignment(for: item), let storage = editor.textStorage else { return }
        apply(alignment, to: storage)
        let typing = typingAttributes(editor.typingAttributes, for: item)
        if (typing[.paragraphStyle] as? NSParagraphStyle) != (editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle) {
            editor.typingAttributes = typing
        }
    }

    static func textAlignment(_ alignment: EaselTextStyle.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    private static func apply(_ alignment: EaselTextStyle.Alignment, to text: NSMutableAttributedString) {
        let target = textAlignment(alignment)
        var changes: [(NSRange, NSParagraphStyle)] = []
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            guard style.alignment != target else { return }
            style.alignment = target
            changes.append((range, style))
        }
        guard !changes.isEmpty else { return }
        text.beginEditing()
        for (range, style) in changes { text.addAttribute(.paragraphStyle, value: style, range: range) }
        text.endEditing()
    }
}
