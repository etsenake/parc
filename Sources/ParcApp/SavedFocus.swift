import AppKit

/// A container that waits unhidden off-screen while it is not presented, as the
/// hidden sidebar does. AppKit still lets its views take focus there [C].
@MainActor
protocol OffscreenPresenting: NSView {
    var isPresented: Bool { get }
}

extension OffscreenPresenting {
    /// Whether an edit may begin inside it. In a key window `reveal` runs first
    /// whatever the presentation: the owner floats a hidden one in and settles
    /// any motion, since a hide still in motion reports presented until it ends.
    func presentsForEditing(reveal: (() -> Void)?) -> Bool {
        if window?.isKeyWindow == true { reveal?() }
        return isPresented
    }
    /// Takes focus for its own keyboard commands only while presented: one that
    /// is not refuses it, and makeFirstResponder would still move focus from the
    /// page to the window [C].
    func focusIfPresented() { if isPresented { window?.makeFirstResponder(self) } }
}

/// The one test for focus a panel or session saved and restores later: the
/// command bars, Space creation's cancel, navigation history, Easel web input,
/// sidebar previews and the sidebar window move. A hidden view, a view in
/// another window and a view inside a container that is not presented take no
/// restored focus; each owner then keeps its own fallback.
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
