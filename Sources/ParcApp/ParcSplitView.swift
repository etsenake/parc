import AppKit

struct SplitDividerSnapState {
    private(set) var canSnap = false
    private(set) var isSnapped = false
    mutating func update(distance: Double, velocity: Double) -> Bool {
        guard distance.isFinite, velocity.isFinite else { return false }
        let previous = isSnapped
        if abs(distance) >= 14 { canSnap = true; isSnapped = false }
        else if canSnap, !isSnapped, abs(velocity) <= 120,
                (distance < 0) == (velocity >= 0) { isSnapped = true }
        return previous != isSnapped
    }
}
final class ParcSplitView: NSView, NSGestureRecognizerDelegate {
    private(set) var arrangedSubviews: [NSView] = []
    private(set) var isVertical = true
    func addArrangedSubview(_ view: NSView) { insertArrangedSubview(view, at: arrangedSubviews.count) }
    func insertArrangedSubview(_ view: NSView, at index: Int) {
        guard index >= 0, index <= arrangedSubviews.count,
              !arrangedSubviews.contains(where: { $0 === view }) else { return }
        retireDropReservation()
        arrangedSubviews.insert(view, at: index)
        let previous = index > 0 ? arrangedSubviews[index - 1] : nil
        addSubview(view, positioned: previous == nil ? .below : .above, relativeTo: previous)
    }
    @discardableResult
    func reconcileArrangedSubviews(_ views: [NSView]) -> [NSView] {
        let leaving = arrangedSubviews.filter { current in !views.contains { $0 === current } }
        let alreadyMatched = leaving.isEmpty
            && arrangedSubviews.count == views.count
            && zip(arrangedSubviews, views).allSatisfy { $0 === $1 }
        guard !alreadyMatched else { return [] }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for view in leaving { removeArrangedSubview(view) }
        for (index, view) in views.enumerated() {
            if index < arrangedSubviews.count, arrangedSubviews[index] === view { continue }
            if let current = arrangedSubviews.firstIndex(where: { $0 === view }) {
                arrangedSubviews.remove(at: current)
                arrangedSubviews.insert(view, at: index)
                let previous = index > 0 ? arrangedSubviews[index - 1] : nil
                addSubview(view, positioned: previous == nil ? .below : .above, relativeTo: previous)
            } else {
                insertArrangedSubview(view, at: index)
            }
        }
        return leaving
    }
    func removeArrangedSubview(_ view: NSView) {
        guard arrangedSubviews.contains(where: { $0 === view }) else { return }
        retireDropReservation()
        finishDividerResize(commit: false)
        arrangedSubviews.removeAll { $0 === view }
        synchronizePaneShadows()
    }
    override func willRemoveSubview(_ subview: NSView) {
        removeArrangedSubview(subview)
        super.willRemoveSubview(subview)
    }
    fileprivate final class DropRegionView: NSView {
        var insertionColor: (() -> NSColor)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func refreshAppearance() {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.borderWidth = 2; layer?.cornerRadius = 6
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.borderColor = insertionColor?().withAlphaComponent(0.5).cgColor
            }
            CATransaction.commit()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance(); refreshAppearance()
        }
    }
    final class DropReservation {
        private weak var owner: ParcSplitView?
        private weak var host: NSView?
        private weak var window: NSWindow?
        private let panes: [NSView]
        private let contents: [NSView]
        private let originalOrientation: SplitOrientation
        private let originalFactors: [Double]
        private let hostBounds: NSRect
        private let hostFrame: NSRect
        private let windowFrame: NSRect
        private let scale: CGFloat
        private var splitFrame: NSRect
        private var splitBounds: NSRect
        private var paneFrames: [NSRect]
        private var contentFrames: [NSRect]
        private var paneHostFrames: [NSRect]
        private var updating = false
        private(set) var ended = false
        fileprivate let region = DropRegionView()
        fileprivate var index: Int?
        fileprivate var orientation: SplitOrientation
        private var target: SplitDropTarget?
        private(set) var reusedRegion = false
        private var retiredIndex: Int?
        func setInsertionColor(_ color: @escaping () -> NSColor) {
            region.insertionColor = color; region.refreshAppearance()
        }
        func refreshAppearance() { region.refreshAppearance() }
        func beginInteractivePaneEdit() -> InteractivePaneEdit? {
            guard !ended, let owner, owner.dropReservation === self else { return nil }
            return owner.beginInteractivePaneEdit()
        }

        fileprivate init(owner: ParcSplitView, host: NSView, contents: [NSView]) {
            self.owner = owner; self.host = host; window = owner.window
            panes = owner.arrangedSubviews; self.contents = contents
            originalOrientation = owner.savedOrientation; orientation = owner.savedOrientation
            originalFactors = owner.savedFactors
            hostBounds = host.bounds; hostFrame = host.frame; windowFrame = owner.window?.frame ?? .zero
            scale = owner.paneBackingScale; splitFrame = owner.frame; splitBounds = owner.bounds
            paneFrames = panes.map(\.frame)
            contentFrames = contents.map { $0.convert($0.bounds, to: host) }
            paneHostFrames = panes.map { $0.convert($0.bounds, to: host) }
            region.wantsLayer = true; region.setAccessibilityElement(false); region.setAccessibilityChildren([])
        }
        var incomingPaneSize: NSSize {
            NSSize(width: splitBounds.width / CGFloat(panes.count + 1), height: splitBounds.height)
        }
        var isCurrent: Bool {
            guard !ended, let owner, let host, let window, owner.dropReservation === self,
                  owner.window === window, host.window === window, owner.isDescendant(of: host),
                  host.bounds == hostBounds, host.frame == hostFrame, window.frame == windowFrame,
                  owner.paneBackingScale == scale, owner.savedOrientation == originalOrientation,
                  owner.savedFactors == originalFactors, panes.count == owner.arrangedSubviews.count,
                  zip(panes, owner.arrangedSubviews).allSatisfy({ $0 === $1 }),
                  contents.enumerated().allSatisfy({ $0.element.isDescendant(of: panes[$0.offset]) }) else { return false }
            if updating { return true }
            return owner.frame == splitFrame && owner.bounds == splitBounds
                && panes.map(\.frame) == paneFrames
                && contents.map({ $0.convert($0.bounds, to: host) }) == contentFrames
        }
        private func capture() {
            guard let owner, let host else { return }
            splitFrame = owner.frame; splitBounds = owner.bounds
            paneFrames = panes.map(\.frame)
            contentFrames = contents.map { $0.convert($0.bounds, to: host) }
            paneHostFrames = panes.map { $0.convert($0.bounds, to: host) }
        }
        private var regionFrame: NSRect? {
            guard index != nil, let owner, let host else { return nil }
            return owner.convert(region.frame, to: host)
        }
        func containsReservedPoint(_ point: NSPoint) -> Bool {
            isCurrent && regionFrame?.contains(point) == true
        }
        func containsHandoffPoint(_ point: NSPoint) -> Bool {
            guard isCurrent else { return false }
            if regionFrame?.contains(point) == true { return true }
            return zip(paneHostFrames, contentFrames).contains { $0.contains(point) && !$1.contains(point) }
        }
        @MainActor func proposal(at point: NSPoint, canPropose: (SplitDropTarget, SplitOrientation) -> Bool) -> SplitDropGeometry.Proposal? {
            guard isCurrent else { end(); return nil }
            reusedRegion = false
            if let target, let rect = regionFrame, rect.contains(point), canPropose(target, orientation), isCurrent {
                reusedRegion = true
                return (target, orientation, rect)
            }
            guard isCurrent else { end(); return nil }
            let proposed = SplitDropGeometry.proposal(at: point, frames: paneHostFrames,
                orientation: orientation, canPropose: canPropose)
            guard isCurrent else { end(); return nil }
            guard let proposed else { clear(animated: true); return nil }
            guard case .insert(let next) = proposed.0 else {
                clear(animated: true)
                if case .replace(let i) = proposed.0 { return (proposed.0, originalOrientation, paneHostFrames[i]) }
                return proposed
            }
            guard isCurrent, let owner, next >= 0, next <= panes.count else { end(); return nil }
            if index == next && orientation == proposed.1 { reusedRegion = true }
            else {
                reusedRegion = index == nil && retiredIndex == next && owner.retiringDropRegion === region
                let positions = owner.captureLayoutPresentation()
                let visible = owner.captureDropRegion(region)
                let collapsed = collapsedFrame(at: next, orientation: proposed.1)
                owner.clearRetiringDropRegion()
                updating = true
                index = next; orientation = proposed.1; target = proposed.0
                if region.superview !== owner { owner.addSubview(region) }
                region.frame = collapsed; region.layer?.opacity = 0
                let start = visible ?? owner.captureDropRegion(region)
                owner.applyDropReserveLayout()
                capture(); updating = false
                if isCurrent {
                    owner.animateReservedLayout(from: positions)
                    owner.presentDropRegion(region, from: start, opacity: 1, removing: false)
                }
            }
            guard isCurrent, let rect = regionFrame else { end(); return nil }
            return (proposed.0, proposed.1, rect)
        }
        private func collapsedFrame(at index: Int, orientation: SplitOrientation) -> NSRect {
            guard let owner else { return .zero }
            let horizontal = orientation == .horizontal
            let edge: CGFloat
            if index == 0 { edge = 0 }
            else if index >= panes.count { edge = horizontal ? panes.last!.frame.maxX : panes.last!.frame.maxY }
            else { edge = horizontal ? panes[index].frame.minX : panes[index].frame.minY }
            return horizontal
                ? NSRect(x: edge, y: 0, width: 0, height: owner.bounds.height)
                : NSRect(x: 0, y: edge, width: owner.bounds.width, height: 0)
        }
        func clear(animated: Bool = false) {
            guard let owner, owner.dropReservation === self, !ended else { return }
            guard let previousIndex = index else {
                if !animated { owner.clearLayoutAnimation() }
                return
            }
            let animate = animated && isCurrent
            let positions = animate ? owner.captureLayoutPresentation() : []
            let border = animate ? owner.captureDropRegion(region) : nil
            let previousOrientation = orientation
            updating = true; index = nil; target = nil; orientation = originalOrientation
            region.removeFromSuperview(); owner.applyDropReserveLayout()
            capture(); updating = false
            guard isCurrent else { return }
            owner.animateReservedLayout(from: positions)
            if animate, let border {
                region.frame = collapsedFrame(at: previousIndex, orientation: previousOrientation)
                owner.addSubview(region)
                retiredIndex = previousIndex
                owner.presentDropRegion(region, from: border, opacity: 0, removing: true)
            }
        }
        func end(animated: Bool = false) {
            guard !ended else { return }
            let current = isCurrent
            let animate = animated && current
            let positions = animate ? owner?.captureLayoutPresentation() ?? [] : []
            let border = animate ? owner?.captureDropRegion(region) : nil
            let previousIndex = index, previousOrientation = orientation
            ended = true
            guard let owner, owner.dropReservation === self else { region.removeFromSuperview(); return }
            owner.dropReservation = nil
            if animate, previousIndex == nil { return }
            region.removeFromSuperview()
            owner.applyDropReserveLayout()
            if animate {
                owner.animateReservedLayout(from: positions)
                if let previousIndex, let border {
                    region.frame = collapsedFrame(at: previousIndex, orientation: previousOrientation)
                    owner.addSubview(region)
                    owner.presentDropRegion(region, from: border, opacity: 0, removing: true)
                }
            }
        }
    }

    private var dropReservation: DropReservation?
    func prepareDropReservation(in host: NSView, contents: [NSView]) -> DropReservation? {
        guard dropReservation == nil, !isTrackingDivider, window != nil,
              isDescendant(of: host), !arrangedSubviews.isEmpty, contents.count == arrangedSubviews.count,
              contents.enumerated().allSatisfy({ $0.element.isDescendant(of: arrangedSubviews[$0.offset]) }) else { return nil }
        clearRetiringDropRegion()
        let lease = DropReservation(owner: self, host: host, contents: contents)
        dropReservation = lease
        return lease
    }
    private func retireDropReservation() { dropReservation?.end() }
    @MainActor final class InteractivePaneEdit {
        fileprivate weak var owner: ParcSplitView?
        private(set) var ended = false
        private var fallback: Timer?
        fileprivate init(owner: ParcSplitView) { self.owner = owner }
        var isDragInside = true { didSet { updateFallback() } }
        private func updateFallback() {
            guard !ended, !isDragInside else { fallback?.invalidate(); fallback = nil; return }
            guard fallback == nil else { return }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    self.endIfDragReleased()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            fallback = timer
        }
        func endIfDragReleased() {
            guard !ended, !isDragInside, owner?.primaryMouseButtonIsDown() != true else { return }
            end()
        }
        func end() {
            guard !ended else { return }
            ended = true
            fallback?.invalidate(); fallback = nil
            owner?.interactivePaneEditDidEnd(self)
        }
    }
    var primaryMouseButtonIsDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    private var interactivePaneEdit: InteractivePaneEdit?
    var isInteractivePaneEditing: Bool { interactivePaneEdit != nil }
    var onInteractivePaneEditing: ((Bool) -> Void)?
    fileprivate func beginInteractivePaneEdit() -> InteractivePaneEdit? {
        guard window != nil else { return nil }
        let previous = interactivePaneEdit
        let edit = InteractivePaneEdit(owner: self)
        interactivePaneEdit = edit
        previous?.owner = nil; previous?.end()
        if previous == nil { onInteractivePaneEditing?(true) }
        return edit
    }
    fileprivate func interactivePaneEditDidEnd(_ edit: InteractivePaneEdit) {
        guard interactivePaneEdit === edit else { return }
        interactivePaneEdit = nil
        onInteractivePaneEditing?(false)
    }
    var prepareDividerResize: (() -> (([Double]) -> Bool)?)?
    private var dividerGrips: [CALayer] = []
    private var dividerTrackingAreas: [NSTrackingArea] = []
    private var hoveredDivider: Int?
    private var resignObserver: NSObjectProtocol?
    private let layoutAnimationKey = "Split divider equalization"
    private let reservedAnimationKey = "Split reserved layout"
    private final class AnimatedLayer {
        weak var layer: CALayer?
        init(_ layer: CALayer) { self.layer = layer }
    }
    private var animatedLayers: [AnimatedLayer] = []
    private let regionAnimationKey = "Split drop region"
    private var retiringDropRegion: DropRegionView?
    private var regionTransition = UUID()
    private struct RegionPosition {
        let parent: CALayer?
        let position: CGPoint
        let bounds: CGRect
        let opacity: Float
    }
    private func captureDropRegion(_ region: DropRegionView) -> RegionPosition? {
        guard region.superview === self, let layer = region.layer else { return nil }
        let visible = layer.presentation() ?? layer
        return RegionPosition(parent: layer.superlayer, position: visible.position,
                              bounds: visible.bounds, opacity: visible.opacity)
    }
    private func clearRetiringDropRegion() {
        regionTransition = UUID()
        let previous = retiringDropRegion; retiringDropRegion = nil
        previous?.layer?.removeAnimation(forKey: regionAnimationKey)
        previous?.removeFromSuperview()
    }
    private func presentDropRegion(_ region: DropRegionView, from previous: RegionPosition?,
                                   opacity: Float, removing: Bool) {
        guard region.superview === self, let layer = region.layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        region.refreshAppearance()
        layer.removeAnimation(forKey: regionAnimationKey)
        guard let previous, previous.parent === layer.superlayer, window != nil,
              !isHiddenOrHasHiddenAncestor else {
            if removing { region.removeFromSuperview() }
            return
        }
        let token = UUID(); regionTransition = token
        if removing { retiringDropRegion = region }
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: previous.position); position.toValue = NSValue(point: layer.position)
        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: previous.bounds); bounds.toValue = NSValue(rect: layer.bounds)
        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = previous.opacity; alpha.toValue = opacity
        let animation = CAAnimationGroup()
        animation.animations = [position, bounds, alpha]; animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        if removing {
            CATransaction.setCompletionBlock { [weak self, weak region] in
                MainActor.assumeIsolated {
                    guard let self, let region, self.regionTransition == token,
                          self.retiringDropRegion === region else { return }
                    self.clearRetiringDropRegion()
                }
            }
        }
        layer.add(animation, forKey: regionAnimationKey)
        CATransaction.commit()
    }
    private struct LayerPosition {
        let layer: CALayer
        let parent: CALayer?
        let position: CGPoint
        let bounds: CGRect
    }
    private var layoutLayers: [CALayer] {
        arrangedSubviews.compactMap(\.layer) + dividerGrips + arrangedSubviews.compactMap { paneShadows[ObjectIdentifier($0)] }
    }
    private var paneShadows: [ObjectIdentifier: CALayer] = [:]
    private func synchronizePaneShadows() {
        guard let layer else { return }
        let live = Set(arrangedSubviews.map(ObjectIdentifier.init))
        for (id, shadow) in paneShadows where !live.contains(id) {
            shadow.removeFromSuperlayer(); paneShadows[id] = nil
        }
        let divided = arrangedSubviews.count > 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for pane in arrangedSubviews {
            let id = ObjectIdentifier(pane)
            let shadow: CALayer
            if let existing = paneShadows[id] {
                shadow = existing
            } else {
                shadow = CALayer()
                shadow.name = "Split pane shadow"
                shadow.zPosition = -1
                layer.addSublayer(shadow)
                paneShadows[id] = shadow
            }
            if !ContentShadowImage.isCurrent(shadow, scale: paneBackingScale) {
                ContentShadowImage.apply(to: shadow, scale: paneBackingScale)
            }
            shadow.frame = ContentShadowImage.frame(around: pane.layer?.frame ?? pane.frame)
            shadow.isHidden = !divided
        }
        CATransaction.commit()
    }
    private func captureLayoutPresentation() -> [LayerPosition] {
        layoutLayers.map { layer in
            let visible = layer.presentation() ?? layer
            return LayerPosition(layer: layer, parent: layer.superlayer,
                                 position: visible.position, bounds: visible.bounds)
        }
    }
    private func clearLayoutAnimation() {
        clearRetiringDropRegion()
        dropReservation?.region.layer?.removeAnimation(forKey: regionAnimationKey)
        for layer in animatedLayers.compactMap(\.layer) + layoutLayers {
            layer.removeAnimation(forKey: layoutAnimationKey)
            layer.removeAnimation(forKey: reservedAnimationKey)
            (layer.delegate as? SplitLayoutFollowing)?.cancelSplitLayoutFollow()
        }
        animatedLayers.removeAll()
    }
    private func animateEqualizedLayout(from positions: [LayerPosition]) {
        animateLayout(from: positions, key: layoutAnimationKey)
    }
    private func animateReservedLayout(from positions: [LayerPosition]) {
        animateLayout(from: positions, key: reservedAnimationKey)
    }
    private func animateLayout(from positions: [LayerPosition], key: String) {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        let current = layoutLayers
        for previous in positions where current.contains(where: { $0 === previous.layer })
            && previous.layer.superlayer === previous.parent {
            let layer = previous.layer
            guard previous.position != layer.position || previous.bounds != layer.bounds else { continue }
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: previous.position); position.toValue = NSValue(point: layer.position)
            let bounds = CABasicAnimation(keyPath: "bounds")
            bounds.fromValue = NSValue(rect: previous.bounds); bounds.toValue = NSValue(rect: layer.bounds)
            let animation = CAAnimationGroup()
            animation.animations = [position, bounds]; animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animatedLayers.append(AnimatedLayer(layer))
            layer.add(animation, forKey: key)
            (layer.delegate as? SplitLayoutFollowing)?.followSplitLayout(from: previous.bounds, animation: animation)
        }
    }
    private var savedOrientation: SplitOrientation = .horizontal
    private var savedFactors: [Double] = [1]
    var onSnapTransition: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    private lazy var dividerPan = NSPanGestureRecognizer(target: self, action: #selector(handleDividerPan(_:)))
    private struct Resize {
        let divider: Int
        let views: [NSView]
        let frames: [NSRect]
        let bounds: NSRect
        let orientation: SplitOrientation
        let backingScale: CGFloat
        let originalFactors: [Double]
        var origin: NSPoint
        let commit: ([Double]) -> Bool
        var snap = SplitDividerSnapState()
        var factors: [Double]
        var moved = false
    }
    private var resize: Resize?
    private var isTrackingDivider: Bool { resize != nil }
    private(set) var isDividerPanActive = false {
        didSet { if oldValue != isDividerPanActive { onDividerPanActivity?(isDividerPanActive) } }
    }
    private var isPaneInputLocked = false
    var onDividerPanActivity: ((Bool) -> Void)?
    private var isApplyingLayout = false
    override var isFlipped: Bool { true }
    var dividerColor: NSColor { .clear }
    override var isOpaque: Bool { false }
    var dividerThickness: CGFloat = 10 {
        didSet { if dividerThickness != oldValue { needsLayout = true } }
    }
    private let expandedPaneMinimum: CGFloat = 220
    private let draggableTopInset: CGFloat = 53
    private let draggableEndInset: CGFloat = 8
    private weak var constrainedHost: NSView?
    private var hostConstraints: [NSLayoutConstraint] = []
    private var minimumWidthConstraint: NSLayoutConstraint?
    private var minimumHeightConstraint: NSLayoutConstraint?

    func constrain(to host: NSView) {
        guard superview === host else { return }
        if constrainedHost !== host {
            NSLayoutConstraint.deactivate(hostConstraints)
            constrainedHost = host
            translatesAutoresizingMaskIntoConstraints = false
            let trailing = trailingAnchor.constraint(equalTo: host.trailingAnchor)
            let bottom = bottomAnchor.constraint(equalTo: host.bottomAnchor)
            trailing.priority = .defaultHigh; bottom.priority = .defaultHigh
            let width = widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
            let height = heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
            minimumWidthConstraint = width; minimumHeightConstraint = height
            hostConstraints = [leadingAnchor.constraint(equalTo: host.leadingAnchor),
                topAnchor.constraint(equalTo: host.topAnchor), trailing, bottom, width, height]
            NSLayoutConstraint.activate(hostConstraints)
        }
        updateContainerMinimum()
    }

    private func updateContainerMinimum() {
        guard let host = constrainedHost, superview === host else { return }
        let count = arrangedSubviews.count + (dropReservation?.index == nil ? 0 : 1)
        let width = count > 1 ? expandedPaneMinimum * CGFloat(count) + dividerThickness * CGFloat(count - 1) : 0
        let height: CGFloat = count > 1 ? 382 : 0
        let widthChanged = minimumWidthConstraint?.constant != width
        let heightChanged = minimumHeightConstraint?.constant != height
        if widthChanged { minimumWidthConstraint?.constant = width }
        if heightChanged { minimumHeightConstraint?.constant = height }
        if SplitLayoutFlushSkip.shouldFlush(
            frameChanged: widthChanged || heightChanged,
            needsLayout: host.needsLayout,
            subtreeNeedsLayout: host.subviews.contains(where: \.needsLayout)
        ) {
            host.layoutSubtreeIfNeeded()
        }
    }

    fileprivate func applyDropReserveLayout() {
        updateContainerMinimum()
        applySavedFrames()
        if SplitLayoutFlushSkip.shouldFlush(
            needsLayout: needsLayout,
            subtreeNeedsLayout: subviews.contains(where: \.needsLayout)
        ) {
            layoutSubtreeIfNeeded()
        }
    }


    private func alignedPaneFrame(_ frame: NSRect) -> NSRect {
        let left = frame.minX.rounded(), top = frame.minY.rounded()
        return NSRect(x: left, y: top, width: max(0, frame.maxX.rounded() - left),
                      height: max(0, frame.maxY.rounded() - top))
    }

    private var paneBackingScale: CGFloat {
        let scale = window?.backingScaleFactor ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }

    private var availablePaneLength: CGFloat {
        let total = savedOrientation == .horizontal ? bounds.width : bounds.height
        return max(0, total - dividerThickness * CGFloat(max(0, arrangedSubviews.count - 1)))
    }

    private func resizableFactors(at divider: Int) -> [Double]? {
        guard arrangedSubviews.indices.contains(divider), arrangedSubviews.indices.contains(divider + 1),
              let factors = BrowserSplitLayout.normalized(savedFactors, count: arrangedSubviews.count) else { return nil }
        guard CGFloat(factors[divider] + factors[divider + 1]) * availablePaneLength < 2 * minimumPaneLength else { return factors }
        var lengths = arrangedSubviews.map { Double(isVertical ? $0.frame.width : $0.frame.height) }
        let pair = lengths[divider] + lengths[divider + 1]
        let room = Double(availablePaneLength) - (lengths.reduce(0, +) - pair)
        guard pair > 2 * Double(minimumPaneLength), room > 2 * Double(minimumPaneLength) else { return factors }
        lengths[divider] *= room / pair; lengths[divider + 1] *= room / pair
        return BrowserSplitLayout.normalized(lengths, count: lengths.count) ?? factors
    }

    private func dividerFraction(distance: CGFloat, pairShare: Double) -> Double? {
        let available = availablePaneLength
        guard distance.isFinite, available.isFinite, available > 0 else { return nil }
        let minimum = Double(minimumPaneLength / available)
        let fraction = max(minimum, min(Double(distance / available), pairShare - minimum))
        guard fraction.isFinite, fraction > 0, pairShare - fraction > 0 else { return nil }
        return fraction
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        dividerPan.delegate = self
        dividerPan.buttonMask = 1
        dividerPan.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(dividerPan)
    }
    func refreshPaneCorners(radius: CGFloat) {
        guard arrangedSubviews.count > 1 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for pane in arrangedSubviews { pane.layer?.cornerRadius = radius }
        CATransaction.commit()
        needsLayout = true
    }

    func configureBacking(in host: NSView, hasTranslucentPane: Bool, backing: NSColor = .white) {
        let divided = arrangedSubviews.count > 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = nil
        layer?.masksToBounds = false
        host.layer?.backgroundColor = (divided || hasTranslucentPane ? NSColor.clear : backing).cgColor
        host.layer?.masksToBounds = !divided
        for pane in arrangedSubviews {
            pane.wantsLayer = true
            pane.layer?.cornerRadius = divided ? PageCard.cornerRadius : 0
            pane.layer?.cornerCurve = .continuous
            pane.layer?.masksToBounds = divided
        }
        CATransaction.commit()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
    override func viewDidHide() {
        super.viewDidHide(); retireDropReservation(); clearLayoutAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        updateDividerHover(at: nil, animated: false)
        if let window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retireDropReservation(); self?.clearLayoutAnimation(); self?.updateDividerHover(at: nil, animated: false) }
            }
        }
        if !isTrackingDivider { applySavedFrames() }
        updateTrackingAreas()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        retireDropReservation()
        if isTrackingDivider, !resizeIsCurrent { finishDividerResize(commit: false) }
        else if !isTrackingDivider { applySavedFrames() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        synchronizeDividerPresentation(animated: false)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = isVertical ? .resizeLeftRight : .resizeUpDown
        for rect in dividerRegions where !rect.isEmpty { addCursorRect(rect, cursor: cursor) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in dividerTrackingAreas { removeTrackingArea(area) }
        dividerTrackingAreas = dividerRegions.compactMap { rect in
            let visible = rect.intersection(visibleRect)
            guard !visible.isEmpty, !visible.isNull,
                  visible.minX.isFinite, visible.minY.isFinite,
                  visible.width.isFinite, visible.height.isFinite else { return nil }
            let area = NSTrackingArea(rect: visible,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .enabledDuringMouseDrag], owner: self, userInfo: nil)
            addTrackingArea(area); return area
        }
        if let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor {
            updateDividerHover(at: topmostPoint(atWindowPoint: window.mouseLocationOutsideOfEventStream), animated: false)
        } else { updateDividerHover(at: nil, animated: false) }
    }
    override func mouseEntered(with event: NSEvent) {
        guard let area = event.trackingArea, dividerTrackingAreas.contains(where: { $0 === area }),
              let window, event.window === window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        updateDividerHover(at: topmostPoint(atWindowPoint: event.locationInWindow))
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard dividerTrackingAreas.contains(where: { $0.rect.contains(point) }) else {
            super.mouseMoved(with: event); return
        }
        guard let window, event.window === window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        updateDividerHover(at: topmostPoint(atWindowPoint: event.locationInWindow))
    }
    private func topmostPoint(atWindowPoint point: NSPoint) -> NSPoint? {
        let local = convert(point, from: nil)
        return divider(at: local) != nil && isTopmost(atWindowPoint: point) ? local : nil
    }
    override func mouseExited(with event: NSEvent) {
        guard let area = event.trackingArea, dividerTrackingAreas.contains(where: { $0 === area }) else { return }
        updateDividerHover(at: nil)
    }
    func updateDividerHover(at point: NSPoint?, animated: Bool = true) {
        let next = point.flatMap { point in
            point.x.isFinite && point.y.isFinite ? divider(at: point) : nil
        }
        guard hoveredDivider != next else {
            if !animated { synchronizeDividerPresentation(animated: false) }
            return
        }
        hoveredDivider = next
        synchronizeDividerPresentation(animated: animated)
    }
    private var dividerRects: [NSRect] {
        guard dropReservation?.index == nil else { return [] }
        return arrangedSubviews.dropLast().map { pane in
            isVertical
                ? NSRect(x: pane.frame.maxX, y: 0, width: dividerThickness, height: bounds.height)
                : NSRect(x: 0, y: pane.frame.maxY, width: bounds.width, height: dividerThickness)
        }
    }
    private var dividerRegions: [NSRect] {
        dividerRects.map { rect in
            isVertical
                ? NSRect(x: rect.minX, y: rect.minY + draggableTopInset,
                         width: rect.width, height: max(0, rect.height - draggableTopInset))
                : NSRect(x: rect.minX + draggableEndInset, y: rect.minY,
                         width: max(0, rect.width - 2 * draggableEndInset), height: rect.height)
        }
    }
    weak var marginHandle: SplitMarginHandleView? { didSet { synchronizeDividerPresentation(animated: false) } }
    private func synchronizeDividerPresentation(animated: Bool) {
        marginHandle?.splitAllows = arrangedSubviews.count == 1 && dropReservation?.index == nil
        guard let layer else { return }
        let rects = dividerRects
        while dividerGrips.count > rects.count { dividerGrips.removeLast().removeFromSuperlayer() }
        while dividerGrips.count < rects.count {
            let grip = CALayer(); grip.name = "Split divider grip"; grip.cornerRadius = 1
            layer.addSublayer(grip); dividerGrips.append(grip)
        }
        if let hoveredDivider, !rects.indices.contains(hoveredDivider) { self.hoveredDivider = nil }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for (index, rect) in rects.enumerated() {
            let grip = dividerGrips[index]
            let color = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0,
                                alpha: hoveredDivider == index ? 0.5 : 0.2).cgColor
            let previous = grip.presentation()?.backgroundColor ?? grip.backgroundColor
            let changed = grip.backgroundColor != color
            CATransaction.begin(); CATransaction.setDisableActions(true)
            grip.frame = isVertical
                ? NSRect(x: rect.midX - 1, y: rect.midY - 12, width: 2, height: 24)
                : NSRect(x: rect.midX - 12, y: rect.midY - 1, width: 24, height: 2)
            grip.backgroundColor = color
            CATransaction.commit()
            if changed, animated, let previous {
                let transition = CABasicAnimation(keyPath: "backgroundColor")
                transition.fromValue = previous; transition.toValue = color; transition.duration = 0.16
                grip.add(transition, forKey: "Split grip hover")
            } else if !animated { grip.removeAnimation(forKey: "Split grip hover") }
        }
        window?.invalidateCursorRects(for: self)
    }

    func configure(orientation: SplitOrientation, factors: [Double]) {
        let changed = savedOrientation != orientation || savedFactors != factors
        if changed { retireDropReservation() }
        savedOrientation = orientation
        savedFactors = factors
        updateContainerMinimum()
        if changed, isTrackingDivider { finishDividerResize(commit: false) }
        else if !isTrackingDivider { applySavedFrames() }
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        if !isApplyingLayout, dropReservation?.isCurrent == false { retireDropReservation() }
        if isTrackingDivider, resize?.bounds != bounds { finishDividerResize(commit: false) }
        else if !isTrackingDivider { applySavedFrames() }
        guard bounds.size != oldSize else { return }
        for view in subviews where !arrangedSubviews.contains(where: { $0 === view }) && !view.autoresizingMask.isEmpty {
            view.resize(withOldSuperviewSize: oldSize)
        }
    }
    func adjustSubviews() {
        if !isTrackingDivider { applySavedFrames() }
    }
    private func applySavedFrames() {
        applyFrames(factors: savedFactors)
    }
    private func applyFrames(factors proposedFactors: [Double]) {
        guard !isApplyingLayout else { return }
        guard !arrangedSubviews.isEmpty else {
            synchronizePaneShadows()
            synchronizeDividerPresentation(animated: false)
            updateTrackingAreas()
            dividerLayoutDidChange()
            return
        }
        clearLayoutAnimation()
        isApplyingLayout = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let reservation = dropReservation
        var views = arrangedSubviews
        var factors = BrowserSplitLayout.normalized(proposedFactors, count: views.count) ?? Array(repeating: 1 / Double(views.count), count: views.count)
        let previewOrientation = reservation?.index != nil ? reservation!.orientation : savedOrientation
        if let reservation, let index = reservation.index {
            let share = 1 / Double(views.count + 1)
            factors = factors.map { $0 * (1 - share) }
            factors.insert(share, at: index); views.insert(reservation.region, at: index)
        }
        isVertical = previewOrientation == .horizontal
        let count = views.count
        let available = max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness * CGFloat(count - 1))
        var lengths = Array(repeating: CGFloat(0), count: count)
        var remaining = available
        var pending = Array(0..<count)
        let minimum = count > 1 ? expandedPaneMinimum : 0
        while !pending.isEmpty {
            let weight = pending.reduce(0.0) { $0 + factors[$1] }
            let small = pending.filter { CGFloat(factors[$0] / weight) * remaining < minimum }
            if small.isEmpty {
                for index in pending { lengths[index] = CGFloat(factors[index] / weight) * remaining }
                break
            }
            for index in small { lengths[index] = minimum; remaining -= minimum }
            pending.removeAll { small.contains($0) }
        }
        let scale = paneBackingScale
        var position: CGFloat = 0
        var anyFrameChanged = false
        for (index, pane) in views.enumerated() {
            let length = max(minimum, (lengths[index] * scale).rounded() / scale)
            let frame = alignedPaneFrame(isVertical
                ? NSRect(x: position, y: 0, width: length, height: bounds.height)
                : NSRect(x: 0, y: position, width: bounds.width, height: length))
            let frameChanged = pane.frame != frame
            if frameChanged {
                pane.frame = frame
                anyFrameChanged = true
            }
            position += length + dividerThickness
            guard pane !== reservation?.region else { continue }
            if frameChanged { pane.needsLayout = true }
            if SplitLayoutFlushSkip.shouldFlush(
                frameChanged: frameChanged,
                needsLayout: pane.needsLayout,
                subtreeNeedsLayout: pane.subviews.contains(where: \.needsLayout)
            ) {
                pane.layoutSubtreeIfNeeded()
            }
        }
        CATransaction.commit()
        isApplyingLayout = false
        if anyFrameChanged { needsDisplay = true }
        synchronizePaneShadows()
        synchronizeDividerPresentation(animated: false)
        updateTrackingAreas()
        dividerLayoutDidChange()
    }
    private func divider(at point: NSPoint) -> Int? {
        guard dropReservation == nil else { return nil }
        return dividerRegions.firstIndex { $0.contains(point) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard isPaneInputLocked, let hit, hit !== self,
              arrangedSubviews.contains(where: { hit === $0 || hit.isDescendant(of: $0) }) else { return hit }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let divider = divider(at: point) else { super.mouseDown(with: event); return }
        guard event.clickCount == 2 else { return }
        finishDividerResize(commit: false)
        guard let commit = prepareDividerResize?(),
              var factors = resizableFactors(at: divider) else { return }
        let views = arrangedSubviews, originalBounds = bounds, orientation = savedOrientation
        let positions = captureLayoutPresentation()
        let half = (factors[divider] + factors[divider + 1]) / 2
        factors[divider] = half; factors[divider + 1] = half
        let accepted = commit(factors)
        let current = originalBounds == bounds && orientation == savedOrientation
            && views.count == arrangedSubviews.count
            && zip(views, arrangedSubviews).allSatisfy { $0 === $1 }
        if accepted, current { savedFactors = factors }
        applySavedFrames()
        if accepted, current { animateEqualizedLayout(from: positions) }
    }
    override func mouseUp(with event: NSEvent) {
        if resize?.moved == false { finishDividerResize(commit: false) }
        super.mouseUp(with: event)
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { retireDropReservation() }
        if newSuperview !== constrainedHost {
            NSLayoutConstraint.deactivate(hostConstraints)
            hostConstraints = []; minimumWidthConstraint = nil; minimumHeightConstraint = nil
            constrainedHost = nil
        }
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { retireDropReservation() }
        if newWindow !== window {
            clearLayoutAnimation(); finishDividerResize(commit: false)
            interactivePaneEdit?.end()
        }
        super.viewWillMove(toWindow: newWindow)
    }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard gestureRecognizer === dividerPan, event.type == .leftMouseDown,
              event.clickCount == 1 else { return false }
        return beginDividerResize(at: convert(event.locationInWindow, from: nil))
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer === dividerPan && resizeIsCurrent
    }
    @objc private func handleDividerPan(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began: beginDividerPan(at: recognizer.location(in: self))
        case .changed:
            updateDividerResize(at: recognizer.location(in: self), velocity: recognizer.velocity(in: self).x)
        case .ended: finishDividerResize(commit: true)
        case .cancelled, .failed: finishDividerResize(commit: false)
        default: break
        }
    }
    func beginDividerPan(at point: NSPoint) {
        guard resizeIsCurrent, point.x.isFinite, point.y.isFinite else { finishDividerResize(commit: false); return }
        resize?.origin = point
        isPaneInputLocked = true
        isDividerPanActive = true
    }
    private var resizeIsCurrent: Bool {
        guard let resize, resize.bounds == bounds, resize.orientation == savedOrientation,
              resize.backingScale == paneBackingScale, resize.views.count == arrangedSubviews.count else { return false }
        return zip(resize.views, arrangedSubviews).allSatisfy { $0 === $1 }
    }
    @discardableResult
    func beginDividerResize(at point: NSPoint) -> Bool {
        clearLayoutAnimation()
        finishDividerResize(commit: false)
        guard let divider = divider(at: point), let commit = prepareDividerResize?(),
              let factors = resizableFactors(at: divider) else { return false }
        resize = Resize(divider: divider, views: arrangedSubviews,
            frames: arrangedSubviews.map(\.frame), bounds: bounds, orientation: savedOrientation,
            backingScale: paneBackingScale, originalFactors: factors,
            origin: point, commit: commit, factors: factors)
        return true
    }
    func updateDividerResize(at point: NSPoint, velocity: CGFloat) {
        guard resizeIsCurrent, var current = resize else { finishDividerResize(commit: false); return }
        let first = current.frames[current.divider]
        let horizontal = current.orientation == .horizontal
        let firstLength = horizontal ? first.width : first.height
        guard point.x.isFinite, point.y.isFinite, velocity.isFinite else { return }
        let delta = horizontal ? point.x - current.origin.x : point.y - current.origin.y
        let liveFirst = current.views[current.divider].frame
        let originShift = horizontal ? liveFirst.minX - first.minX : liveFirst.minY - first.minY
        let proposed = firstLength + delta - originShift
        let pairShare = current.originalFactors[current.divider] + current.originalFactors[current.divider + 1]
        let center = availablePaneLength * CGFloat(pairShare) / 2
        let transitioned = current.snap.update(distance: Double(proposed - center), velocity: Double(velocity))
        let wanted = current.snap.isSnapped ? center : proposed
        guard let fraction = dividerFraction(distance: wanted, pairShare: pairShare) else { return }
        let nextFirst = fraction
        let nextSecond = pairShare - nextFirst
        let factorsChanged = nextFirst != current.factors[current.divider]
            || nextSecond != current.factors[current.divider + 1]
        if SplitLayoutFlushSkip.shouldApplyDividerMove(
            factorsChanged: factorsChanged, alreadyMoved: current.moved
        ) {
            if factorsChanged {
                current.factors[current.divider] = nextFirst
                current.factors[current.divider + 1] = nextSecond
            }
            current.moved = true
            resize = current
            applyFrames(factors: current.factors)
        } else {
            resize = current
        }
        if transitioned { onSnapTransition() }
    }
    func finishDividerResize(commit: Bool) {
        let valid = resizeIsCurrent
        guard let current = resize else { return }
        resize = nil
        isPaneInputLocked = false
        if commit, valid, current.moved, current.commit(current.factors) { savedFactors = current.factors }
        applySavedFrames()
        isDividerPanActive = false
    }
    private var minimumPaneLength: CGFloat {
        expandedPaneMinimum
    }
    func drawDivider(in rect: NSRect) {
    }
    @discardableResult
    func moveDivider(_ divider: Int, forward: Bool) -> Bool {
        commitSteppedResize { SplitPaneResize.movingDivider(divider, in: $0, forward: forward, minimum: $1) }
    }
    @discardableResult
    func resizePane(_ pane: NSView, growing: Bool) -> Bool {
        commitSteppedResize(paneStep(pane, growing: growing))
    }
    @discardableResult
    func equalizePanes() -> Bool {
        commitSteppedResize(equalStep)
    }
    func canResizePane(_ pane: NSView, growing: Bool) -> Bool {
        steppedFactors(paneStep(pane, growing: growing)) != nil
    }
    var canEqualizePanes: Bool { steppedFactors(equalStep) != nil }
    private func paneStep(_ pane: NSView, growing: Bool) -> ([Double], Double) -> [Double]? {
        let index = arrangedSubviews.firstIndex { $0 === pane }
        return { shares, minimum in
            index.flatMap { SplitPaneResize.resizingPane($0, in: shares, growing: growing, minimum: minimum) }
        }
    }
    private func equalStep(_ shares: [Double], _ minimum: Double) -> [Double]? {
        guard savedFactors.count != arrangedSubviews.count || !SplitPaneResize.isEqual(savedFactors) else { return nil }
        return SplitPaneResize.equal(count: shares.count)
    }
    private var adjustableShares: (shares: [Double], minimum: Double)? {
        let available = Double(availablePaneLength), minimum = Double(minimumPaneLength)
        guard available.isFinite, available > 0 else { return nil }
        if let saved = BrowserSplitLayout.normalized(savedFactors, count: arrangedSubviews.count),
           saved.allSatisfy({ $0 * available >= minimum - 0.5 }) {
            return (saved, minimum / available)
        }
        let lengths = arrangedSubviews.map { Double(isVertical ? $0.frame.width : $0.frame.height) }
        let total = lengths.reduce(0, +)
        guard total.isFinite, total > 0,
              let shown = BrowserSplitLayout.normalized(lengths, count: lengths.count) else { return nil }
        return (shown, minimum / total)
    }
    private func steppedFactors(_ adjust: ([Double], Double) -> [Double]?) -> [Double]? {
        guard !isTrackingDivider, dropReservation == nil, interactivePaneEdit == nil, !isApplyingLayout,
              window != nil, let shares = adjustableShares else { return nil }
        return adjust(shares.shares, shares.minimum)
    }
    private func commitSteppedResize(_ adjust: ([Double], Double) -> [Double]?) -> Bool {
        guard let factors = steppedFactors(adjust), let commit = prepareDividerResize?() else { return false }
        let views = arrangedSubviews, originalBounds = bounds, orientation = savedOrientation
        let accepted = commit(factors)
        let current = originalBounds == bounds && orientation == savedOrientation
            && views.count == arrangedSubviews.count
            && zip(views, arrangedSubviews).allSatisfy { $0 === $1 }
        if accepted, current { savedFactors = factors }
        applySavedFrames()
        return accepted && current
    }
    var postAccessibilityNotification: (Any, NSAccessibility.Notification, [NSAccessibility.NotificationUserInfoKey: Any]?) -> Void = {
        NSAccessibility.post(element: $0, notification: $1, userInfo: $2)
    }
    private struct DividerAnnouncementBasis: Equatable {
        let orientation: SplitOrientation
        let factors: [Double]
        let panes: [ObjectIdentifier]
    }
    private var dividerAccessibilityElements: [DividerAccessibilityElement] = []
    private var createdDividerElements: [DividerAccessibilityElement] = []
    private var retiredDividerElements: [DividerAccessibilityElement] = []
    private var announcedDividerBasis: DividerAnnouncementBasis?
    private var dividerSettleTimer: Timer?
    private var dividerAnnouncementBasis: DividerAnnouncementBasis {
        DividerAnnouncementBasis(orientation: savedOrientation, factors: savedFactors,
                                 panes: arrangedSubviews.map(ObjectIdentifier.init))
    }
    private func canAnnounceDividers(endingLiveResize: Bool = false) -> Bool {
        window != nil && !isTrackingDivider && (endingLiveResize || !inLiveResize)
    }
    private func dividerLayoutDidChange() {
        guard canAnnounceDividers() else { return }
        guard dividerAnnouncementBasis == announcedDividerBasis, createdDividerElements.isEmpty,
              retiredDividerElements.isEmpty else { announceDividerChanges(); return }
        guard recordDividerValues(announcing: false) else { return }
        dividerSettleTimer?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.announceDividerChanges() }
        }
        RunLoop.main.add(timer, forMode: .default)
        dividerSettleTimer = timer
    }
    private func announceDividerChanges(endingLiveResize: Bool = false) {
        guard canAnnounceDividers(endingLiveResize: endingLiveResize) else { return }
        dividerSettleTimer?.invalidate(); dividerSettleTimer = nil
        announcedDividerBasis = dividerAnnouncementBasis
        reconcileDividerElements()
        let created = createdDividerElements, retired = retiredDividerElements
        createdDividerElements = []; retiredDividerElements = []
        for element in retired { postAccessibilityNotification(element, .uiElementDestroyed, nil) }
        for element in created { postAccessibilityNotification(element, .created, nil) }
        if !created.isEmpty || !retired.isEmpty, let parent = NSAccessibility.unignoredAncestor(of: self) {
            postAccessibilityNotification(parent, .layoutChanged, created.isEmpty ? nil : [.uiElements: created])
        }
        recordDividerValues(announcing: true)
    }
    @discardableResult
    private func recordDividerValues(announcing: Bool) -> Bool {
        var pending = false
        for element in dividerAccessibilityElements {
            guard let value = element.reportedValue, value != element.announcedValue else { continue }
            let changed = element.announcedValue != nil
            guard announcing || !changed else { pending = true; continue }
            element.announcedValue = value
            if changed { postAccessibilityNotification(element, .valueChanged, nil) }
        }
        return pending
    }
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        announceDividerChanges(endingLiveResize: true)
    }
    private func reconcileDividerElements() {
        let count = max(0, arrangedSubviews.count - 1)
        while dividerAccessibilityElements.count > count {
            let element = dividerAccessibilityElements.removeLast()
            element.owner = nil
            if let unannounced = createdDividerElements.firstIndex(where: { $0 === element }) {
                createdDividerElements.remove(at: unannounced)
            } else { retiredDividerElements.append(element) }
        }
        while dividerAccessibilityElements.count < count {
            let element = DividerAccessibilityElement(owner: self, index: dividerAccessibilityElements.count)
            dividerAccessibilityElements.append(element); createdDividerElements.append(element)
        }
    }
    private func availableDividerElements() -> [DividerAccessibilityElement] {
        reconcileDividerElements()
        return dividerRects.isEmpty ? [] : dividerAccessibilityElements
    }
    override func accessibilityChildren() -> [Any]? {
        let splitters = availableDividerElements()
        var ordered: [Any] = []
        for (index, pane) in arrangedSubviews.enumerated() {
            ordered.append(pane)
            if splitters.indices.contains(index) { ordered.append(splitters[index]) }
        }
        ordered += subviews.filter { view in !arrangedSubviews.contains { $0 === view } }
        return NSAccessibility.unignoredChildren(from: ordered)
    }
    override func accessibilitySplitters() -> [Any]? { availableDividerElements() }
    final class DividerAccessibilityElement: NSAccessibilityElement {
        fileprivate weak var owner: ParcSplitView?
        let index: Int
        fileprivate var announcedValue: Double?
        fileprivate var reportedValue: Double? { position.map { ($0.value * 100).rounded() } }
        fileprivate init(owner: ParcSplitView, index: Int) {
            self.owner = owner; self.index = index
            super.init()
        }
        private var position: (value: Double, minimum: Double, maximum: Double)? {
            guard isAvailable, let owner, let current = owner.adjustableShares,
                  current.shares.indices.contains(index + 1) else { return nil }
            let before = current.shares[..<index].reduce(0, +)
            let value = before + current.shares[index]
            return (value, before + current.minimum, value + current.shares[index + 1] - current.minimum)
        }
        private var isAvailable: Bool { owner?.dividerRects.indices.contains(index) == true }
        override func isAccessibilityElement() -> Bool { isAvailable }
        override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
        override func accessibilityLabel() -> String? {
            (owner?.dividerRects.count ?? 0) > 1 ? "Split View Divider \(index + 1)" : "Split View Divider"
        }
        override func accessibilityHelp() -> String? { "Increase or decrease to resize the pages on either side." }
        override func accessibilityValue() -> Any? { reportedValue.map { NSNumber(value: $0) } }
        override func accessibilityMinValue() -> Any? { position.map { NSNumber(value: ($0.minimum * 100).rounded()) } }
        override func accessibilityMaxValue() -> Any? { position.map { NSNumber(value: ($0.maximum * 100).rounded()) } }
        override func accessibilityValueDescription() -> String? {
            position?.value.formatted(.percent.precision(.fractionLength(0)))
        }
        override func accessibilityOrientation() -> NSAccessibilityOrientation {
            owner?.isVertical == false ? .horizontal : .vertical
        }
        override func accessibilityParent() -> Any? { owner.flatMap { NSAccessibility.unignoredAncestor(of: $0) } }
        override func accessibilityFrame() -> NSRect {
            guard let owner, let window = owner.window, owner.dividerRects.indices.contains(index) else { return .zero }
            return window.convertToScreen(owner.convert(owner.dividerRects[index], to: nil))
        }
        override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
            guard isAvailable, selector != #selector(setAccessibilityValue(_:)) else { return false }
            return super.isAccessibilitySelectorAllowed(selector)
        }
        override func accessibilityPerformIncrement() -> Bool { isAvailable && owner?.moveDivider(index, forward: true) == true }
        override func accessibilityPerformDecrement() -> Bool { isAvailable && owner?.moveDivider(index, forward: false) == true }
    }
}

@MainActor
protocol SplitLayoutFollowing: AnyObject {
    func followSplitLayout(from previous: CGRect, animation: CAAnimation)
    func cancelSplitLayoutFollow()
}
