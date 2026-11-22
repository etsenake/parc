import AppKit

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

@MainActor final class BrowserFindState<Owner: AnyObject> {
    private(set) weak var owner: Owner?
    let revision: UInt
    var query = ""
    init(owner: Owner, revision: UInt) { self.owner = owner; self.revision = revision }
    func matches(_ current: Owner?, revision: UInt) -> Bool {
        owner != nil && owner === current && self.revision == revision
    }
}
