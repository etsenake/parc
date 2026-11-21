import AppKit
import ParcCore

@MainActor
final class EaselCanvasOnboardingState {
    static let quickCreateHintKey = "easel.quickCreateHintSeen"
    static let hintLifetime: TimeInterval = 8
    var emptyState: EaselCanvasEmptyStateView?
    var hint: EaselQuickCreateHintView?
    var hintItem: UUID?
    var hintGeneration = 0
    var sawObjects = false
    var templateRow: EaselEmptyStateRow? {
        didSet { emptyState?.row = templateRow }
    }
    var defaults: UserDefaults = .standard
    var hintSeen = false
}

@MainActor
final class EaselQuickCreateHintView: NSView {
    static let text = "Tip: click a + beside it to make the next one, or press ⌘↩"
    private static let font = NoteTheme.chromeFont(13)
    private static let height: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applySurface()
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Tip: click a plus beside it to make the next one, or press Command-Return")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var preferredSize: NSSize {
        let width = ceil((Self.text as NSString).size(withAttributes: [.font: Self.font]).width)
        return NSSize(width: width + 32, height: Self.height)
    }

    private func applySurface() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            EaselAppearance.configureSurface(layer)
            layer?.cornerRadius = Self.height / 2
            EaselAppearance.configureFloatingShadow(layer, dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySurface()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NoteTheme.menuInk]
        let size = (Self.text as NSString).size(withAttributes: attributes)
        (Self.text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

extension EaselCanvasView {
    func refreshOnboarding() {
        refreshEmptyState()
        refreshQuickCreateHint()
    }

    private var showsEmptyState: Bool {
        session.document.items.isEmpty && editor == nil && fixedCanvasSize == nil && !session.isDeleted && !usesObjectSurfaces
    }

    private func refreshEmptyState() {
        let shows = showsEmptyState
        if !session.document.items.isEmpty { onboarding.sawObjects = true }
        if shows, onboarding.emptyState == nil {
            let view = EaselCanvasEmptyStateView(frame: .zero)
            view.onAction = { [weak self] action in self?.performEmptyStateAction(action) }
            view.setPresented(false, animated: false)
            onboarding.emptyState = view
        }
        guard let view = onboarding.emptyState else { return }
        if shows {
            if view.superview !== self { addSubview(view, positioned: .below, relativeTo: nil) }
            if view.row?.view !== onboarding.templateRow?.view { view.row = onboarding.templateRow }
            view.showsFindAnything = toolState.onQuickActions != nil
            let visible = visibleRect.isEmpty ? bounds : visibleRect
            let width = max(180, min(EaselCanvasEmptyStateView.maximumWidth, visible.width - 80))
            let origin = EaselCanvasEmptyStateView.origin
            let scale = max(CGFloat(magnification), 0.01)
            let viewport = enclosingScrollView?.contentSize.height ?? visible.height * scale
            let covered = CGFloat(EaselFloatingBar.cover(Double(toolState.coveredBottom), viewportHeight: Double(viewport)))
            view.availableHeight = max(0, (viewport - covered) / scale - origin.y)
            let next = NSRect(x: origin.x, y: origin.y, width: EaselCanvasEmptyStateView.frameWidth(content: width), height: view.fittedHeight(width: width))
            if view.frame != next { view.frame = next }
            if !view.isPresented { keyboardStructureChanged() }
            view.setPresented(true, animated: window != nil && onboarding.sawObjects)
        } else if view.superview != nil {
            let animated = window != nil && !usesObjectSurfaces
            if view.isPresented { keyboardStructureChanged() }
            view.setPresented(false, animated: animated)
            if !animated { view.removeFromSuperview() }
        }
    }

    private func performEmptyStateAction(_ action: EaselEmptyStateAction) {
        guard !session.isClosed, !session.isDeleted else { return }
        switch action {
        case .tool(let next):
            window?.makeFirstResponder(self)
            tool = next
        case .findAnything:
            toolState.onQuickActions?()
        }
    }

    private func refreshQuickCreateHint() {
        if let shown = onboarding.hintItem {
            if quickCreateSource?.id != shown || start != nil || !canAnimateObjects { dismissQuickCreateHint() }
            return
        }
        guard !onboarding.hintSeen, fixedCanvasSize == nil else { return }
        if onboarding.defaults.bool(forKey: EaselCanvasOnboardingState.quickCreateHintKey) { onboarding.hintSeen = true; return }
        guard let source = quickCreateSource, start == nil, canAnimateObjects, window?.isKeyWindow == true,
              let scroll = enclosingScrollView, let container = scroll.superview else { return }
        onboarding.hintSeen = true
        onboarding.defaults.set(true, forKey: EaselCanvasOnboardingState.quickCreateHintKey)
        let hint = EaselQuickCreateHintView(frame: .zero)
        let size = hint.preferredSize
        let area = scroll.frame
        let covered = toolState.coveredBottom
        let lift = covered > 0 ? covered - CGFloat(EaselFloatingBar.clearance) + CGFloat(EaselFloatingBar.chipGap) : 20
        let y = container.isFlipped ? area.maxY - size.height - lift : area.minY + lift
        hint.frame = NSRect(x: (area.midX - size.width / 2).rounded(), y: y.rounded(), width: size.width, height: size.height)
        hint.autoresizingMask = container.isFlipped ? [.minXMargin, .maxXMargin, .minYMargin] : [.minXMargin, .maxXMargin, .maxYMargin]
        container.addSubview(hint, positioned: .above, relativeTo: scroll)
        onboarding.hint = hint
        onboarding.hintItem = source.id
        onboarding.hintGeneration &+= 1
        presentQuickCreateHint(hint, visible: true)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: hint.accessibilityLabel() ?? "", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        let generation = onboarding.hintGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + EaselCanvasOnboardingState.hintLifetime) { [weak self] in
            guard let self, self.onboarding.hintGeneration == generation else { return }
            self.dismissQuickCreateHint()
        }
    }

    func dismissQuickCreateHint() {
        guard let hint = onboarding.hint else { onboarding.hintItem = nil; return }
        onboarding.hint = nil
        onboarding.hintGeneration &+= 1
        presentQuickCreateHint(hint, visible: false)
    }

    private func presentQuickCreateHint(_ hint: EaselQuickCreateHintView, visible: Bool) {
        guard let layer = hint.layer, hint.window != nil else {
            if !visible { hint.removeFromSuperview() }
            return
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let center = CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x), y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
        var shrunk = CATransform3DMakeTranslation(center.x, center.y, 0)
        shrunk = CATransform3DScale(shrunk, 0.95, 0.95, 1)
        shrunk = CATransform3DTranslate(shrunk, -center.x, -center.y, 0)
        let curve = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        CATransaction.begin()
        if !visible { CATransaction.setCompletionBlock { [weak hint] in MainActor.assumeIsolated { hint?.removeFromSuperview() } } }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = visible ? 0 : 1; fade.toValue = visible ? 1 : 0
        fade.duration = visible ? 0.1 : 0.07; fade.timingFunction = curve
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = visible
        layer.add(fade, forKey: "parc.easel.hint.fade")
        if !reduced {
            let pop = CABasicAnimation(keyPath: "transform")
            pop.fromValue = NSValue(caTransform3D: visible ? shrunk : CATransform3DIdentity)
            pop.toValue = NSValue(caTransform3D: visible ? CATransform3DIdentity : shrunk)
            pop.duration = fade.duration; pop.timingFunction = curve
            pop.fillMode = .forwards; pop.isRemovedOnCompletion = visible
            layer.add(pop, forKey: "parc.easel.hint.pop")
        }
        CATransaction.commit()
        if !visible { onboarding.hintItem = nil }
    }
}
