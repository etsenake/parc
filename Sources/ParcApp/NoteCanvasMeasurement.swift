import AppKit
import QuartzCore

extension NoteCanvasMetrics {
    @MainActor
    static func make(for settings: NotePageSettings) -> NoteCanvasMetrics {
        var metrics = NoteCanvasMetrics()
        metrics.columnWidth = NoteTheme.pageColumnWidth
        metrics.pageSideMargin = NoteTheme.pageSideMargin
        metrics.minimumSideMargin = NoteTheme.minimumSideMargin
        metrics.fullWidth = settings.fullWidth
        metrics.indentWidth = NoteTheme.indentWidth
        metrics.columnGap = NoteTheme.columnGap
        metrics.gutterWidth = NoteTheme.gutterWidth
        metrics.minimumColumnWidth = NoteTheme.columnMinimumWidth
        metrics.maximumColumns = NoteDragPlan.maximumColumns
        metrics.topInset = NoteTheme.pageTopMargin
        metrics.bottomInset = NoteTheme.pageBottomMargin
        metrics.blockSpacing = NoteTheme.blockSpacing
        let padding = NoteTheme.calloutPadding
        metrics.calloutInsets = NoteCanvasInsets(top: padding.top, left: padding.left, bottom: padding.bottom, right: padding.right)
        metrics.quoteChildIndent = NoteTheme.quoteBarWidth + NoteTheme.quoteInset
        metrics.quoteBarWidth = NoteTheme.quoteBarWidth
        metrics.scale = settings.smallText ? NoteTheme.smallBodySize / NoteTheme.bodySize : 1
        metrics.bodyLineHeight = NoteTheme.textStyle(.body, font: settings.font, small: settings.smallText).lineHeight
        metrics.headingLineHeights = (1...6).map {
            NoteTheme.textStyle(.heading($0), font: settings.font, small: settings.smallText).lineHeight
        }
        metrics.codeLineHeight = NoteTheme.textStyle(.code, font: settings.font, small: settings.smallText).lineHeight
        metrics.averageCharacterWidth = NoteTheme.bodyFont(settings.font, small: settings.smallText).pointSize * 0.5
        metrics.dragLeadOffset = NoteHandleGeometry.contentGap + NoteHandleGeometry.buttonSize.width / 2
        metrics.syncedHeaderHeight = NoteTheme.syncedPadding
        metrics.syncedFooterHeight = NoteTheme.syncedPadding
        return metrics
    }
}

@MainActor
final class NoteCanvasMeasurer {
    private struct Key: Hashable {
        var content: Int
        var width: Int
        var font: NotePageFont
        var small: Bool
        var salt: Int
    }

    weak var editor: NotePageEditor?
    var metrics = NoteCanvasMetrics()
    private(set) var font: NotePageFont = .standard
    private(set) var small = false
    private var heights: [Key: CGFloat] = [:]
    private var contentHashes: [NoteBlockID: Int] = [:]
    private var lastKeys: [NoteBlockID: Key] = [:]
    private var pending: [NoteBlockID: (block: NoteBlock, width: CGFloat)] = [:]
    private var measuringViews: [NoteBlockKind: NoteBlockView] = [:]
    private var contentsSalt = 0

    var hasPending: Bool { !pending.isEmpty }

    func use(_ settings: NotePageSettings, metrics: NoteCanvasMetrics) {
        self.metrics = metrics
        guard settings.font != font || settings.smallText != small else { return }
        font = settings.font
        small = settings.smallText
        heights.removeAll()
        lastKeys.removeAll()
        pending.removeAll()
        measuringViews.removeAll()
    }

    func invalidate(_ ids: some Sequence<NoteBlockID>) {
        for id in ids { contentHashes[id] = nil }
    }

    func invalidateAll() {
        contentHashes.removeAll()
    }

    func invalidateContents() {
        contentsSalt &+= 1
    }

    func forget(_ id: NoteBlockID) {
        if let key = lastKeys.removeValue(forKey: id) { heights[key] = nil }
        contentHashes[id] = nil
    }

    func reset() {
        heights.removeAll()
        contentHashes.removeAll()
        lastKeys.removeAll()
        pending.removeAll()
        measuringViews.removeAll()
    }

    func cachedHeight(of block: NoteBlock, width: CGFloat) -> CGFloat? {
        heights[key(for: block, width: width)]
    }

    func height(of block: NoteBlock, width: CGFloat, live: NoteBlockView?) -> CGFloat {
        let key = key(for: block, width: width)
        if let live {
            let value = max(0, live.measureHeight(width: width))
            store(value, for: key, id: block.id)
            return value
        }
        if let cached = heights[key] {
            pending[block.id] = nil
            return cached
        }
        if Self.measuresOffscreen(block.kind) { pending[block.id] = (block, width) }
        return NoteCanvasEstimate.height(of: block, width: width, metrics: metrics)
    }

    func measurePending(budget: CFTimeInterval) -> Bool {
        guard !pending.isEmpty else { return false }
        let deadline = CACurrentMediaTime() + budget
        var changed = false
        for (id, item) in Array(pending) {
            if CACurrentMediaTime() > deadline { break }
            pending[id] = nil
            let key = key(for: item.block, width: item.width)
            guard heights[key] == nil, let view = measuringView(for: item.block) else { continue }
            view.update(item.block)
            store(max(0, view.measureHeight(width: item.width)), for: key, id: id)
            changed = true
        }
        return changed
    }

    @discardableResult
    func measureNow(_ block: NoteBlock, width: CGFloat) -> CGFloat? {
        let key = key(for: block, width: width)
        if let cached = heights[key] { return cached }
        guard Self.measuresOffscreen(block.kind), let view = measuringView(for: block) else { return nil }
        view.update(block)
        let value = max(0, view.measureHeight(width: width))
        store(value, for: key, id: block.id)
        return value
    }

    func childIndent(of block: NoteBlock, live: NoteBlockView?) -> CGFloat {
        switch block.kind {
        case .callout, .quote:
            let inset = live?.contentLeadingInset ?? 0
            return inset > 0 ? inset : metrics.childIndent(of: block)
        case .synced:
            return metrics.childIndent(of: block)
        default:
            return metrics.indentWidth
        }
    }

    static func measuresOffscreen(_ kind: NoteBlockKind) -> Bool {
        switch kind {
        case .image, .video, .audio, .file, .pdf, .bookmark, .embed, .columns, .column, .synced: return false
        default: return true
        }
    }

    private func store(_ value: CGFloat, for key: Key, id: NoteBlockID) {
        heights[key] = value
        lastKeys[id] = key
        pending[id] = nil
    }

    private func key(for block: NoteBlock, width: CGFloat) -> Key {
        let content: Int
        if let cached = contentHashes[block.id] {
            content = cached
        } else {
            var hasher = Hasher()
            hasher.combine(block.kind)
            hasher.combine(block.text)
            hasher.combine(block.props)
            hasher.combine(block.color)
            hasher.combine(block.children.isEmpty)
            content = hasher.finalize()
            contentHashes[block.id] = content
        }
        let salt = block.kind == .tableOfContents || block.kind == .numberedItem ? contentsSalt : 0
        return Key(content: content, width: Int((width * 2).rounded()), font: font, small: small, salt: salt)
    }

    private func measuringView(for block: NoteBlock) -> NoteBlockView? {
        if let view = measuringViews[block.kind] { return view }
        guard let editor else { return nil }
        let view = editor.makeBlockView(for: block)
        measuringViews[block.kind] = view
        return view
    }
}
