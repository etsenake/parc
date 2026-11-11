import AppKit

@MainActor
final class SettingsFocusState {
    private final class Bookmark {
        weak var view: NSView?
        let selection: NSRange?
        init(view: NSView, selection: NSRange?) { self.view = view; self.selection = selection }
    }
    private var bookmarks: [String: Bookmark] = [:]

    func remember(in window: NSWindow, root: NSView, context: String) {
        let responder = window.firstResponder
        let editor = responder as? NSTextView
        let view = editor?.isFieldEditor == true ? editor?.delegate as? NSView : responder as? NSView
        guard let view, view === root || view.isDescendant(of: root) else { return }
        bookmarks[context] = Bookmark(view: view, selection: editor?.isFieldEditor == true ? editor?.selectedRange() : nil)
    }

    @discardableResult
    func restore(in window: NSWindow, root: NSView, context: String?, fallback: NSView? = nil) -> Bool {
        guard window.isVisible, window.isKeyWindow, NSApp.isActive,
              window.attachedSheet == nil, root.window === window else { return false }
        let bookmark = context.flatMap { bookmarks[$0] }
        let candidate = bookmark?.view
        let target = candidate.flatMap { Self.isAvailable($0, in: root, window: window) ? $0 : nil }
            ?? fallback.flatMap { Self.isAvailable($0, in: root, window: window) ? $0 : nil }
            ?? Self.controls(in: root).first { Self.isAvailable($0, in: root, window: window) && $0.canBecomeKeyView }
        guard let target, window.makeFirstResponder(target) else { return false }
        target.scrollToVisible(target.bounds)
        if target === candidate, let range = bookmark?.selection,
           let field = target as? NSTextField, let editor = field.currentEditor() as? NSTextView {
            let length = (editor.string as NSString).length
            let location = min(range.location, length)
            editor.setSelectedRange(NSRange(location: location, length: min(range.length, length - location)))
        }
        return true
    }

    static func cancelAttachedSheets(of parent: NSWindow) {
        guard let sheet = parent.attachedSheet else { return }
        cancelAttachedSheets(of: sheet)
        parent.endSheet(sheet, returnCode: .cancel)
        sheet.orderOut(nil)
    }

    func forget() { bookmarks.removeAll() }

    static func isAvailable(_ view: NSView, in root: NSView, window: NSWindow) -> Bool {
        view.window === window && (view === root || view.isDescendant(of: root))
            && !view.isHiddenOrHasHiddenAncestor && (view as? NSControl)?.isEnabled != false
            && view.acceptsFirstResponder
    }

    static func controls(in root: NSView) -> [NSView] {
        if let field = root as? NSTextField { return field.isEditable || field.isSelectable ? [field] : [] }
        if root is NSControl { return [root] }
        if let scroll = root as? NSScrollView { return scroll.documentView.map { controls(in: $0) } ?? [] }
        let children = root.subviews.enumerated().sorted { lhs, rhs in
            let leftY = root.isFlipped ? lhs.element.frame.minY : -lhs.element.frame.maxY
            let rightY = root.isFlipped ? rhs.element.frame.minY : -rhs.element.frame.maxY
            if leftY != rightY { return leftY < rightY }
            if lhs.element.frame.minX != rhs.element.frame.minX { return lhs.element.frame.minX < rhs.element.frame.minX }
            return lhs.offset < rhs.offset
        }
        return children.flatMap { controls(in: $0.element) }
    }

    static func connectKeyViews(in root: NSView) {
        let controls = controls(in: root)
        guard !controls.isEmpty else { return }
        for (index, control) in controls.enumerated() { control.nextKeyView = controls[(index + 1) % controls.count] }
    }
}

@MainActor
final class SettingsNativeWindow: NSWindow {
    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSWindow.toggleToolbarShown(_:)) { return false }
        return super.responds(to: selector)
    }
}
