import AppKit

@MainActor
protocol OffscreenPresenting: NSView {
    var isPresented: Bool { get }
}

extension OffscreenPresenting {
    func presentsForEditing(reveal: (() -> Void)?) -> Bool {
        if window?.isKeyWindow == true { reveal?() }
        return isPresented
    }
    func focusIfPresented() { if isPresented { window?.makeFirstResponder(self) } }
}

@MainActor
enum SavedFocus {
    static func mayReturn(to view: NSView, in window: NSWindow?) -> Bool {
        guard let window, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return false }
        var ancestor: NSView? = view
        while let container = ancestor {
            if let presenting = container as? OffscreenPresenting, !presenting.isPresented { return false }
            ancestor = container.superview
        }
        return true
    }
}
