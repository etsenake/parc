import AppKit

struct EaselZoomInteraction {
    let initial: CGFloat
    private(set) var previous: CGFloat

    init?(zoom: CGFloat) {
        guard zoom.isFinite, zoom > 0 else { return nil }
        initial = zoom; previous = zoom
    }

    mutating func record(_ zoom: CGFloat) -> Bool {
        guard zoom.isFinite, zoom > 0 else { return false }
        defer { previous = zoom }
        return (initial < 0.99 && previous < 1 && zoom >= 1) ||
               (initial > 1.01 && previous > 1 && zoom <= 1)
    }
}

@MainActor
final class EaselCanvasMotion: NSObject {
    static let annotationDuration: TimeInterval = 0.1
    private weak var owner: NSView?
    private weak var scroll: NSScrollView?
    private weak var interactionWindow: NSWindow?
    private var interaction: EaselZoomInteraction?
    private let validOwner: () -> Bool
    private let changed: () -> Void
    private let settleAnnotations: () -> Void
    private let feedback: () -> Void
    var isInteracting: Bool { interaction != nil }
    private(set) var allowsAnnotationAnimation = true

    init(owner: NSView, validOwner: @escaping () -> Bool,
         changed: @escaping () -> Void, settleAnnotations: @escaping () -> Void,
         feedback: @escaping () -> Void = {
             NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
         }) {
        self.owner = owner; self.validOwner = validOwner; self.changed = changed
        self.settleAnnotations = settleAnnotations; self.feedback = feedback
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func bind(_ next: NSScrollView?) {
        guard next !== scroll else { return }
        cancel()
        NotificationCenter.default.removeObserver(self)
        scroll = next
        guard let next else { return }
        next.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(began),
            name: NSScrollView.willStartLiveMagnifyNotification, object: next)
        NotificationCenter.default.addObserver(self, selector: #selector(ended),
            name: NSScrollView.didEndLiveMagnifyNotification, object: next)
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: next.contentView)
    }

    private var eligible: Bool {
        guard let owner, let scroll, owner.enclosingScrollView === scroll,
              let window = owner.window, window === scroll.window,
              !owner.isHiddenOrHasHiddenAncestor, validOwner() else { return false }
        return window.isKeyWindow && window.attachedSheet == nil
    }

    @objc private func began(_ notification: Notification) {
        guard notification.object as? NSScrollView === scroll, eligible, let scroll else { cancel(); return }
        interaction = EaselZoomInteraction(zoom: scroll.magnification)
        interactionWindow = owner?.window
        changed()
    }

    @objc private func boundsChanged(_ notification: Notification) {
        guard notification.object as? NSClipView === scroll?.contentView else { return }
        guard eligible, interactionWindow === owner?.window else { cancel(); return }
        guard let scroll, var current = interaction else { return }
        let emit = current.record(scroll.magnification)
        interaction = current
        if emit { feedback() }
        changed()
    }

    @objc private func ended(_ notification: Notification) {
        guard notification.object as? NSScrollView === scroll else { return }
        cancel(animated: eligible && interactionWindow === owner?.window)
    }

    func cancel(animated: Bool = false) {
        let wasInteracting = isInteracting
        allowsAnnotationAnimation = animated
        interaction = nil; interactionWindow = nil
        if wasInteracting { changed() }
        if !animated { settleAnnotations() }
        allowsAnnotationAnimation = true
    }

    @objc private func accessibilityChanged(_ notification: Notification) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { settleAnnotations() }
    }

    static func setAnnotationHidden(_ hidden: Bool, view: NSView, animated: Bool) {
        guard view.isHidden != hidden else { return }
        NSAnimationContext.runAnimationGroup { context in
            let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = animate ? annotationDuration : 0
            context.allowsImplicitAnimation = animate
            view.isHidden = hidden
        }
    }

    static func settle(_ view: NSView) {
        view.layer?.removeAllAnimations()
        for child in view.subviews { settle(child) }
    }
}
