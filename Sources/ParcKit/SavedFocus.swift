import AppKit

@MainActor
package protocol OffscreenPresenting: NSView {
    var isPresented: Bool { get }
}

extension OffscreenPresenting {
    package func presentsForEditing(reveal: (() -> Void)?) -> Bool {
        if window?.isKeyWindow == true { reveal?() }
        return isPresented
    }
    package func focusIfPresented() { if isPresented { window?.makeFirstResponder(self) } }
}

@MainActor
package enum SavedFocus {
    package static func mayReturn(to view: NSView, in window: NSWindow?) -> Bool {
        guard let window, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return false }
        var ancestor: NSView? = view
        while let container = ancestor {
            if let presenting = container as? OffscreenPresenting, !presenting.isPresented { return false }
            ancestor = container.superview
        }
        return true
    }
}
