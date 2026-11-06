import AppKit

///
/// owns one passive `CAShapeLayer` above its content. The window state decides
/// whether it is shown (focused split pane, or the proposed replacement drop
/// target) and its width; this owner only presents that state.
@MainActor
final class SplitPaneHighlight {
    ///
    static let transitionDuration: TimeInterval = 0.11
    let layer = CAShapeLayer()
    private(set) var display = false
    private(set) var width: CGFloat = 2
    private var published = false
    private let followKey = "Split pane highlight layout"
    var color: NSColor? { didSet { guard color != oldValue else { return }; refreshColor() } }
    private weak var host: NSView?

    init() {
        //
        layer.fillColor = nil
        layer.lineJoin = .round
        layer.lineCap = .round
        layer.zPosition = 8
        layer.opacity = 0
        layer.name = "Split pane highlight"
    }

    func attach(to view: NSView) {
        view.wantsLayer = true
        guard let parent = view.layer, layer.superlayer !== parent else { return }
        host = view
        CATransaction.begin(); CATransaction.setDisableActions(true)
        parent.addSublayer(layer)
        CATransaction.commit()
        refreshColor()
    }

    ///
    /// rectangle of the same bounds with the view's corner radius.
    func layout(bounds: NSRect, cornerRadius: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.path = Self.path(for: CGRect(origin: .zero, size: bounds.size), cornerRadius: cornerRadius)
        CATransaction.commit()
    }

    static func path(for rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        let radius = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    ///
    /// previously published value; a width-only change applies immediately.
    func update(display: Bool, width: CGFloat) {
        guard !published || display != self.display || width != self.width else { return }
        let animated = published && display != self.display && host?.window != nil
            && host?.isHiddenOrHasHiddenAncestor == false
        published = true; self.display = display; self.width = width
        //
        // clipped by the rounded content host); opacity is one or zero.
        let apply = { [layer] in
            layer.lineWidth = width * 2
            layer.opacity = display ? 1 : 0
        }
        guard animated else {
            CATransaction.begin(); CATransaction.setDisableActions(true); apply(); CATransaction.commit()
            return
        }
        //
        // animation allowed and duration 0.11, using the context's default timing.
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            context.duration = Self.transitionDuration
            apply()
        }
    }

    ///
    /// bounds animation for `path`, so the border stays on the moving edge.
    func followLayout(from previous: CGRect, animation: CAAnimation) {
        guard let path = layer.path, previous.size != layer.bounds.size else { return }
        let radius = host?.layer?.cornerRadius ?? 0
        let motion = CABasicAnimation(keyPath: "path")
        motion.fromValue = Self.path(for: CGRect(origin: .zero, size: previous.size), cornerRadius: radius)
        motion.toValue = path
        motion.duration = animation.duration
        motion.timingFunction = animation.timingFunction
        motion.beginTime = animation.beginTime
        layer.add(motion, forKey: followKey)
    }

    func cancelFollow() { layer.removeAnimation(forKey: followKey) }

    func refreshColor() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let color {
            let resolve = { [layer] in layer.strokeColor = color.cgColor }
            if let host { host.effectiveAppearance.performAsCurrentDrawingAppearance(resolve) } else { resolve() }
        } else { layer.strokeColor = nil }
        CATransaction.commit()
    }
}

///
struct SplitPaneHighlightState: Equatable {
    var display: Bool
    var width: CGFloat

    /// `proposedWindowContentDropTarget == contentID` shows a three-point
    /// border; the focused content of a multi-pane split shows two points
    /// while no interactive pane edit (drag and drop) is active.
    static func resolve(isProposedDropTarget: Bool, isFocused: Bool, paneCount: Int,
                        dragEditActive: Bool) -> SplitPaneHighlightState {
        let focused = isFocused && paneCount > 1 && !dragEditActive
        return SplitPaneHighlightState(display: isProposedDropTarget || focused,
                                       width: isProposedDropTarget ? 3 : 2)
    }
}
