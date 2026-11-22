import AppKit
import ParcCore

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
        private let originalStacks: BrowserSplitStacks?
        private let mainRowCount: Int
        private let stacks: BrowserSplitStacks?
        private let hostBounds: NSRect
        private let hostFrame: NSRect
        private let windowFrame: NSRect
        private let scale: CGFloat
        private var splitFrame: NSRect
        private var splitBounds: NSRect
        private let originalPaneFrames: [NSRect]
        private var paneFrames: [NSRect]
        private var contentFrames: [NSRect]
        private var paneHostFrames: [NSRect]
        private var splitHostFrame: NSRect
        private var updating = false
        private(set) var ended = false
        fileprivate let region = DropRegionView()
        fileprivate var orientation: SplitOrientation
        fileprivate private(set) var target: SplitDropTarget?
        fileprivate var insertionIndex: Int? {
            if case .insert(let index)? = target { return index }
            return nil
        }
        private(set) var reusedRegion = false
        private(set) var appeared = false
        private var retiredTarget: SplitDropTarget?
        var hoverIntent = SplitDropIntent()
        var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var onIntentDue: (() -> Void)?
        private var intentTimer: Timer?
        var shownTarget: SplitDropTarget? { hoverIntent.shown?.target }
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
            originalStacks = owner.savedStacks
            stacks = owner.activeStacks
            mainRowCount = stacks?.slotSizes.count ?? owner.arrangedSubviews.count
            hostBounds = host.bounds; hostFrame = host.frame; windowFrame = owner.window?.frame ?? .zero
            scale = owner.paneBackingScale; splitFrame = owner.frame; splitBounds = owner.bounds
            paneFrames = panes.map(\.frame); originalPaneFrames = paneFrames
            contentFrames = contents.map { $0.convert($0.bounds, to: host) }
            paneHostFrames = panes.map { $0.convert($0.bounds, to: host) }
            splitHostFrame = owner.convert(owner.bounds, to: host)
            region.wantsLayer = true; region.setAccessibilityElement(false); region.setAccessibilityChildren([])
        }
        var incomingPaneSize: NSSize {
            guard case .stack(let pane, _)? = target, originalPaneFrames.indices.contains(pane) else {
                let share = CGFloat(mainRowCount + 1)
                return orientation == .horizontal
                    ? NSSize(width: splitBounds.width / share, height: splitBounds.height)
                    : NSSize(width: splitBounds.width, height: splitBounds.height / share)
            }
            let count = CGFloat(stacks.flatMap { shape in shape.place(ofPane: pane).map { shape.slotSizes[$0.slot] } } ?? 1) + 1
            let slot = originalPaneFrames[pane]
            return originalOrientation == .horizontal
                ? NSSize(width: slot.width, height: splitBounds.height / count)
                : NSSize(width: splitBounds.width / count, height: slot.height)
        }
        var isCurrent: Bool {
            guard !ended, let owner, let host, let window, owner.dropReservation === self,
                  owner.window === window, host.window === window, owner.isDescendant(of: host),
                  host.bounds == hostBounds, host.frame == hostFrame, window.frame == windowFrame,
                  owner.paneBackingScale == scale, owner.savedOrientation == originalOrientation,
                  owner.savedFactors == originalFactors, owner.savedStacks == originalStacks,
                  panes.count == owner.arrangedSubviews.count,
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
            splitHostFrame = owner.convert(owner.bounds, to: host)
        }
        private var regionFrame: NSRect? {
            guard target != nil, let owner, let host else { return nil }
            return owner.convert(region.frame, to: host)
        }
        func containsReservedPoint(_ point: NSPoint) -> Bool {
            isCurrent && regionFrame?.contains(point) == true
        }
        func containsContentPoint(_ point: NSPoint, outside view: NSView? = nil) -> Bool {
            isCurrent && zip(contents, contentFrames).contains { content, frame in
                frame.contains(point) && !(view.map { $0 === content || $0.isDescendant(of: content) } ?? false)
            }
        }
        func containsHandoffPoint(_ point: NSPoint) -> Bool {
            guard isCurrent else { return false }
            if regionFrame?.contains(point) == true { return true }
            return splitHostFrame.contains(point) && !contentFrames.contains { $0.contains(point) }
        }
        @MainActor func proposal(at point: NSPoint, canPropose: (SplitDropTarget, SplitOrientation) -> Bool,
                                 presenting: Bool = true) -> SplitDropGeometry.Proposal? {
            guard isCurrent else { end(); return nil }
            if presenting { reusedRegion = false; appeared = false }
            let place: SplitDropIntent.Place
            var drop: SplitDropGeometry.Proposal?
            if let target, let rect = regionFrame, rect.contains(point), canPropose(target, orientation), isCurrent {
                place = .preview; drop = (target, orientation, rect)
                if presenting { reusedRegion = true }
            } else {
                guard isCurrent else { end(); return nil }
                guard splitHostFrame.contains(point) else {
                    if presenting { leave() }
                    return nil
                }
                if paneHostFrames.contains(where: { $0.contains(point) }) {
                    drop = SplitDropGeometry.proposal(at: point, frames: paneHostFrames,
                        orientation: orientation, slotSizes: stacks?.slotSizes, canPropose: canPropose)
                    if case .replace(let index)? = drop?.0 { drop = (.replace(index), originalOrientation, paneHostFrames[index]) }
                    place = .pane(drop.map { SplitDropIntent.Zone(target: $0.0, orientation: $0.1) })
                } else if let shown = hoverIntent.shown, !canPropose(shown.target, shown.orientation) {
                    place = .pane(nil)
                } else {
                    place = .preview
                    drop = hoverIntent.shown.map { ($0.target, $0.orientation, splitHostFrame) }
                }
                guard isCurrent else { end(); return nil }
            }
            if presenting {
                present(hoverIntent.move(to: place, x: Double(point.x), y: Double(point.y), at: clock()))
                guard isCurrent else { end(); return nil }
            }
            guard let drop else { return nil }
            return (drop.0, drop.1, frame(for: drop))
        }
        private func frame(for drop: SplitDropGeometry.Proposal) -> NSRect {
            if drop.0 == target, drop.1 == orientation, let rect = regionFrame { return rect }
            if case .replace(let index) = drop.0, paneHostFrames.indices.contains(index) { return paneHostFrames[index] }
            return drop.2
        }
        @MainActor private func present(_ step: SplitDropIntent.Step) {
            scheduleIntent()
            guard step.changed else {
                if target != nil { reusedRegion = true }
                return
            }
            if let zone = step.shown, zone.target.reservesRoom { open(zone) } else { collapse(animated: true) }
            appeared = !ended && step.appeared && !reusedRegion
        }
        @MainActor private func open(_ zone: SplitDropIntent.Zone) {
            guard isCurrent, let owner, let collapsed = collapsedFrame(for: zone.target, orientation: zone.orientation) else { end(); return }
            guard target != zone.target || orientation != zone.orientation else { reusedRegion = true; return }
            reusedRegion = target == nil && retiredTarget == zone.target && owner.retiringDropRegion === region
            let positions = owner.captureLayoutPresentation()
            let visible = owner.captureDropRegion(region)
            owner.clearRetiringDropRegion()
            updating = true
            orientation = zone.orientation; target = zone.target
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
        private func leave() {
            _ = hoverIntent.leave()
            scheduleIntent()
            collapse(animated: true)
        }
        private func resetIntent() {
            hoverIntent.reset(); appeared = false
            intentTimer?.invalidate(); intentTimer = nil
        }
        private func scheduleIntent() {
            guard !ended, let deadline = hoverIntent.deadline else {
                intentTimer?.invalidate(); intentTimer = nil
                return
            }
            let date = Date(timeIntervalSinceNow: max(0, deadline - clock()))
            if let intentTimer, intentTimer.isValid { intentTimer.fireDate = date; return }
            let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.intentTimer = nil
                    if !self.ended { self.onIntentDue?() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            intentTimer = timer
        }
        private func collapsedFrame(for target: SplitDropTarget, orientation: SplitOrientation) -> NSRect? {
            guard let owner else { return nil }
            let horizontal = orientation == .horizontal
            switch target {
            case .insert(let index):
                guard index >= 0, index <= panes.count else { return nil }
                let edge: CGFloat
                if index == 0 { edge = 0 }
                else if index >= panes.count { edge = horizontal ? panes.last!.frame.maxX : panes.last!.frame.maxY }
                else { edge = horizontal ? panes[index].frame.minX : panes[index].frame.minY }
                return horizontal
                    ? NSRect(x: edge, y: 0, width: 0, height: owner.bounds.height)
                    : NSRect(x: 0, y: edge, width: owner.bounds.width, height: 0)
            case .stack(let pane, let after):
                guard panes.indices.contains(pane) else { return nil }
                let frame = panes[pane].frame
                return horizontal
                    ? NSRect(x: frame.minX, y: after ? frame.maxY : frame.minY, width: frame.width, height: 0)
                    : NSRect(x: after ? frame.maxX : frame.minX, y: frame.minY, width: 0, height: frame.height)
            case .replace: return nil
            }
        }
        func clear(animated: Bool = false) {
            resetIntent()
            collapse(animated: animated)
        }
        private func collapse(animated: Bool) {
            guard let owner, owner.dropReservation === self, !ended else { return }
            guard let previousTarget = target else {
                if !animated { owner.clearLayoutAnimation() }
                return
            }
            let animate = animated && isCurrent
            let positions = animate ? owner.captureLayoutPresentation() : []
            let border = animate ? owner.captureDropRegion(region) : nil
            let previousOrientation = orientation
            updating = true; target = nil; orientation = originalOrientation
            region.removeFromSuperview(); owner.applyDropReserveLayout()
            capture(); updating = false
            guard isCurrent else { return }
            owner.animateReservedLayout(from: positions)
            if animate, let border {
                region.frame = collapsedFrame(for: previousTarget, orientation: previousOrientation) ?? .zero
                owner.addSubview(region)
                retiredTarget = previousTarget
                owner.presentDropRegion(region, from: border, opacity: 0, removing: true)
            }
        }
        func end(animated: Bool = false) {
            guard !ended else { return }
            resetIntent()
            let current = isCurrent
            let animate = animated && current
            let positions = animate ? owner?.captureLayoutPresentation() ?? [] : []
            let border = animate ? owner?.captureDropRegion(region) : nil
            let previousTarget = target, previousOrientation = orientation
            ended = true
            guard let owner, owner.dropReservation === self else { region.removeFromSuperview(); return }
            owner.dropReservation = nil
            if animate, previousTarget == nil { return }
            region.removeFromSuperview()
            owner.applyDropReserveLayout()
            if animate {
                owner.animateReservedLayout(from: positions)
                if let previousTarget, let border {
                    region.frame = collapsedFrame(for: previousTarget, orientation: previousOrientation) ?? .zero
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
    var prepareStackedResize: (() -> ((SplitStackResize) -> BrowserSplitStacks?)?)?
    private var dividerGrips: [CALayer] = []
    private var dividerTrackingAreas: [NSTrackingArea] = []
    private var hoveredDivider: Int?
    private var topmostCursor = TopmostCursor()
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
    private var savedStacks: BrowserSplitStacks?
    private var activeStacks: BrowserSplitStacks? {
        savedStacks?.validated(paneCount: arrangedSubviews.count)
    }
    var onSnapTransition: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    private lazy var dividerPan = NSPanGestureRecognizer(target: self, action: #selector(handleDividerPan(_:)))
    private struct StackLevel {
        let divider: SplitStackDivider
        let stacks: BrowserSplitStacks
        let views: [NSView]
        let horizontal: Bool
        let available: CGFloat
        let rescaled: Bool
        let commit: (SplitStackResize) -> BrowserSplitStacks?
    }
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
        var level: StackLevel? = nil
        var snap = SplitDividerSnapState()
        var factors: [Double]
        var moved = false
        var movesHorizontally: Bool { level?.horizontal ?? (orientation == .horizontal) }
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

    func constrain(to host: NSView) {
        guard superview === host else { return }
        if constrainedHost !== host {
            NSLayoutConstraint.deactivate(hostConstraints)
            constrainedHost = host
            translatesAutoresizingMaskIntoConstraints = false
            hostConstraints = [leadingAnchor.constraint(equalTo: host.leadingAnchor),
                topAnchor.constraint(equalTo: host.topAnchor),
                trailingAnchor.constraint(equalTo: host.trailingAnchor),
                bottomAnchor.constraint(equalTo: host.bottomAnchor)]
            NSLayoutConstraint.activate(hostConstraints)
        }
        flushHostLayout()
    }

    private func flushHostLayout() {
        guard let host = constrainedHost, superview === host,
              SplitLayoutFlushSkip.shouldFlush(needsLayout: host.needsLayout,
                  subtreeNeedsLayout: host.subviews.contains(where: \.needsLayout)) else { return }
        host.layoutSubtreeIfNeeded()
    }

    fileprivate func applyDropReserveLayout() {
        flushHostLayout()
        applySavedFrames()
        if SplitLayoutFlushSkip.shouldFlush(
            needsLayout: needsLayout,
            subtreeNeedsLayout: subviews.contains(where: \.needsLayout)
        ) {
            layoutSubtreeIfNeeded()
        }
    }

    private var paneBackingScale: CGFloat {
        let scale = window?.backingScaleFactor ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }

    private var availablePaneLength: CGFloat {
        let total = savedOrientation == .horizontal ? bounds.width : bounds.height
        return max(0, total - dividerThickness * CGFloat(max(0, arrangedSubviews.count - 1)))
    }

    private func fittedMinimum(count: Int, available: CGFloat) -> CGFloat {
        SplitStackGeometry.fittedMinimum(count: count, available: available, minimum: expandedPaneMinimum)
    }

    private var flatPaneMinimum: CGFloat {
        fittedMinimum(count: arrangedSubviews.count, available: availablePaneLength)
    }

    private func resizableFactors(at divider: Int) -> [Double]? {
        guard arrangedSubviews.indices.contains(divider), arrangedSubviews.indices.contains(divider + 1),
              let factors = BrowserSplitLayout.normalized(savedFactors, count: arrangedSubviews.count) else { return nil }
        let minimum = flatPaneMinimum
        guard CGFloat(factors[divider] + factors[divider + 1]) * availablePaneLength < 2 * minimum else { return factors }
        var lengths = arrangedSubviews.map { Double(isVertical ? $0.frame.width : $0.frame.height) }
        let pair = lengths[divider] + lengths[divider + 1]
        let room = Double(availablePaneLength) - (lengths.reduce(0, +) - pair)
        guard pair > 2 * Double(minimum), room > 2 * Double(minimum) else { return factors }
        lengths[divider] *= room / pair; lengths[divider + 1] *= room / pair
        return BrowserSplitLayout.normalized(lengths, count: lengths.count) ?? factors
    }

    private func dividerFraction(distance: CGFloat, pairShare: Double, available: CGFloat, minimum length: CGFloat) -> Double? {
        guard distance.isFinite, available.isFinite, available > 0 else { return nil }
        let minimum = Double(length / available)
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
                MainActor.assumeIsolated {
                    self?.retireDropReservation(); self?.clearLayoutAnimation(); self?.updateDividerHover(at: nil, animated: false)
                    self?.topmostCursor.release()
                }
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
    override func cursorUpdate(with event: NSEvent) {
        guard let window, !isHiddenOrHasHiddenAncestor,
              let cursor = dividerCursor(atWindowPoint: window.mouseLocationOutsideOfEventStream) else {
            topmostCursor.release(); super.cursorUpdate(with: event); return
        }
        topmostCursor.update(cursor, in: self)
    }
    func dividerCursor(atWindowPoint point: NSPoint) -> NSCursor? {
        dividerCursor(topmost: topmostPoint(atWindowPoint: point))
    }
    private func dividerCursor(topmost: NSPoint?) -> NSCursor? {
        guard topmost != nil || isDividerPanActive else { return nil }
        guard let stacked = stackedDividers else { return isVertical ? .resizeLeftRight : .resizeUpDown }
        let hovered = topmost.flatMap { divider(at: $0) }.flatMap { stacked.indices.contains($0) ? stacked[$0] : nil }
        let vertical = resize?.movesHorizontally ?? hovered?.isVerticalBar ?? isVertical
        return vertical ? .resizeLeftRight : .resizeUpDown
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
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .enabledDuringMouseDrag],
                owner: self, userInfo: nil)
            addTrackingArea(area); return area
        }
        resampleDividerPointer()
    }
    private func resampleDividerPointer() {
        if let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor {
            let topmost = topmostPoint(atWindowPoint: window.mouseLocationOutsideOfEventStream)
            updateDividerHover(at: topmost, animated: false)
            topmostCursor.update(dividerCursor(topmost: topmost), in: self)
        } else { updateDividerHover(at: nil, animated: false); topmostCursor.release() }
    }
    override func mouseEntered(with event: NSEvent) {
        guard let area = event.trackingArea, dividerTrackingAreas.contains(where: { $0 === area }),
              let window, event.window === window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        let topmost = topmostPoint(atWindowPoint: event.locationInWindow)
        updateDividerHover(at: topmost)
        topmostCursor.update(dividerCursor(topmost: topmost), in: self)
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard dividerTrackingAreas.contains(where: { $0.rect.contains(point) }) else {
            super.mouseMoved(with: event); return
        }
        guard let window, event.window === window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        let topmost = topmostPoint(atWindowPoint: event.locationInWindow)
        updateDividerHover(at: topmost)
        topmostCursor.update(dividerCursor(topmost: topmost), in: self)
    }
    private func topmostPoint(atWindowPoint point: NSPoint) -> NSPoint? {
        let local = convert(point, from: nil)
        return divider(at: local) != nil && isTopmost(atWindowPoint: point) ? local : nil
    }
    override func mouseExited(with event: NSEvent) {
        guard let area = event.trackingArea, dividerTrackingAreas.contains(where: { $0 === area }) else { return }
        updateDividerHover(at: nil)
        topmostCursor.release()
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
    private var stackedDividers: [SplitStackGeometry.Divider]? {
        guard let stacks = activeStacks else { return nil }
        guard dropReservation?.target == nil else { return [] }
        return SplitStackGeometry.dividers(paneFrames: arrangedSubviews.map(\.frame), size: bounds.size,
            orientation: savedOrientation, stacks: stacks, thickness: dividerThickness)
    }
    private var dividerRects: [NSRect] {
        guard dropReservation?.target == nil else { return [] }
        if let stacked = stackedDividers { return stacked.map(\.rect) }
        return arrangedSubviews.dropLast().map { pane in
            isVertical
                ? NSRect(x: pane.frame.maxX, y: 0, width: dividerThickness, height: bounds.height)
                : NSRect(x: 0, y: pane.frame.maxY, width: bounds.width, height: dividerThickness)
        }
    }
    private var dividerRegions: [NSRect] {
        if let stacked = stackedDividers { return stacked.map(\.region) }
        return dividerRects.map { rect in
            isVertical
                ? NSRect(x: rect.minX, y: rect.minY + draggableTopInset,
                         width: rect.width, height: max(0, rect.height - draggableTopInset))
                : NSRect(x: rect.minX + draggableEndInset, y: rect.minY,
                         width: max(0, rect.width - 2 * draggableEndInset), height: rect.height)
        }
    }
    weak var marginHandle: SplitMarginHandleView? { didSet { synchronizeDividerPresentation(animated: false) } }
    private func synchronizeDividerPresentation(animated: Bool) {
        marginHandle?.splitAllows = arrangedSubviews.count == 1 && dropReservation?.target == nil
        guard let layer else { return }
        let rects = dividerRects
        while dividerGrips.count > rects.count { dividerGrips.removeLast().removeFromSuperlayer() }
        while dividerGrips.count < rects.count {
            let grip = CALayer(); grip.name = "Split divider grip"; grip.cornerRadius = 1
            layer.addSublayer(grip); dividerGrips.append(grip)
        }
        if let hoveredDivider, !rects.indices.contains(hoveredDivider) { self.hoveredDivider = nil }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bars = stackedDividers?.map(\.isVerticalBar)
        for (index, rect) in rects.enumerated() {
            let grip = dividerGrips[index]
            let vertical = bars.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? isVertical
            let color = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0,
                                alpha: hoveredDivider == index ? 0.5 : 0.2).cgColor
            let previous = grip.presentation()?.backgroundColor ?? grip.backgroundColor
            let changed = grip.backgroundColor != color
            CATransaction.begin(); CATransaction.setDisableActions(true)
            grip.frame = vertical
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
    }

    func configure(orientation: SplitOrientation, factors: [Double], stacks: BrowserSplitStacks? = nil) {
        let changed = savedOrientation != orientation || savedFactors != factors || savedStacks != stacks
        if changed { retireDropReservation() }
        savedOrientation = orientation
        savedFactors = factors
        savedStacks = stacks
        flushHostLayout()
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
        if let stacks = activeStacks ?? reservedFlatStacks { applyStackedFrames(stacks) } else { applyFrames(factors: savedFactors) }
    }
    private var reservedFlatStacks: BrowserSplitStacks? {
        let count = arrangedSubviews.count
        guard dropReservation?.target?.isStack == true, count > 1 else { return nil }
        return .flat(BrowserSplitLayout.normalized(savedFactors, count: count) ?? Array(repeating: 1 / Double(count), count: count))
    }
    private func reservedStack(in stacks: BrowserSplitStacks) -> (stacks: BrowserSplitStacks, region: Int)? {
        guard case .stack(let pane, let after)? = dropReservation?.target else { return nil }
        return stacks.reservingStack(besidePane: pane, after: after)
    }
    private func applyStackedFrames(_ stacks: BrowserSplitStacks) {
        guard !isApplyingLayout else { return }
        clearLayoutAnimation()
        isApplyingLayout = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let reservation = dropReservation
        var views = arrangedSubviews
        var shape = stacks
        if let reservation, let index = reservation.insertionIndex {
            let boundaries = stacks.slotBoundaries
            let slot = boundaries.lastIndex { $0 <= index } ?? 0
            shape = stacks.reservingSlot(at: slot)
            views.insert(reservation.region, at: boundaries[slot])
        } else if let reservation, let reserved = reservedStack(in: stacks) {
            shape = reserved.stacks
            views.insert(reservation.region, at: reserved.region)
        }
        isVertical = savedOrientation == .horizontal
        let frames = SplitStackGeometry.paneFrames(size: bounds.size, orientation: savedOrientation, stacks: shape,
            thickness: dividerThickness, minimum: expandedPaneMinimum, scale: paneBackingScale)
        var anyFrameChanged = false
        for (pane, frame) in zip(views, frames) {
            let frameChanged = pane.frame != frame
            if frameChanged {
                pane.frame = frame
                anyFrameChanged = true
            }
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
        let previewOrientation = reservation?.insertionIndex != nil ? reservation!.orientation : savedOrientation
        if let reservation, let index = reservation.insertionIndex {
            let share = 1 / Double(views.count + 1)
            factors = factors.map { $0 * (1 - share) }
            factors.insert(share, at: index); views.insert(reservation.region, at: index)
        }
        isVertical = previewOrientation == .horizontal
        let frames = SplitStackGeometry.flatFrames(size: bounds.size, orientation: previewOrientation, factors: factors,
            thickness: dividerThickness, minimum: expandedPaneMinimum, scale: paneBackingScale)
        var anyFrameChanged = false
        for (pane, frame) in zip(views, frames) {
            let frameChanged = pane.frame != frame
            if frameChanged {
                pane.frame = frame
                anyFrameChanged = true
            }
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
        if let stacks = activeStacks {
            guard let id = stacks.divider(after: divider), let pair = stackedPair(id, in: stacks) else { return }
            var factors = pair.factors
            let half = (factors[id.index] + factors[id.index + 1]) / 2
            factors[id.index] = half; factors[id.index + 1] = half
            let positions = captureLayoutPresentation()
            if commitStackedChange(stackedPairChange(id, factors: factors, rescaled: pair.rescaled)) {
                animateEqualizedLayout(from: positions)
            }
            return
        }
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
            hostConstraints = []
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
            updateDividerResize(at: recognizer.location(in: self), panVelocity: recognizer.velocity(in: self))
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
              resize.backingScale == paneBackingScale, resize.views.count == arrangedSubviews.count,
              resize.level?.stacks.slotSizes == activeStacks?.slotSizes else { return false }
        return zip(resize.views, arrangedSubviews).allSatisfy { $0 === $1 }
    }
    private func stackLevel(_ slot: Int?, in stacks: BrowserSplitStacks)
        -> (views: [NSView], horizontal: Bool, available: CGFloat, factors: [Double])? {
        guard let factors = stacks.factors(inSlot: slot) else { return nil }
        let boundaries = stacks.slotBoundaries
        let views: [NSView]
        if let slot {
            guard boundaries.indices.contains(slot + 1), boundaries[slot + 1] <= arrangedSubviews.count else { return nil }
            views = Array(arrangedSubviews[boundaries[slot]..<boundaries[slot + 1]])
        } else {
            views = boundaries.dropLast().compactMap { arrangedSubviews.indices.contains($0) ? arrangedSubviews[$0] : nil }
        }
        guard views.count == factors.count, views.count > 1 else { return nil }
        let horizontal = (slot == nil) == (savedOrientation == .horizontal)
        let length = horizontal ? bounds.width : bounds.height
        return (views, horizontal, max(0, length - dividerThickness * CGFloat(views.count - 1)), factors)
    }
    private func stackedShares(_ slot: Int?) -> (shares: [Double], minimum: Double)? {
        guard let stacks = activeStacks, let level = stackLevel(slot, in: stacks) else { return nil }
        return SplitStackGeometry.adjustableShares(saved: level.factors,
            shown: level.views.map { Double(level.horizontal ? $0.frame.width : $0.frame.height) },
            available: Double(level.available),
            minimum: Double(fittedMinimum(count: level.views.count, available: level.available)))
    }
    private func commitStackedChange(_ change: SplitStackResize?) -> Bool {
        guard let change, let commit = prepareStackedResize?() else { return false }
        let views = arrangedSubviews, originalBounds = bounds, orientation = savedOrientation
        let committed = commit(change)
        let current = originalBounds == bounds && orientation == savedOrientation
            && views.count == arrangedSubviews.count
            && zip(views, arrangedSubviews).allSatisfy { $0 === $1 }
        if let committed, current, committed.paneCount == arrangedSubviews.count {
            savedStacks = committed; savedFactors = committed.flattenedFactors
        }
        applySavedFrames()
        return committed != nil && current
    }
    private func stackedPair(_ id: SplitStackDivider, in stacks: BrowserSplitStacks)
        -> (level: (views: [NSView], horizontal: Bool, available: CGFloat, factors: [Double]), factors: [Double], rescaled: Bool)? {
        guard let level = stackLevel(id.slot, in: stacks),
              let factors = SplitStackGeometry.resizableFactors(saved: level.factors,
                  shown: level.views.map { Double(level.horizontal ? $0.frame.width : $0.frame.height) },
                  divider: id.index, available: Double(level.available),
                  minimum: Double(fittedMinimum(count: level.views.count, available: level.available))) else { return nil }
        let rescaled = !zip(factors, level.factors).allSatisfy { abs($0 - $1) < 1e-9 }
        return (level, factors, rescaled)
    }
    private func stackedPairChange(_ id: SplitStackDivider, factors: [Double], rescaled: Bool) -> SplitStackResize {
        guard !rescaled else { return .level(slot: id.slot, factors: factors) }
        let first = factors[id.index]
        return .divider(id.index, slot: id.slot, leadingShare: first / (first + factors[id.index + 1]))
    }
    private func beginStackedResize(at point: NSPoint, divider: Int, stacks: BrowserSplitStacks) -> Bool {
        guard let id = stacks.divider(after: divider), let pair = stackedPair(id, in: stacks),
              let commit = prepareStackedResize?() else { return false }
        let level = pair.level
        resize = Resize(divider: id.index, views: arrangedSubviews, frames: level.views.map(\.frame), bounds: bounds,
            orientation: savedOrientation, backingScale: paneBackingScale, originalFactors: pair.factors, origin: point,
            commit: { _ in false }, level: StackLevel(divider: id, stacks: stacks, views: level.views,
                horizontal: level.horizontal, available: level.available, rescaled: pair.rescaled, commit: commit),
            factors: pair.factors)
        return true
    }
    @discardableResult
    func beginDividerResize(at point: NSPoint) -> Bool {
        clearLayoutAnimation()
        finishDividerResize(commit: false)
        guard let divider = divider(at: point) else { return false }
        if let stacks = activeStacks { return beginStackedResize(at: point, divider: divider, stacks: stacks) }
        guard let commit = prepareDividerResize?(),
              let factors = resizableFactors(at: divider) else { return false }
        resize = Resize(divider: divider, views: arrangedSubviews,
            frames: arrangedSubviews.map(\.frame), bounds: bounds, orientation: savedOrientation,
            backingScale: paneBackingScale, originalFactors: factors,
            origin: point, commit: commit, factors: factors)
        return true
    }
    func updateDividerResize(at point: NSPoint, panVelocity: NSPoint) {
        updateDividerResize(at: point, velocity: CGFloat(SplitDividerSnapState.velocity(
            panVelocity, movingHorizontally: resize?.movesHorizontally ?? isVertical)))
    }
    func updateDividerResize(at point: NSPoint, velocity: CGFloat) {
        guard resizeIsCurrent, var current = resize else { finishDividerResize(commit: false); return }
        let first = current.frames[current.divider]
        let horizontal = current.movesHorizontally
        let firstLength = horizontal ? first.width : first.height
        guard point.x.isFinite, point.y.isFinite, velocity.isFinite else { return }
        let delta = horizontal ? point.x - current.origin.x : point.y - current.origin.y
        let liveFirst = (current.level?.views ?? current.views)[current.divider].frame
        let originShift = horizontal ? liveFirst.minX - first.minX : liveFirst.minY - first.minY
        let proposed = firstLength + delta - originShift
        let pairShare = current.originalFactors[current.divider] + current.originalFactors[current.divider + 1]
        let available = current.level?.available ?? availablePaneLength
        let minimum = fittedMinimum(count: (current.level?.views ?? current.views).count, available: available)
        guard minimum >= expandedPaneMinimum, CGFloat(pairShare) * available >= 2 * minimum - 0.5 else { return }
        let center = available * CGFloat(pairShare) / 2
        let transitioned = current.snap.update(distance: Double(proposed - center), velocity: Double(velocity))
        let wanted = current.snap.isSnapped ? center : proposed
        guard let fraction = dividerFraction(distance: wanted, pairShare: pairShare, available: available,
                                             minimum: minimum) else { return }
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
            if let level = current.level {
                applyStackedFrames(level.stacks.replacing(current.factors, inSlot: level.divider.slot))
            } else { applyFrames(factors: current.factors) }
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
        if commit, valid, current.moved, let level = current.level {
            if let committed = level.commit(stackedPairChange(level.divider, factors: current.factors, rescaled: level.rescaled)),
               committed.paneCount == arrangedSubviews.count {
                savedStacks = committed; savedFactors = committed.flattenedFactors
            }
        } else if commit, valid, current.moved, current.commit(current.factors) { savedFactors = current.factors }
        applySavedFrames()
        isDividerPanActive = false
        resampleDividerPointer()
    }
    func drawDivider(in rect: NSRect) {
    }
    @discardableResult
    func moveDivider(_ divider: Int, forward: Bool) -> Bool {
        if let stacks = activeStacks { return commitStackedChange(stackedDividerStep(divider, forward: forward, stacks: stacks)) }
        return commitSteppedResize { SplitPaneResize.movingDivider(divider, in: $0, forward: forward, minimum: $1) }
    }
    @discardableResult
    func resizePane(_ pane: NSView, growing: Bool) -> Bool {
        if let stacks = activeStacks { return commitStackedChange(stackedPaneStep(pane, growing: growing, stacks: stacks)) }
        return commitSteppedResize(paneStep(pane, growing: growing))
    }
    @discardableResult
    func equalizePanes() -> Bool {
        if let stacks = activeStacks { return commitStackedChange(stackedEqualStep(stacks)) }
        return commitSteppedResize(equalStep)
    }
    func canResizePane(_ pane: NSView, growing: Bool) -> Bool {
        if let stacks = activeStacks { return stackedPaneStep(pane, growing: growing, stacks: stacks) != nil }
        return steppedFactors(paneStep(pane, growing: growing)) != nil
    }
    var canEqualizePanes: Bool {
        if let stacks = activeStacks { return stackedEqualStep(stacks) != nil }
        return steppedFactors(equalStep) != nil
    }
    private func stackedStep(_ slot: Int?, _ adjust: ([Double], Double) -> SplitStackResize?) -> SplitStackResize? {
        guard !isTrackingDivider, dropReservation == nil, interactivePaneEdit == nil, !isApplyingLayout,
              window != nil, let shares = stackedShares(slot) else { return nil }
        return adjust(shares.shares, shares.minimum)
    }
    private func stackedDividerStep(_ divider: Int, forward: Bool, stacks: BrowserSplitStacks) -> SplitStackResize? {
        guard let id = stacks.divider(after: divider) else { return nil }
        return stackedStep(id.slot) { shares, minimum in
            SplitPaneResize.movingDivider(id.index, in: shares, forward: forward, minimum: minimum).map {
                .divider(id.index, slot: id.slot, leadingShare: $0[id.index] / ($0[id.index] + $0[id.index + 1]))
            }
        }
    }
    private func stackedPaneStep(_ pane: NSView, growing: Bool, stacks: BrowserSplitStacks) -> SplitStackResize? {
        guard let index = arrangedSubviews.firstIndex(where: { $0 === pane }),
              let slot = stacks.place(ofPane: index)?.slot else { return nil }
        return stackedStep(nil) { shares, minimum in
            SplitPaneResize.resizingPane(slot, in: shares, growing: growing, minimum: minimum).map { .slots($0) }
        }
    }
    private func stackedEqualStep(_ stacks: BrowserSplitStacks) -> SplitStackResize? {
        stackedStep(nil) { _, _ in stacks.isEven ? nil : .equal }
    }
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
        let available = Double(availablePaneLength), minimum = Double(flatPaneMinimum)
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
        let stacks: BrowserSplitStacks?
        let panes: [ObjectIdentifier]
    }
    private var dividerAccessibilityElements: [DividerAccessibilityElement] = []
    private var createdDividerElements: [DividerAccessibilityElement] = []
    private var retiredDividerElements: [DividerAccessibilityElement] = []
    private var announcedDividerBasis: DividerAnnouncementBasis?
    private var dividerSettleTimer: Timer?
    var scheduleDividerSettle: (@escaping @MainActor () -> Void) -> Timer = { settle in
        let timer = Timer(timeInterval: 0.3, repeats: false) { _ in MainActor.assumeIsolated { settle() } }
        RunLoop.main.add(timer, forMode: .default)
        return timer
    }
    private var dividerAnnouncementBasis: DividerAnnouncementBasis {
        DividerAnnouncementBasis(orientation: savedOrientation, factors: savedFactors, stacks: activeStacks,
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
        dividerSettleTimer = scheduleDividerSettle { [weak self] in self?.announceDividerChanges() }
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
        private var stackedDivider: SplitStackDivider? { owner?.activeStacks?.divider(after: index) }
        private var position: (value: Double, minimum: Double, maximum: Double)? {
            guard isAvailable, let owner else { return nil }
            if let divider = stackedDivider {
                guard let current = owner.stackedShares(divider.slot) else { return nil }
                return SplitStackGeometry.splitterPosition(shares: current.shares, index: divider.index, minimum: current.minimum)
            }
            guard let current = owner.adjustableShares else { return nil }
            return SplitStackGeometry.splitterPosition(shares: current.shares, index: index, minimum: current.minimum)
        }
        private var isAvailable: Bool { owner?.dividerRects.indices.contains(index) == true }
        override func isAccessibilityElement() -> Bool { isAvailable }
        override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
        override func accessibilityLabel() -> String? {
            if let owner, let divider = stackedDivider {
                return SplitStackGeometry.splitterLabel(index: index, count: owner.dividerRects.count,
                                                        slot: divider.slot, orientation: owner.savedOrientation)
            }
            return (owner?.dividerRects.count ?? 0) > 1 ? "Split View Divider \(index + 1)" : "Split View Divider"
        }
        override func accessibilityHelp() -> String? { "Increase or decrease to resize the pages on either side." }
        override func accessibilityValue() -> Any? { reportedValue.map { NSNumber(value: $0) } }
        override func accessibilityMinValue() -> Any? { position.map { NSNumber(value: ($0.minimum * 100).rounded()) } }
        override func accessibilityMaxValue() -> Any? { position.map { NSNumber(value: ($0.maximum * 100).rounded()) } }
        override func accessibilityValueDescription() -> String? {
            position?.value.formatted(.percent.precision(.fractionLength(0)))
        }
        override func accessibilityOrientation() -> NSAccessibilityOrientation {
            if let stacked = owner?.stackedDividers, stacked.indices.contains(index) {
                return stacked[index].isVerticalBar ? .vertical : .horizontal
            }
            return owner?.isVertical == false ? .horizontal : .vertical
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
