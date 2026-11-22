import Foundation

struct CommandBarEditState {
    struct Projection: Equatable {
        let resultID: String
        let text: String
        var accepted: Bool
        var automatic: Bool
    }
    private(set) var query: String
    private(set) var projection: Projection?
    private(set) var allowsInlineCompletion = false
    var displayedText: String { projection?.text ?? query }

    init(query: String) { self.query = query }

    mutating func edit(_ value: String) {
        query = value
        projection = nil
        allowsInlineCompletion = false
    }

    mutating func userEdit(_ value: String, selection: NSRange, hasMarkedText: Bool, didBackspace: Bool) {
        edit(value)
        allowsInlineCompletion = !value.isEmpty && !hasMarkedText && !didBackspace &&
            Self.reachesEnd(selection, of: value)
    }

    static func deletesCharacters(editedRange: NSRange, changeInLength: Int) -> Bool {
        changeInLength < 0 && editedRange.length == 0
    }

    static func reachesEnd(_ range: NSRange, of text: String) -> Bool {
        let count = (text as NSString).length
        return range.location != NSNotFound && range.location <= count &&
            range.length <= count - range.location && range.location + range.length == count
    }

    mutating func stopAutomaticCompletion() { allowsInlineCompletion = false }

    @discardableResult
    mutating func projectInline(resultID: String, text: String, selection: NSRange, hasMarkedText: Bool) -> Bool {
        guard allowsInlineCompletion, !hasMarkedText, !query.isEmpty,
              text.hasPrefix(query), text != query, Self.reachesEnd(selection, of: displayedText),
              projection?.accepted != true else { return false }
        project(resultID: resultID, text: text, automatic: true)
        return true
    }

    mutating func project(resultID: String, text: String, automatic: Bool = false) {
        guard !text.isEmpty else { projection = nil; return }
        let accepted = projection?.resultID == resultID && projection?.text == text && projection?.accepted == true
        projection = Projection(resultID: resultID, text: text, accepted: accepted, automatic: automatic)
    }

    mutating func clearProjection() { projection = nil }
    mutating func accept() { projection?.accepted = true }

    var selection: NSRange {
        let text = displayedText as NSString
        guard let projection, !projection.accepted else {
            return NSRange(location: text.length, length: 0)
        }
        let prefix = text.range(of: query, options: [.anchored, .caseInsensitive])
        if !query.isEmpty, prefix.location == 0 {
            return NSRange(location: NSMaxRange(prefix), length: text.length - NSMaxRange(prefix))
        }
        return NSRange(location: 0, length: text.length)
    }
}
