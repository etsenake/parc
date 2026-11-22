import AppKit

@MainActor enum BlockedContentSign {
    static let pillSide: CGFloat = 28
    static let toolbarTitleRoom: CGFloat = 60
    static let restingAlpha: CGFloat = 0.6
    static let help = "Show what this page tried to open"
    static let hoverDuration: TimeInterval = 0.18
    static let revealDuration: TimeInterval = 0.2

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func emphasize(_ view: NSView, hovered: Bool) {
        let alpha = hovered ? 1 : restingAlpha
        guard !reduceMotion, view.window != nil else { view.alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hoverDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = alpha
        }
    }

    static func reveal(_ view: NSView, animated: Bool, alpha target: CGFloat? = nil) {
        let alpha = target ?? restingAlpha
        view.isHidden = false
        guard animated, !reduceMotion, view.window != nil else { view.alphaValue = alpha; return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = alpha
        }
    }
}
