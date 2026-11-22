import AppKit

enum BrowserFindAction: Int, CaseIterable {
    case jumpToSelection = 0, show = 1, next = 2, previous = 3, useSelection = 7, replace = 12
    var title: String {
        switch self {
        case .show: return "Find…"
        case .replace: return "Find and Replace"
        case .next: return "Find Next"
        case .previous: return "Find Previous"
        case .useSelection: return "Use Selection to Find"
        case .jumpToSelection: return "Jump to Selection"
        }
    }
    var isNativeTextOnly: Bool { self == .jumpToSelection || self == .replace }
    static func fieldAction(_ selector: Selector, shift: Bool, composing: Bool) -> BrowserFindAction? {
        guard !composing else { return nil }
        switch NSStringFromSelector(selector) {
        case "insertNewline:": return shift ? .previous : .next
        case "moveUp:": return .previous
        case "moveDown:": return .next
        default: return nil
        }
    }
}
