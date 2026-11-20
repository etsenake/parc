import AppKit
import Combine

@MainActor
protocol NoteCanvasHeader: AnyObject {
    func canvasHeaderHeight(width: CGFloat, column: NSRect) -> CGFloat
}

@MainActor
final class NotePageCanvasView: NSView {
    private struct Anchor {
        var id: NoteBlockID
        var top: CGFloat
    }

    private struct Settle {
        var ids: [NoteBlockID]
        var origin: NSPoint
    }

    private struct ColumnResize {
        var key: NoteCanvasColumnHandle.Key
        var fractions: [CGFloat]
        var available: CGFloat
    }

    weak var editor: NotePageEditor?
    let overlayView: NSView = NoteCanvasOverlayView()
    var headerView: NSView? {
        didSet {
            guard headerView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let headerView { addSubview(headerView, positioned: .above, relativeTo: transientView) }
            invalidateCanvasLayout()
        }
    }
    var spaceFocus: NSColor? {
        didSet {
            dropIndicator.spaceFocus = spaceFocus
            for view in washViews.values { view.spaceFocus = spaceFocus }
        }
    }
    let layoutDidChange = PassthroughSubject<Void, Never>()
    let blockViewDidMaterialize = PassthroughSubject<NoteBlockView, Never>()
    private(set) var canvasLayout = NoteCanvasLayout.empty

    private let decorationView = NoteCanvasPassiveView()
    private let washView = NoteCanvasPassiveView()
    private let transientView = NoteCanvasPassiveView()
    private let dropIndicator = NoteCanvasDropIndicatorView()
    private let measurer = NoteCanvasMeasurer()
    private var views: [NoteBlockID: NoteBlockView] = [:]
    private var decorationViews: [NoteCanvasDecoration.Key: NoteCanvasDecorationView] = [:]
    private var washViews: [NoteBlockID: NoteCanvasDecorationView] = [:]
    private var columnHandles: [NoteCanvasColumnHandle.Key: NoteCanvasColumnHandle] = [:]
    private var isDirty = true
    private var wantsAnimation = false
    private var isLayingOut = false
    private var pendingSettle: Settle?
    private var columnOverrides: [NoteBlockID: [CGFloat]] = [:]
    private var columnResize: ColumnResize?
    private var dragSources: Set<NoteBlockID> = []
    private var extraWash: Set<NoteBlockID> = []
    private var metricsCache: (settings: NotePageSettings, metrics: NoteCanvasMetrics)?
    private var appliedSettings: NotePageSettings?
    private var syncMeasureBudget = 0
    private var subscriptions: Set<AnyCancellable> = []
    private var clipObservers: [NSObjectProtocol] = []
    private var pointerTracking: NSTrackingArea?
    private var idleMeasureScheduled = false

