import AppKit
import CoreImage
import ParcCore

struct HistorySwipeOverlayRow: Equatable {
    var title: String
    var favicon: NSImage?
}

@MainActor final class HistorySwipeOverlayView: NSView {
    typealias M = HistorySwipeOverlayMetrics

    var palette: ThemeChromePalette? {
        didSet { if palette != oldValue { appearance = palette?.contentAppearance } }
    }
    private(set) var current = HistorySwipeOverlayRow(title: "", favicon: nil)
    private(set) var back: [HistorySwipeOverlayRow] = []
    private(set) var forward: [HistorySwipeOverlayRow] = []
    private var model = HistorySwipeOverlayModel()
    private var rowsRevision = 0
    private var shownRows: (direction: HistorySwipeDirection, revision: Int)?
    private var chevronDirection: HistorySwipeDirection?
    private let shadowView = NSView()
    private let shadowLayer = CALayer()
    private let capsule = NSView()
    private let material = NSVisualEffectView()
    private let wash = NSView()
    private let list = HistorySwipeOverlayListView()
    private let chevron = NSImageView()
    private let frames = ViewDisplayFrameDriver()

    private let reducesMotion: () -> Bool
    private let now: () -> TimeInterval

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect,
                  reducesMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
                  now: CACurrentMediaTime)
    }

    init(frame frameRect: NSRect, reducesMotion: @escaping () -> Bool, now: @escaping () -> TimeInterval) {
        self.reducesMotion = reducesMotion
        self.now = now
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        shadowView.wantsLayer = true
        shadowView.layer?.masksToBounds = false
        shadowView.layer?.addSublayer(shadowLayer)
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowRadius = M.shadowRadius
        shadowLayer.shadowOffset = CGSize(width: 0, height: -M.shadowDrop)
        capsule.wantsLayer = true
        capsule.layerUsesCoreImageFilters = true
        capsule.layer?.masksToBounds = true
        capsule.layer?.cornerCurve = .continuous
        capsule.layer?.borderWidth = M.ringWidth
        material.material = .popover
        material.blendingMode = .withinWindow
        material.state = .active
        wash.wantsLayer = true
        list.wantsLayer = true
        list.layerUsesCoreImageFilters = true
        chevron.wantsLayer = true
        chevron.layerUsesCoreImageFilters = true
        chevron.imageScaling = .scaleProportionallyUpOrDown
        chevron.contentTintColor = .labelColor
        for view in [material, wash, list, chevron] { capsule.addSubview(view) }
        addSubview(shadowView)
        addSubview(capsule)
        hideIndicator()
        applyLook()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyLook()
        guard window == nil else { return }
        frames.stop()
        model.reset()
        hideIndicator()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLook()
    }

    override func layout() {
        super.layout()
        render()
    }

    func setRows(current: HistorySwipeOverlayRow, back: [HistorySwipeOverlayRow], forward: [HistorySwipeOverlayRow]) {
        guard current != self.current || back != self.back || forward != self.forward else { return }
        self.current = current
        self.back = back
        self.forward = forward
        rowsRevision += 1
        render()
    }

    func handle(_ output: HistorySwipeOutput) {
        if case .begin = output { model.prefersReducedMotion = reducesMotion() }
        if case let .begin(direction) = output { showChevron(direction) }
        let haptic = model.receive(output, at: now())
        if let haptic { perform(haptic) }
        render()
        guard model.isAnimating, window != nil else { return }
        frames.start(in: self) { [weak self] in
            guard let self else { return false }
            self.model.advance(to: self.now())
            self.render()
            return self.model.isAnimating
        }
    }

    private func render() {
        model.backRows = back.count
        model.forwardRows = forward.count
        guard let frame = model.frame(in: bounds.size) else {
            hideIndicator()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let box = paneRect(frame.capsule)
        let radius = min(frame.cornerRadius, box.width / 2, box.height / 2)
        for view in [shadowView, capsule] {
            view.isHidden = false
            view.frame = box
            view.alphaValue = CGFloat(frame.opacity)
            scale(view, by: frame.scale)
        }
        shadowLayer.frame = CGRect(origin: .zero, size: box.size)
        shadowLayer.shadowPath = CGPath(roundedRect: shadowLayer.bounds, cornerWidth: radius, cornerHeight: radius,
                                        transform: nil)
        capsule.layer?.cornerRadius = radius
        blur(capsule, frame.blur)
        material.frame = capsule.bounds
        wash.frame = capsule.bounds
        wash.alphaValue = CGFloat(frame.wash)
        let center = local(frame.chevronCenter, in: frame.capsule)
        chevron.frame = NSRect(x: center.x - frame.chevronSize / 2, y: center.y - frame.chevronSize / 2,
                               width: frame.chevronSize, height: frame.chevronSize)
        chevron.alphaValue = CGFloat(frame.chevronOpacity)
        chevron.isHidden = frame.chevronOpacity <= 0.001
        scale(chevron, by: frame.chevronScale)
        blur(chevron, frame.chevronBlur)
        guard let rows = frame.list else {
            list.isHidden = true
            return
        }
        showRows(for: rows.direction)
        list.isHidden = false
        list.frame = local(rows.content, in: frame.capsule)
        list.alphaValue = CGFloat(rows.opacity)
        list.place(rows: (0..<rows.rows).map { local(rows.row($0), in: rows.content) },
                   highlight: local(rows.highlight, in: rows.content))
        let card = local(rows.card, in: rows.content)
        scale(list, by: rows.scale, about: CGPoint(x: card.midX, y: card.midY))
        blur(list, rows.blur)
    }

    private func showRows(for direction: HistorySwipeDirection) {
        guard shownRows?.direction != direction || shownRows?.revision != rowsRevision else { return }
        shownRows = (direction, rowsRevision)
        list.show([current] + (direction == .back ? back : forward))
    }

    private func showChevron(_ direction: HistorySwipeDirection) {
        guard chevronDirection != direction else { return }
        chevronDirection = direction
        chevron.image = NSImage(systemSymbolName: direction == .back ? "chevron.left" : "chevron.right",
                                accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: M.chevronPointSize, weight: .bold))
    }

    private func hideIndicator() {
        shadowView.isHidden = true
        capsule.isHidden = true
        list.isHidden = true
        for view in [shadowView, capsule, chevron, list] { scale(view, by: 1) }
        for view in [capsule, chevron, list] { blur(view, 0) }
    }

    private func applyLook() {
        let look = HistorySwipeOverlayLook(dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        capsule.layer?.borderColor = NSColor(white: look.ringWhite, alpha: look.ringAlpha).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.shadowOpacity = Float(look.shadowAlpha)
        CATransaction.commit()
        wash.layer?.backgroundColor = NSColor(white: 1, alpha: look.washAlpha).cgColor
        list.highlightColor = NSColor(white: look.highlightWhite, alpha: look.highlightAlpha)
    }

    private func perform(_ haptic: HistorySwipeOverlayModel.Haptic) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch haptic {
        case .levelChange: performer.perform(.levelChange, performanceTime: .default)
        case .generic: performer.perform(.generic, performanceTime: .now)
        case .alignment: performer.perform(.alignment, performanceTime: .now)
        }
    }

    private func paneRect(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func local(_ rect: CGRect, in container: CGRect) -> NSRect {
        NSRect(x: rect.minX - container.minX, y: container.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func local(_ point: CGPoint, in container: CGRect) -> NSPoint {
        NSPoint(x: point.x - container.minX, y: container.maxY - point.y)
    }

    private func scale(_ view: NSView, by amount: Double, about point: CGPoint? = nil) {
        guard let layer = view.layer else { return }
        guard abs(amount - 1) > 0.0001 else {
            if !CATransform3DIsIdentity(layer.transform) { layer.transform = CATransform3DIdentity }
            return
        }
        let size = layer.bounds.size
        let pivot = point ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = pivot.x - layer.anchorPoint.x * size.width, dy = pivot.y - layer.anchorPoint.y * size.height
        var transform = CATransform3DMakeTranslation(dx, dy, 0)
        transform = CATransform3DScale(transform, CGFloat(amount), CGFloat(amount), 1)
        layer.transform = CATransform3DTranslate(transform, -dx, -dy, 0)
    }

    private func blur(_ view: NSView, _ radius: Double) {
        guard radius > 0.05, let filter = CIFilter(name: "CIGaussianBlur") else {
            if !view.contentFilters.isEmpty { view.contentFilters = [] }
            return
        }
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        view.contentFilters = [filter]
    }
}

@MainActor private final class HistorySwipeOverlayListView: NSView {
    private let highlight = NSView()
    private var rowViews: [HistorySwipeOverlayRowView] = []

    var highlightColor = NSColor.clear {
        didSet { highlight.layer?.backgroundColor = highlightColor.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = HistorySwipeOverlayMetrics.highlightRadius
        highlight.layer?.cornerCurve = .continuous
        addSubview(highlight)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ rows: [HistorySwipeOverlayRow]) {
        while rowViews.count < rows.count {
            let view = HistorySwipeOverlayRowView()
            addSubview(view)
            rowViews.append(view)
        }
        for (index, view) in rowViews.enumerated() {
            view.isHidden = index >= rows.count
            if index < rows.count { view.show(rows[index]) }
        }
    }

    func place(rows frames: [NSRect], highlight frame: NSRect) {
        highlight.frame = frame
        for (view, rect) in zip(rowViews, frames) where view.frame != rect { view.place(rect) }
    }
}

@MainActor private final class HistorySwipeOverlayRowView: NSView {
    typealias M = HistorySwipeOverlayMetrics

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = M.faviconRadius
        icon.layer?.cornerCurve = .continuous
        icon.layer?.masksToBounds = true
        title.font = .systemFont(ofSize: M.titleSize)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.cell?.usesSingleLineMode = true
        addSubview(icon)
        addSubview(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ row: HistorySwipeOverlayRow) {
        title.stringValue = row.title
        if let favicon = row.favicon {
            icon.image = favicon
            icon.contentTintColor = nil
        } else {
            icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
        }
    }

    func place(_ rect: NSRect) {
        frame = rect
        let side = M.faviconSize
        icon.frame = NSRect(x: M.cardInset, y: ((rect.height - side) / 2).rounded(), width: side, height: side)
        let x = M.cardInset + side + M.titleGap
        let height = ceil(title.intrinsicContentSize.height)
        title.frame = NSRect(x: x, y: ((rect.height - height) / 2).rounded(), width: max(0, rect.width - x - M.cardInset),
                             height: height)
    }
}
