import CoreGraphics
import Foundation

enum CommandBarFieldAnchor {
    static let leadCharacters = 12
    static let measuredLength = 10_000

    static func completion(_ state: CommandBarEditState) -> NSRange? {
        guard let projection = state.projection, !projection.accepted else { return nil }
        let range = state.selection
        return range.length > 0 ? range : nil
    }

    static func leavesCompletion(selection: NSRange, completion: NSRange?) -> Bool {
        completion.map { selection != $0 } ?? false
    }

    static func visibleRange(text: String, displayed: String, selection: NSRange, completion: NSRange?,
                             hasMarkedText: Bool, touched: Bool = false) -> NSRange? {
        guard !touched, !hasMarkedText, text == displayed, let completion, completion.length > 0, selection == completion,
              CommandBarEditState.reachesEnd(completion, of: text), isLeftToRight(text) else { return nil }
        let tail = (text as NSString).substring(from: completion.location)
        return NSRange(location: completion.location, length: tail.prefix(leadCharacters).utf16.count)
    }

    static func isLeftToRight(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF,
                 0x200F, 0x202B, 0x202E, 0x2067: return true
            default: return false
            }
        }
    }

    static func fades(text: String, textEnd: CGFloat?, visibleEnd: CGFloat, padding: CGFloat) -> Bool {
        guard !text.isEmpty, isLeftToRight(text) else { return false }
        guard let textEnd else { return true }
        return textEnd > visibleEnd + padding + 1
    }

    static func fadeWidth(fieldWidth: CGFloat, fontSize: CGFloat) -> CGFloat {
        max(0, min(fieldWidth / 2, (fontSize * 4 / 3).rounded()))
    }

    static func fadeLocations(width: CGFloat, fade: CGFloat) -> [Double] {
        guard width > 0 else { return [0, 1] }
        return [0, Double(max(0, min(1, (width - fade) / width))), 1]
    }
}

enum CommandBarCompletionTitle {
    static let separator = "— "

    static func isInline(query: String, text: String, displayed: String, selection: NSRange, completion: NSRange?,
                         hasMarkedText: Bool) -> Bool {
        guard !query.isEmpty, let range = CommandBarFieldAnchor.visibleRange(
            text: text, displayed: displayed, selection: selection, completion: completion, hasMarkedText: hasMarkedText)
        else { return false }
        return range.location > 0
    }

    static func text(title: String, url: String?, isSearch: Bool, completion: String) -> String? {
        guard !isSearch else { return nil }
        let shown = title.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shown.isEmpty, isLeftToRight(completion) else { return nil }
        let sources = [completion, url].compactMap { $0 }
        let hosts = Set(sources.compactMap(host).map(address))
        let candidate = address(shown)
        if Set(sources.map(address)).contains(candidate) || hosts.contains(candidate) { return nil }
        if !shown.contains(where: \.isWhitespace), let titleHost = host(shown).map(address), hosts.contains(titleHost) {
            return nil
        }
        return shown
    }

    static func display(_ title: String) -> String { separator + title }

    static func frame(textEnd: CGFloat, fieldEnd: CGFloat, natural: CGFloat, gap: CGFloat,
                      minimum: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        let x = textEnd + gap
        let available = fieldEnd - x
        guard natural > 0, available > 0, available >= min(natural, minimum) else { return nil }
        return (x, min(natural, available))
    }

    private static func host(_ text: String) -> String? {
        URL(string: text.contains("://") ? text : "https://" + text)?.host
    }

    private static func address(_ text: String) -> String {
        var value = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        if let scheme = value.range(of: "://") { value = value[scheme.upperBound...] }
        if value.hasPrefix("www.") { value = value.dropFirst(4) }
        while value.hasSuffix("/") || value.hasSuffix("?") { value = value.dropLast() }
        return String(value)
    }

    private static func isLeftToRight(_ text: String) -> Bool { CommandBarFieldAnchor.isLeftToRight(text) }
}