    init(editor: NotePageEditor) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width]
        measurer.editor = editor
        addSubview(decorationView)
        addSubview(washView)
        addSubview(transientView)
        addSubview(overlayView)
        overlayView.addSubview(dropIndicator)
        editor.session.changes
            .sink { [weak self] change in
                guard change.kind == .selection else { return }
                self?.refreshWashes(animated: false)
            }
            .store(in: &subscriptions)
        NoteAnimation.observeReduceMotion(self) { [weak self] in self?.settleAnimations() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override var needsLayout: Bool {
        get { super.needsLayout }
        set {
            if newValue && !isLayingOut { isDirty = true }
            super.needsLayout = newValue
        }
    }

    var contentRect: NSRect {
        let metrics = currentMetrics()
        let column = metrics.pageColumn(width: bounds.width)
        return NSRect(x: column.x, y: 0, width: column.width, height: bounds.height)
    }

    var documentHeight: CGFloat {
        canvasLayout.contentBottom + max(canvasLayout.metrics.bottomInset,
                                         viewportHeight * canvasLayout.metrics.bottomViewportFraction)
    }

    var materializedViews: [NoteBlockView] {
        canvasLayout.entries.compactMap { views[$0.id] }
    }

    func reload() {
        for view in views.values {
            NoteCanvasMotion.settleAll(view)
            view.removeFromSuperview()
        }
        views.removeAll()
        for view in decorationViews.values { view.removeFromSuperview() }
        decorationViews.removeAll()
        for view in washViews.values { view.removeFromSuperview() }
        washViews.removeAll()
        for view in transientView.subviews { view.removeFromSuperview() }
        measurer.reset()
        canvasLayout = .empty
        appliedSettings = editor?.session.page.settings
        wantsAnimation = false
        invalidateCanvasLayout()
    }

    func apply(_ change: NotePageChange) {
        guard let editor else { return }
        let page = editor.session.page
        switch change.kind {
        case .selection:
            refreshWashes(animated: false)
            return
        case .replaced:
            reload()
            return
        case .settings:
            applySettings(page.settings)
        case .text:
            measurer.invalidate(change.blocks)
            if change.blocks.contains(where: { canvasLayout.blocks[$0]?.kind == .heading }) { measurer.invalidateContents() }
            if applyTextChange(change, page: page) { return }
        case .structure:
            measurer.invalidateAll()
            measurer.invalidateContents()
            wantsAnimation = true
        }
        invalidateCanvasLayout()
    }

    func invalidateCanvasLayout(animated: Bool = false) {
        if animated { wantsAnimation = true }
        isDirty = true
        super.needsLayout = true
    }

    func blockHeightDidChange(_ id: NoteBlockID) {
        measurer.forget(id)
        invalidateCanvasLayout()
    }

    func updateLayoutIfNeeded() {
        if isDirty { performLayout() }
    }

    override func layout() {
        super.layout()
        updateLayoutIfNeeded()
        pinUtilityViews()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.25
        super.setFrameSize(newSize)
        pinUtilityViews()
        if widthChanged { invalidateCanvasLayout() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeClipView()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for view in views.values { view.themeDidChange() }
    }

    override func updateTrackingAreas() {
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTracking = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        editor?.handles.pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        editor?.handles.pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        editor?.handles.pointerExited()
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor else { return }
        if editor.selection.canvasMouseDown(event) { return }
        let point = convert(event.locationInWindow, from: nil)
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if modifiers.isEmpty, isBelowContent(point) {
            clickBelowContent()
            return
        }
        super.mouseDown(with: event)
    }

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = []
        if let headerView { children.append(headerView) }
        children.append(contentsOf: materializedViews.filter { $0.block.kind != .columns && $0.block.kind != .column })
        let managed: [NSView] = [decorationView, washView, transientView, overlayView]
        for view in subviews where !(view is NoteBlockView) && view !== headerView && !managed.contains(where: { $0 === view }) {
            children.append(view)
        }
        children.append(contentsOf: overlayView.subviews.filter { !$0.isHidden && $0 !== dropIndicator })
        return children
    }

    func blockView(for id: NoteBlockID) -> NoteBlockView? {
        updateLayoutIfNeeded()
        guard let entry = canvasLayout.entry(id) else { return nil }
        return materialize(entry)
    }

    func existingBlockView(for id: NoteBlockID) -> NoteBlockView? { views[id] }

    func textHost(for position: NotePosition) -> NoteTextHost? {
        blockView(for: position.block)?.textHost(for: position.field)
    }

    func frame(of id: NoteBlockID) -> NSRect? {
        updateLayoutIfNeeded()
        return canvasLayout.frame(of: id)
    }

    func outerFrame(of id: NoteBlockID) -> NSRect? {
        updateLayoutIfNeeded()
        return canvasLayout.outerFrame(of: id)
    }

    func blockID(at point: NSPoint) -> NoteBlockID? {
        updateLayoutIfNeeded()
        return canvasLayout.blockID(at: point)
    }

    func blockIDs(in rect: NSRect) -> [NoteBlockID] {
        updateLayoutIfNeeded()
        return canvasLayout.blockIDs(in: rect)
    }

    func gutterRect(for id: NoteBlockID) -> NSRect? {
        updateLayoutIfNeeded()
        return canvasLayout.gutterRect(for: id)
    }

    func handleAnchorY(for id: NoteBlockID) -> CGFloat {
        if let view = views[id] { return view.handleAnchorY }
        guard let entry = canvasLayout.entry(id), let block = canvasLayout.blocks[id] else { return 14 }
        let metrics = canvasLayout.metrics
        switch block.kind {
        case .heading:
            let padding: CGFloat = [22, 16, 12, 8, 6, 6][min(max(block.props.level, 1), 6) - 1]
            return padding + metrics.headingLineHeight(block.props.level) / 2
        case .callout: return metrics.calloutInsets.top + metrics.bodyLineHeight / 2
        case .divider, .image, .video, .embed, .table, .code, .bookmark, .equation: return min(entry.frame.height / 2, 14)
        default: return NoteTheme.blockVerticalPadding + metrics.bodyLineHeight / 2
        }
    }

    func listOrdinal(of id: NoteBlockID) -> Int? { canvasLayout.listOrdinal(of: id) }

    func scrollBlockToVisible(_ id: NoteBlockID) {
        updateLayoutIfNeeded()
        if views[id] == nil, let entry = canvasLayout.entry(id), let block = canvasLayout.blocks[id],
           measurer.cachedHeight(of: block, width: entry.frame.width) == nil,
           let measured = measurer.measureNow(block, width: entry.frame.width), abs(measured.rounded(.up) - entry.frame.height) > 0.5 {
            invalidateCanvasLayout()
            updateLayoutIfNeeded()
        }
        guard let frame = canvasLayout.frame(of: id) else { return }
        let target = NSRect(x: frame.minX, y: frame.minY - 40, width: frame.width, height: min(frame.height, 400) + 80)
        if !visibleRect.contains(target) { scrollToVisible(target) }
        materializeVisibleRegion()
    }

    func showDropIndicator(_ target: NoteCanvasDropTarget?) {
        dropIndicator.spaceFocus = spaceFocus
        dropIndicator.show(target)
    }

    func dropTarget(at point: NSPoint, dragging ids: [NoteBlockID]) -> NoteCanvasDropTarget? {
        dropTarget(at: point, dragging: ids, leadingX: nil)
    }

    func dropTarget(at point: NSPoint, dragging ids: [NoteBlockID], leadingX: CGFloat?) -> NoteCanvasDropTarget? {
        updateLayoutIfNeeded()
        return canvasLayout.dropTarget(at: point, dragging: ids, leadingX: leadingX)
    }

    func setDragSources(_ ids: [NoteBlockID]) {
        let next = Set(ids)
        guard next != dragSources else { return }
        dragSources = next
        let dimmed = dimmedBlocks()
        for (id, view) in views { view.alphaValue = dimmed.contains(id) ? 0.4 : 1 }
        refreshWashes(animated: false)
    }

    func setSelectionWash(_ ids: Set<NoteBlockID>) {
        guard ids != extraWash else { return }
        extraWash = ids
        refreshWashes(animated: false)
    }

    func prepareDropSettle(_ ids: [NoteBlockID], ghostOrigin: NSPoint) {
        pendingSettle = Settle(ids: ids, origin: ghostOrigin)
        DispatchQueue.main.async { [weak self] in self?.pendingSettle = nil }
    }

    func clickBelowContent() {
        guard let editor, !editor.isReadOnly else { return }
        let page = editor.session.page
        if let last = page.blocks.last, last.kind == .paragraph, last.text.isEmpty, last.children.isEmpty {
            editor.session.setSelection(.caret(NotePosition(last.id, 0)))
            editor.focus(NotePosition(last.id, 0))
            return
        }
        let paragraph = NoteBlock.paragraph()
        editor.session.insertBlocks([paragraph], .top(page.blocks.count), select: .caret(NotePosition(paragraph.id, 0)))
        updateLayoutIfNeeded()
        editor.focus(NotePosition(paragraph.id, 0))
    }

    func beginColumnResize(_ key: NoteCanvasColumnHandle.Key) -> Bool {
        guard let editor, !editor.isReadOnly, let row = canvasLayout.columnsRows[key.columns],
              key.divider + 1 < row.fractions.count else { return false }
        columnResize = ColumnResize(key: key, fractions: row.fractions, available: row.available)
        return true
    }

    func updateColumnResize(delta: CGFloat) {
        guard let resize = columnResize else { return }
        columnOverrides[resize.key.columns] = NoteCanvasLayout.resizedFractions(
            resize.fractions, divider: resize.key.divider, delta: delta, available: resize.available,
            minimumWidth: canvasLayout.metrics.minimumColumnWidth)
        invalidateCanvasLayout()
        updateLayoutIfNeeded()
    }

    func endColumnResize(commit: Bool) {
        guard let resize = columnResize else { return }
        columnResize = nil
        let fractions = columnOverrides.removeValue(forKey: resize.key.columns)
        guard commit, let editor, let fractions, fractions != resize.fractions else {
            invalidateCanvasLayout()
            return
        }
        let widths = fractions.map { (Double($0) * 10_000).rounded() / 10_000 }
        editor.session.updateBlock(resize.key.columns, name: "Resize Columns") { block in
            for index in block.children.indices where index < widths.count { block.children[index].props.width = widths[index] }
        }
    }

    private var viewportHeight: CGFloat {
        enclosingScrollView?.contentView.bounds.height ?? bounds.height
    }

    private var viewport: NSRect {
        let visible = visibleRect
        return visible.isEmpty ? bounds : visible
    }

    private func currentMetrics() -> NoteCanvasMetrics {
        let settings = editor?.session.page.settings ?? NotePageSettings()
        if let cached = metricsCache, cached.settings.font == settings.font, cached.settings.smallText == settings.smallText,
           cached.settings.fullWidth == settings.fullWidth {
            return cached.metrics
        }
        let metrics = NoteCanvasMetrics.make(for: settings)
        metricsCache = (settings, metrics)
        return metrics
    }

    private func pinUtilityViews() {
        for view in [decorationView, washView, transientView, overlayView] where view.frame != bounds {
            NoteAnimation.withoutAnimation { view.frame = bounds }
        }
    }

    private func observeClipView() {
        for observer in clipObservers { NotificationCenter.default.removeObserver(observer) }
        clipObservers = []
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        clipObservers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip,
                                                                    queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipDidScroll() }
        })
        clipObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip,
                                                                    queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipDidResize() }
        })
        clipDidResize()
    }

    private func clipDidResize() {
        guard let clip = superview as? NSClipView else { return }
        let width = clip.bounds.width
        if abs(frame.width - width) > 0.25 { setFrameSize(NSSize(width: width, height: max(frame.height, clip.bounds.height))) }
        updateDocumentSize()
        materializeVisibleRegion()
    }

    private func clipDidScroll() {
        guard !isLayingOut else { return }
        materializeVisibleRegion()
    }

    private func updateDocumentSize() {
        let height = canvasLayout.documentHeight(viewportHeight: viewportHeight).rounded(.up)
        guard abs(frame.height - height) > 0.25, superview is NSClipView else { return }
        super.setFrameSize(NSSize(width: frame.width, height: height))
        pinUtilityViews()
    }

    private func applySettings(_ settings: NotePageSettings) {
        let previous = appliedSettings
        appliedSettings = settings
        let readOnly = editor?.isReadOnly ?? false
        for view in views.values where view.isReadOnly != readOnly { view.isReadOnly = readOnly }
        guard let previous, previous.font != settings.font || previous.smallText != settings.smallText else { return }
        metricsCache = nil
        measurer.reset()
        rebuildMaterializedViews()
    }

    private func rebuildMaterializedViews() {
        guard let editor else { return }
        let focusedID = views.first { isFirstResponderInside($0.value) }?.key
        for view in views.values {
            NoteCanvasMotion.settleAll(view)
            view.removeFromSuperview()
        }
        views.removeAll()
        invalidateCanvasLayout()
        updateLayoutIfNeeded()
        if let focusedID, case .text(_, let head) = editor.session.selection, head.block == focusedID {
            editor.focus(head)
        }
    }

    private func applyTextChange(_ change: NotePageChange, page: NotePage) -> Bool {
        guard !isDirty, !canvasLayout.isEmpty else {
            updateViews(for: change.blocks, page: page)
            return false
        }
        var heightChanged = false
        var headingChanged = false
        var blocks: [NoteBlock] = []
        for id in change.blocks {
            guard let block = page.block(id) else { heightChanged = true; continue }
            views[id]?.update(block)
            blocks.append(block)
            guard let entry = canvasLayout.entry(id) else { continue }
            if block.kind == .heading { headingChanged = true }
            let height = measurer.height(of: block, width: entry.frame.width, live: views[id])
            if abs(height.rounded(.up) - entry.frame.height) > 0.25 { heightChanged = true }
        }
        if headingChanged && canvasLayout.entries.contains(where: { $0.kind == .tableOfContents }) { heightChanged = true }
        if heightChanged {
            invalidateCanvasLayout()
            return true
        }
        for block in blocks { canvasLayout.refresh(block) }
        return true
    }

    private func updateViews(for ids: Set<NoteBlockID>, page: NotePage) {
        for id in ids {
            guard let view = views[id], let block = page.block(id), !needsNewView(view, for: block) else { continue }
            view.update(block)
        }
    }

    private func needsNewView(_ view: NoteBlockView, for block: NoteBlock) -> Bool {
        block.kind != view.block.kind && !(block.kind.hasRichText && view.block.kind.hasRichText)
    }

    private func refocusAfterLayout(_ id: NoteBlockID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.editor, case .text(_, let head) = editor.session.selection, head.block == id else { return }
            editor.focus(head)
        }
    }

    private func headerHeight(width: CGFloat, column: NSRect) -> CGFloat {
        guard let headerView else { return 0 }
        if let header = headerView as? NoteCanvasHeader { return max(0, header.canvasHeaderHeight(width: width, column: column)) }
        let fitting = headerView.fittingSize.height
        return fitting > 0 ? fitting : headerView.frame.height
    }

    private func measuredHeight(_ block: NoteBlock, width: CGFloat, previous: NoteCanvasLayout) -> CGFloat {
        if let live = views[block.id], !needsNewView(live, for: block) {
            if live.block != block { live.update(block) }
            return measurer.height(of: block, width: width, live: live)
        }
        if let cached = measurer.cachedHeight(of: block, width: width) { return cached }
        let nearby = previous.frame(of: block.id).map { $0.intersects(materializationRect()) } ?? true
        if nearby, syncMeasureBudget > 0, NoteCanvasMeasurer.measuresOffscreen(block.kind) {
            syncMeasureBudget -= 1
            if let measured = measurer.measureNow(block, width: width) { return measured }
        }
        return measurer.height(of: block, width: width, live: nil)
    }

    private func materializationRect() -> NSRect {
        let visible = viewport
        return visible.insetBy(dx: -visible.width, dy: -max(800, visible.height))
    }

    private func retentionRect() -> NSRect {
        let visible = viewport
        return visible.insetBy(dx: -visible.width, dy: -max(2400, visible.height * 3))
    }

    private func performLayout() {
        guard let editor, !isLayingOut, bounds.width >= 1 else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        for pass in 0..<3 {
            isDirty = false
            let corrected = layoutPass(editor: editor, animate: pass == 0)
            if !corrected { break }
        }
        isDirty = false
        scheduleIdleMeasurement()
        layoutDidChange.send()
    }

    private func layoutPass(editor: NotePageEditor, animate: Bool) -> Bool {
        let page = editor.session.page
        let metrics = currentMetrics()
        measurer.use(page.settings, metrics: metrics)
        if appliedSettings == nil { appliedSettings = page.settings }
        let width = bounds.width
        let column = metrics.pageColumn(width: width)
        let columnRect = NSRect(x: column.x, y: 0, width: column.width, height: bounds.height)
        let header = headerHeight(width: width, column: columnRect)
        let previous = canvasLayout
        let shouldAnimate = animate && wantsAnimation && !previous.isEmpty && window != nil
        wantsAnimation = false
        let anchor = captureAnchor(in: previous)
        syncMeasureBudget = 160
        let next = NoteCanvasLayout(
            page: page, width: width, headerHeight: header, metrics: metrics, columnFractions: columnOverrides,
            measure: NoteCanvasMeasure(
                height: { [unowned self] block, width in self.measuredHeight(block, width: width, previous: previous) },
                childIndent: { [unowned self] block in self.measurer.childIndent(of: block, live: self.views[block.id]) }))
        canvasLayout = next
        if let headerView {
            let frame = NSRect(x: 0, y: 0, width: width, height: header)
            if headerView.frame != frame { NoteAnimation.withoutAnimation { headerView.frame = frame } }
        }
        updateDocumentSize()
        let scrollAdjust = restore(anchor, in: next)
        let transition = shouldAnimate ? NoteCanvasTransition(from: previous, to: next) : NoteCanvasTransition()
        let animated = transition.isStructural
        let settle = animated ? settleDeltas(previous: previous, next: next, scrollAdjust: scrollAdjust) : [:]
        pendingSettle = nil
        let snapshots = animated ? captureDepartures(previous: previous, next: next, transition: transition, scrollAdjust: scrollAdjust) : []
        dropDeparted(next: next)
        let created = syncViews(next: next)
        if animated { runTransition(transition, settle: settle, scrollAdjust: scrollAdjust) }
        play(snapshots)
        syncDecorations(previous: previous, animated: animated && abs(scrollAdjust) < 0.5, transition: transition)
        refreshWashes(animated: animated && abs(scrollAdjust) < 0.5)
        syncColumnHandles()
        return needsCorrection(created, in: next)
    }

    private func needsCorrection(_ created: [NoteBlockID], in layout: NoteCanvasLayout) -> Bool {
        for id in created {
            guard let view = views[id], let entry = layout.entry(id), let block = layout.blocks[id],
                  block.kind != .columns, block.kind != .column else { continue }
            let height = measurer.height(of: block, width: entry.frame.width, live: view).rounded(.up)
            if abs(height - entry.frame.height) > 0.5 { return true }
        }
        return false
    }

    private func captureAnchor(in layout: NoteCanvasLayout) -> [Anchor] {
        guard !layout.isEmpty, superview is NSClipView else { return [] }
        let visible = viewport
        guard let first = layout.flows.first?.first, visible.minY > layout.entries[first].frame.minY else { return [] }
        var result: [Anchor] = []
        for index in layout.flows[0] {
            let entry = layout.entries[index]
            guard entry.frame.maxY > visible.minY else { continue }
            result.append(Anchor(id: entry.id, top: entry.frame.minY))
            if result.count >= 8 || entry.frame.minY > visible.maxY { break }
        }
        return result
    }

    private func restore(_ anchors: [Anchor], in layout: NoteCanvasLayout) -> CGFloat {
        guard let clip = superview as? NSClipView, let scrollView = enclosingScrollView else { return 0 }
        for anchor in anchors {
            guard let frame = layout.frame(of: anchor.id) else { continue }
            let delta = frame.minY - anchor.top
            guard abs(delta) > 0.25 else { return 0 }
            let origin = clip.bounds.origin
            let target = min(max(0, origin.y + delta), max(0, bounds.height - clip.bounds.height))
            let applied = target - origin.y
            guard abs(applied) > 0.25 else { return 0 }
            clip.scroll(to: NSPoint(x: origin.x, y: target))
            scrollView.reflectScrolledClipView(clip)
            return applied
        }
        return 0
    }

    private func settleDeltas(previous: NoteCanvasLayout, next: NoteCanvasLayout, scrollAdjust: CGFloat) -> [NoteBlockID: CGVector] {
        guard let settle = pendingSettle, let first = settle.ids.first(where: { previous.frame(of: $0) != nil }),
              let anchor = previous.frame(of: first) else { return [:] }
        let shift = CGVector(dx: settle.origin.x - anchor.minX, dy: settle.origin.y - anchor.minY)
        var result: [NoteBlockID: CGVector] = [:]
        for id in settle.ids {
            guard let index = next.index(of: id) else { continue }
            for entry in next.entries[index..<next.entries[index].subtreeEnd] {
                guard let old = previous.frame(of: entry.id) else { continue }
                result[entry.id] = CGVector(dx: old.minX + shift.dx - entry.frame.minX,
                                            dy: old.minY + shift.dy + scrollAdjust - entry.frame.minY)
            }
        }
        return result
    }

    private func captureDepartures(previous: NoteCanvasLayout, next: NoteCanvasLayout, transition: NoteCanvasTransition,
                                   scrollAdjust: CGFloat) -> [(NoteCanvasSnapshotView, NoteCanvasTransition.Group?)] {
        let visible = viewport.offsetBy(dx: 0, dy: -scrollAdjust).insetBy(dx: 0, dy: -120)
        var result: [(NoteCanvasSnapshotView, NoteCanvasTransition.Group?)] = []
        var budget = 40
        for id in transition.removed where !transition.merged.contains(id) {
            guard budget > 0, let view = views[id], let frame = previous.frame(of: id), frame.intersects(visible),
                  let snapshot = NoteCanvasSnapshotView(capturing: view) else { continue }
            budget -= 1
            snapshot.frame = frame.offsetBy(dx: 0, dy: scrollAdjust)
            result.append((snapshot, nil))
        }
        for group in transition.concealed {
            let edge = next.frame(of: group.owner)?.maxY ?? group.top + scrollAdjust
            for id in group.ids {
                guard budget > 0, let view = views[id], let frame = previous.frame(of: id), frame.intersects(visible),
                      let snapshot = NoteCanvasSnapshotView(capturing: view) else { continue }
                budget -= 1
                snapshot.frame = frame.offsetBy(dx: 0, dy: edge - group.top)
                result.append((snapshot, NoteCanvasTransition.Group(owner: group.owner, ids: [id], top: edge, height: group.height)))
            }
        }
        return result
    }

    private func play(_ snapshots: [(NoteCanvasSnapshotView, NoteCanvasTransition.Group?)]) {
        for (snapshot, group) in snapshots {
            transientView.addSubview(snapshot)
            if let group {
                NoteCanvasMotion.reveal(snapshot, edge: group.top, height: group.height, expanding: false) { [weak snapshot] in
                    snapshot?.removeFromSuperview()
                }
            } else {
                NoteCanvasMotion.vanish(snapshot) { [weak snapshot] in snapshot?.removeFromSuperview() }
            }
        }
    }

    private func dropDeparted(next: NoteCanvasLayout) {
        for id in Array(views.keys) where next.index(of: id) == nil { discard(id) }
    }

    private func syncViews(next: NoteCanvasLayout) -> [NoteBlockID] {
        let window = materializationRect()
        var created: [NoteBlockID] = []
        for entry in next.entries {
            let box = entry.kind == .callout ? entry.outerFrame : entry.frame
            if let view = views[entry.id] {
                guard let block = next.blocks[entry.id], needsNewView(view, for: block) else {
                    place(view, entry: entry, block: next.blocks[entry.id])
                    continue
                }
                let focused = isFirstResponderInside(view)
                discard(entry.id)
                if (focused || box.intersects(window)), materialize(entry) != nil { created.append(entry.id) }
                if focused { refocusAfterLayout(entry.id) }
            } else if box.intersects(window) {
                if materialize(entry) != nil { created.append(entry.id) }
            }
        }
        let keep = retentionRect()
        for (id, view) in views {
            guard let entry = next.entry(id), !entry.outerFrame.intersects(keep), !isPinned(view) else { continue }
            discard(id)
        }
        return created
    }

    private func materializeVisibleRegion() {
        guard !canvasLayout.isEmpty, !isDirty else { return }
        let window = materializationRect()
        var created: [NoteBlockID] = []
        for entry in canvasLayout.entries where views[entry.id] == nil {
            let box = entry.kind == .callout ? entry.outerFrame : entry.frame
            if box.intersects(window), materialize(entry) != nil { created.append(entry.id) }
        }
        let keep = retentionRect()
        for (id, view) in views {
            guard let entry = canvasLayout.entry(id), !entry.outerFrame.intersects(keep), !isPinned(view) else { continue }
            discard(id)
        }
        if needsCorrection(created, in: canvasLayout) {
            invalidateCanvasLayout()
            updateLayoutIfNeeded()
        } else if !created.isEmpty {
            syncDecorations(previous: canvasLayout, animated: false, transition: NoteCanvasTransition())
            refreshWashes(animated: false)
            syncColumnHandles()
        }
    }

    @discardableResult
    private func materialize(_ entry: NoteCanvasEntry) -> NoteBlockView? {
        if let view = views[entry.id] { return view }
        guard let editor, let block = canvasLayout.blocks[entry.id] ?? editor.session.page.block(entry.id) else { return nil }
        let view = editor.makeBlockView(for: block)
        views[entry.id] = view
        place(view, entry: entry, block: nil)
        addSubview(view, positioned: .below, relativeTo: overlayView)
        if dimmedBlocks().contains(entry.id) { view.alphaValue = 0.4 }
        if case .blocks(let ids) = editor.session.selection, ids.contains(entry.id) { view.setBlockSelected(true, animated: false) }
        blockViewDidMaterialize.send(view)
        editor.selection.blockViewDidAppear(view)
        return view
    }

    private func place(_ view: NoteBlockView, entry: NoteCanvasEntry, block: NoteBlock?) {
        let frame = entry.frame
        if view.frame != frame { NoteAnimation.withoutAnimation { view.frame = frame } }
        if let block, block != view.block { view.update(block) }
    }

    private func discard(_ id: NoteBlockID) {
        guard let view = views.removeValue(forKey: id) else { return }
        NoteCanvasMotion.settleAll(view)
        view.removeFromSuperview()
    }

    private func isPinned(_ view: NoteBlockView) -> Bool {
        if isFirstResponderInside(view) { return true }
        if view.textHosts.contains(where: { $0.textView.hasMarkedText() }) { return true }
        return dragSources.contains(view.blockID)
    }

    private func isFirstResponderInside(_ view: NSView) -> Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === view || responder.isDescendant(of: view)
    }

    private func dimmedBlocks() -> Set<NoteBlockID> {
        guard !dragSources.isEmpty else { return [] }
        var result = Set<NoteBlockID>()
        for id in dragSources {
            guard let index = canvasLayout.index(of: id) else { continue }
            for entry in canvasLayout.entries[index..<canvasLayout.entries[index].subtreeEnd] { result.insert(entry.id) }
        }
        return result
    }

    private func runTransition(_ transition: NoteCanvasTransition, settle: [NoteBlockID: CGVector], scrollAdjust: CGFloat) {
        let visible = viewport.insetBy(dx: 0, dy: -200)
        var revealed = Set<NoteBlockID>()
        for group in transition.revealed {
            for id in group.ids {
                revealed.insert(id)
                guard let view = views[id], view.frame.intersects(visible) else { continue }
                NoteCanvasMotion.reveal(view, edge: group.top, height: group.height, expanding: true)
            }
        }
        for id in transition.inserted where !revealed.contains(id) {
            guard let view = views[id], view.frame.intersects(visible) else { continue }
            NoteCanvasMotion.appear(view)
        }
        for (id, delta) in settle {
            guard let view = views[id] else { continue }
            NoteCanvasMotion.settle(view, by: delta)
        }
        for (id, delta) in transition.moved where settle[id] == nil && !revealed.contains(id) {
            guard let view = views[id] else { continue }
            let shifted = CGVector(dx: delta.dx, dy: delta.dy + scrollAdjust)
            let start = view.frame.offsetBy(dx: shifted.dx, dy: shifted.dy)
            guard start.intersects(visible) || view.frame.intersects(visible) else { continue }
            NoteCanvasMotion.slide(view, by: shifted, spring: .reorder)
        }
    }

    private func syncDecorations(previous: NoteCanvasLayout, animated: Bool, transition: NoteCanvasTransition) {
        let wanted = canvasLayout.decorations(in: retentionRect())
        var seen = Set<NoteCanvasDecoration.Key>()
        var ordered: [NSView] = []
        let inserted = Set(transition.inserted)
        for decoration in wanted {
            seen.insert(decoration.key)
            let frame = decoration.rect.integral
            if let view = decorationViews[decoration.key] {
                view.look = .decoration(decoration.style)
                if view.frame != frame {
                    if animated { NoteAnimation.slide(view, to: frame, spring: .reorder) }
                    else { NoteAnimation.withoutAnimation { view.frame = frame } }
                }
                ordered.append(view)
            } else {
                let view = NoteCanvasDecorationView(look: .decoration(decoration.style))
                view.frame = frame
                decorationViews[decoration.key] = view
                ordered.append(view)
                if animated && inserted.contains(decoration.key.owner) {
                    decorationView.addSubview(view)
                    NoteCanvasMotion.appear(view)
                }
            }
        }
        let removed = Set(transition.removed)
        for (key, view) in decorationViews where !seen.contains(key) {
            decorationViews[key] = nil
            if animated && removed.contains(key.owner) && !transition.merged.contains(key.owner) {
                NoteCanvasMotion.vanish(view) { [weak view] in view?.removeFromSuperview() }
            } else {
                view.removeFromSuperview()
            }
        }
        let current = decorationView.subviews.filter { subview in decorationViews.values.contains { $0 === subview } }
        if current.count != ordered.count || zip(current, ordered).contains(where: { $0 !== $1 }) {
            let leaving = decorationView.subviews.filter { subview in !ordered.contains { $0 === subview } }
            decorationView.subviews = leaving + ordered
        }
    }

    private func refreshWashes(animated: Bool) {
        guard let editor, !canvasLayout.isEmpty else {
            for view in washViews.values { view.removeFromSuperview() }
            washViews.removeAll()
            return
        }
        var ids = extraWash.union(dragSources)
        if case .blocks(let selected) = editor.session.selection { ids.formUnion(selected) }
        let washes = canvasLayout.washRects(for: ids)
        var seen = Set<NoteBlockID>()
        for wash in washes {
            seen.insert(wash.key)
            let frame = wash.rect.integral
            if let view = washViews[wash.key] {
                if view.frame != frame {
                    if animated { NoteAnimation.slide(view, to: frame, spring: .reorder) }
                    else { NoteAnimation.withoutAnimation { view.frame = frame } }
                }
            } else {
                let view = NoteCanvasDecorationView(look: .wash)
                view.spaceFocus = spaceFocus
                view.frame = frame
                washViews[wash.key] = view
                washView.addSubview(view)
            }
        }
        for (key, view) in washViews where !seen.contains(key) {
            washViews[key] = nil
            view.removeFromSuperview()
        }
    }

    private func syncColumnHandles() {
        let readOnly = editor?.isReadOnly ?? true
        let region = retentionRect()
        var seen = Set<NoteCanvasColumnHandle.Key>()
        if !readOnly {
            for row in canvasLayout.columnsRows.values where row.frame.intersects(region) && row.columns.count > 1 {
                for divider in 0..<(row.columns.count - 1) {
                    let key = NoteCanvasColumnHandle.Key(columns: row.id, divider: divider)
                    seen.insert(key)
                    let gap = row.gapRect(after: divider)
                    let frame = NSRect(x: (gap.midX - NoteCanvasColumnHandle.hitWidth / 2).rounded(), y: gap.minY,
                                       width: NoteCanvasColumnHandle.hitWidth, height: gap.height)
                    let handle = columnHandles[key] ?? {
                        let made = NoteCanvasColumnHandle(key: key, canvas: self)
                        columnHandles[key] = made
                        overlayView.addSubview(made, positioned: .above, relativeTo: dropIndicator)
                        return made
                    }()
                    if handle.frame != frame {
                        NoteAnimation.withoutAnimation { handle.frame = frame }
                        window?.invalidateCursorRects(for: handle)
                    }
                }
            }
        }
        for (key, handle) in columnHandles where !seen.contains(key) && columnResize?.key != key {
            handle.cancelDrag()
            columnHandles[key] = nil
            handle.removeFromSuperview()
        }
    }

    private func scheduleIdleMeasurement() {
        guard measurer.hasPending, !idleMeasureScheduled else { return }
        idleMeasureScheduled = true
        perform(#selector(measureIdle), with: nil, afterDelay: 0.02, inModes: [.default])
    }

    @objc private func measureIdle() {
        idleMeasureScheduled = false
        guard window != nil || superview != nil else { return }
        if measurer.measurePending(budget: 0.008) { invalidateCanvasLayout() }
        if measurer.hasPending { scheduleIdleMeasurement() }
    }

    private func settleAnimations() {
        for view in views.values { NoteCanvasMotion.settleAll(view) }
        for view in decorationViews.values { NoteAnimation.settle(view) }
        for view in washViews.values { NoteAnimation.settle(view) }
        for view in transientView.subviews { view.removeFromSuperview() }
    }

    private func isBelowContent(_ point: NSPoint) -> Bool {
        updateLayoutIfNeeded()
        let column = contentRect
        return point.y > canvasLayout.contentBottom + canvasLayout.metrics.slotGap
            && point.x >= column.minX - canvasLayout.metrics.gutterWidth
            && point.x <= column.maxX + canvasLayout.metrics.gutterWidth
    }
}
