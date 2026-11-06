import AppKit

///
/// all of which send `arc_performFindPanelAction:`. Jump to Selection carries
/// no tag (0) and Find and Replace tag 12; the browser rejects both, and only
/// a Note editor consumes them (docs/keyboard-navigation.md, KB04).
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
    ///
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

/// A Find request retains the original owner, never a later front window or page.
@MainActor final class BrowserFindCommand {
    let action: BrowserFindAction
    private weak var window: NSWindow?
    private let available: () -> Bool
    private let prepare: () -> Void
    private let execute: () -> Void
    private var consumed = false
    init(action: BrowserFindAction, window: NSWindow, available: @escaping () -> Bool,
         prepare: @escaping () -> Void = {}, execute: @escaping () -> Void) {
        self.action = action; self.window = window; self.available = available
        self.prepare = prepare; self.execute = execute
    }
    var isAvailable: Bool {
        guard !consumed, let window, window.isVisible, !window.isMiniaturized,
              window.attachedSheet == nil else { return false }
        if let input = window.firstResponder as? NSTextInputClient, input.hasMarkedText() { return false }
        return available()
    }
    @discardableResult func perform() -> Bool {
        guard isAvailable, let window else { return false }
        prepare()
        guard isAvailable, window.isKeyWindow else { return false }
        consumed = true; execute(); return true
    }
}

/// Window-local query storage is weakly bound to one real document. It never
/// uses the system Find pasteboard to seed another Profile's page.
@MainActor final class BrowserFindState<Owner: AnyObject> {
    private(set) weak var owner: Owner?
    let revision: UInt
    var query = ""
    init(owner: Owner, revision: UInt) { self.owner = owner; self.revision = revision }
    func matches(_ current: Owner?, revision: UInt) -> Bool {
        owner != nil && owner === current && self.revision == revision
    }
}
