import AppKit
import ParcCore

@MainActor
final class NoteSelectionController {
    static let didChangeNotification = Notification.Name("NoteSelectionControllerDidChange")

    unowned let editor: NotePageEditor
    let layout: NoteSelectionCanvasLayout
    private(set) var isApplying = false
    private(set) var isTracking = false
    var goal = NoteGoalColumn()
    var blockRange: NoteBlockRange?
    var transitBlock: NoteBlockID?
    var trackingEvent: NSEvent?
    var trackingUpdate: ((NSPoint) -> Void)?
    var trackingNavigator: NoteSelectionNavigator?
    private var highlighted: [NoteBlockID: (field: NoteTextField, range: Range<Int>)] = [:]
    private var looks: Set<NoteBlockID> = []
    private var transientWash: Set<NoteBlockID> = []
    private var displayed: NotePageSelection = .none
    private var announced: [NoteBlockID] = []
    private(set) lazy var responder = NoteSelectionResponder(controller: self)

    init(editor: NotePageEditor) {
        self.editor = editor
        layout = NoteSelectionCanvasLayout(editor: editor)
    }

    var session: NotePageSession { editor.session }
    var canvas: NotePageCanvasView { editor.canvas }

    func navigator() -> NoteSelectionNavigator {
        if let trackingNavigator { return trackingNavigator }
        layout.invalidate()
        return NoteSelectionNavigator(items: layout.items)
    }

    func apply(_ selection: NotePageSelection) {
        guard !isApplying, !isTracking else { return }
        isApplying = true
        defer { isApplying = false }
        render(selection, takeFocus: focusIsInPage, reveal: true)
    }

    func focusSelection() {
        guard !isTracking else { return }
        isApplying = true
        defer { isApplying = false }
        render(session.selection, takeFocus: true, reveal: true)
    }

    func select(_ selection: NotePageSelection, reveal: Bool = true) {
        isApplying = true
        render(selection, takeFocus: true, reveal: reveal)
        isApplying = false
        session.setSelection(selection, origin: responder)
    }

    func blockViewDidAppear(_ view: NoteBlockView) {
        if let entry = highlighted[view.blockID], let text = view.textHost(for: entry.field)?.textView {
            collapseNativeSelection(text)
            text.crossBlockHighlight = entry.range
        }
        if looks.contains(view.blockID), !view.isBlockSelected { view.setBlockSelected(true, animated: false) }
    }

    func sessionSelection(for host: NoteTextHost) -> NotePageSelection {
        let range = host.textView.selectedOffsets
        if case .text(let anchor, let head) = session.selection,
           anchor.block == host.blockID, head.block == host.blockID, anchor.field == host.field, head.field == host.field,
           min(anchor.offset, head.offset) == range.lowerBound, max(anchor.offset, head.offset) == range.upperBound {
            return .text(anchor: anchor, head: head)
        }
        return .text(anchor: NotePosition(host.blockID, range.lowerBound, field: host.field),
                     head: NotePosition(host.blockID, range.upperBound, field: host.field))
    }

    func currentSelection() -> NotePageSelection {
        if let view = canvas.window?.firstResponder as? NoteTextView, view.editor === editor, let host = view.host {
            return sessionSelection(for: host)
        }
        return session.selection
    }

    var selectionBounds: NSRect? {
        switch isTracking ? displayed : session.selection {
        case .none, .cells:
            return nil
        case .text(let anchor, let head) where anchor.block == head.block && anchor.field == head.field:
            let range = min(anchor.offset, head.offset)..<max(anchor.offset, head.offset)
            return union(layout.selectionRects(for: head, range: range))
        case .text(let anchor, let head):
            let marks = navigator().marks(from: anchor, to: head) { [layout] in layout.length(of: NotePosition($0, 0)) }
            var rects: [NSRect] = []
            for (id, mark) in marks {
                if let entry = mark.highlight {
                    rects += layout.selectionRects(for: NotePosition(id, 0, field: entry.field), range: entry.range)
                } else if let frame = canvas.frame(of: id) {
                    rects.append(frame)
                }
            }
            return union(rects)
        case .blocks(let ids):
            return union(navigator().expanded(ids).compactMap { canvas.frame(of: $0) })
        }
    }

    private func union(_ rects: [NSRect]) -> NSRect? {
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    func beginTracking() {
        isTracking = true
        trackingNavigator = nil
        trackingNavigator = navigator()
        editor.formatBar.selectionDidChange()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: editor)
    }

    func endTracking(with selection: NotePageSelection) {
        isTracking = false
        trackingNavigator = nil
        trackingEvent = nil
        trackingUpdate = nil
        select(selection, reveal: false)
        editor.formatBar.selectionDidChange()
    }

    func preview(_ selection: NotePageSelection) {
        isApplying = true
        focusResponder()
        clearPreviousNativeRange(replacedBy: .none)
        switch selection {
        case .text(let anchor, let head):
            let marks = navigator().marks(from: anchor, to: head) { [layout] in layout.length(of: NotePosition($0, 0)) }
            decorate(marks, selected: [])
        case .blocks(let ids):
            setHighlights([:])
            setLooks(Set(navigator().expanded(ids)), wash: Set(ids))
        case .none, .cells:
            setHighlights([:])
            setLooks([])
        }
        displayed = selection
        isApplying = false
        session.setSelection(selection, origin: responder)
        positionResponder(for: selection)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: editor)
    }

    private var focusIsInPage: Bool {
        guard let window = canvas.window else { return false }
        guard let first = window.firstResponder, first !== window else { return true }
        if first === responder || first === canvas { return true }
        if let text = first as? NoteTextView { return text.editor === editor || text.window == nil }
        if let view = first as? NSView { return view.window == nil }
        return false
    }

    private func render(_ selection: NotePageSelection, takeFocus: Bool, reveal: Bool) {
        let changed = selection != displayed
        switch selection {
        case .text(let anchor, let head) where anchor.block == head.block && anchor.field == head.field:
            setHighlights([:])
            setLooks([])
            renderSingle(anchor: anchor, head: head, takeFocus: takeFocus, reveal: reveal && changed)
        case .text(let anchor, let head):
            if takeFocus { focusResponder() }
            let marks = navigator().marks(from: anchor, to: head) { [layout] in layout.length(of: NotePosition($0, 0)) }
            decorate(marks, selected: [])
            if reveal && changed { self.reveal(head) }
        case .blocks(let ids):
            if takeFocus { focusResponder() }
            setHighlights([:])
            let nav = navigator()
            setLooks(Set(nav.expanded(ids)))
            let valid = blockRange.map { Set(nav.blocks(from: $0.anchor, to: $0.head)) == Set(ids) } ?? false
            if !valid, let first = ids.first { blockRange = NoteBlockRange(anchor: first, head: ids.last ?? first) }
            if reveal && changed, let head = blockRange?.head { revealBlock(head) }
            announce(ids)
        case .none, .cells:
            setHighlights([:])
            setLooks([])
        }
        if changed { clearPreviousNativeRange(replacedBy: selection) }
        if selection.selectedBlocks == nil { announced = [] }
        if let transitBlock, selection.selectedBlocks != [transitBlock] { self.transitBlock = nil }
        displayed = selection
        positionResponder(for: selection)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: editor)
    }

    private func renderSingle(anchor: NotePosition, head: NotePosition, takeFocus: Bool, reveal: Bool) {
        guard let host = layout.host(for: head, materialize: takeFocus) else { return }
        let view = host.textView
        guard !view.hasMarkedText(), let window = view.window else { return }
        let length = (view.string as NSString).length
        let lower = min(max(0, min(anchor.offset, head.offset)), length)
        let upper = min(max(lower, max(anchor.offset, head.offset)), length)
        let focused = window.firstResponder === view
        if focused && view.selectedOffsets == lower..<upper { return }
        guard takeFocus else { return }
        if !focused { window.makeFirstResponder(view) }
        let upstream = lower == upper && layout.upstream == head
        view.setSelectedRange(NSRange(location: lower, length: upper - lower), affinity: upstream ? .upstream : .downstream, stillSelecting: false)
        if reveal { self.reveal(head) }
    }

    private func decorate(_ marks: [NoteBlockID: NoteSelectionMark], selected: Set<NoteBlockID>) {
        var ranges: [NoteBlockID: (field: NoteTextField, range: Range<Int>)] = [:]
        var wash = selected
        for (id, mark) in marks {
            if let entry = mark.highlight { ranges[id] = entry } else { wash.insert(id) }
        }
        setHighlights(ranges)
        setLooks(wash, wash: wash)
    }

    private func setHighlights(_ next: [NoteBlockID: (field: NoteTextField, range: Range<Int>)]) {
        for (id, entry) in highlighted where next[id]?.field != entry.field {
            layout.textView(for: NotePosition(id, 0, field: entry.field))?.crossBlockHighlight = nil
        }
        for (id, entry) in next {
            guard let view = layout.textView(for: NotePosition(id, 0, field: entry.field)) else { continue }
            collapseNativeSelection(view)
            view.crossBlockHighlight = entry.range
        }
        highlighted = next
    }

    private func clearPreviousNativeRange(replacedBy next: NotePageSelection) {
        guard case .text(let anchor, let head) = displayed, anchor != head,
              anchor.block == head.block, anchor.field == head.field else { return }
        if case .text(let start, let end) = next,
           start.block == anchor.block, end.block == anchor.block,
           start.field == anchor.field, end.field == anchor.field { return }
        if let previous = layout.textView(for: anchor) { collapseNativeSelection(previous) }
    }

    private func collapseNativeSelection(_ view: NoteTextView) {
        guard view.window?.firstResponder !== view, !view.hasMarkedText() else { return }
        let range = view.selectedRange()
        if range.length > 0 { view.setSelectedRange(NSRange(location: range.location, length: 0)) }
    }

    private func setLooks(_ next: Set<NoteBlockID>, wash: Set<NoteBlockID> = []) {
        let animated = !isTracking
        for id in looks.subtracting(next) {
            if let view = canvas.existingBlockView(for: id), view.isBlockSelected { view.setBlockSelected(false, animated: animated) }
        }
        for id in next {
            if let view = canvas.existingBlockView(for: id), !view.isBlockSelected { view.setBlockSelected(true, animated: animated) }
        }
        looks = next
        if wash != transientWash {
            transientWash = wash
            canvas.setSelectionWash(wash)
        }
    }

    func focusResponder() {
        if responder.superview !== canvas { canvas.addSubview(responder) }
        guard let window = canvas.window, window.firstResponder !== responder else { return }
        window.makeFirstResponder(responder)
    }

    private func positionResponder(for selection: NotePageSelection) {
        guard responder.superview === canvas else { return }
        var rect: NSRect?
        switch selection {
        case .text(_, let head): rect = layout.caretRect(at: head)
        case .blocks(let ids): rect = (blockRange?.head ?? ids.last).flatMap { canvas.frame(of: $0) }
        case .none, .cells: rect = nil
        }
        guard let rect else { return }
        responder.frame = NSRect(x: rect.minX, y: rect.minY, width: max(1, rect.width), height: max(1, rect.height))
    }

    func reveal(_ head: NotePosition) {
        guard let rect = layout.caretRect(at: head) ?? canvas.frame(of: head.block) else {
            canvas.scrollBlockToVisible(head.block)
            return
        }
        canvas.scrollToVisible(rect.insetBy(dx: -2, dy: -32))
    }

    func revealBlock(_ id: NoteBlockID) {
        guard let frame = canvas.frame(of: id) else { return }
        canvas.scrollToVisible(frame.insetBy(dx: 0, dy: -24))
    }

    private func announce(_ ids: [NoteBlockID]) {
        guard ids != announced else { return }
        announced = ids
        let text = NoteSelectionAnnouncement.blocks(ids.count)
        responder.setAccessibilityValue(text)
        NSAccessibility.post(element: responder, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

extension NotePageSelection {
    var selectedBlocks: [NoteBlockID]? {
        if case .blocks(let ids) = self { return ids }
        return nil
    }

    var isCrossBlock: Bool {
        if case .text(let anchor, let head) = self { return anchor.block != head.block || anchor.field != head.field }
        return false
    }
}
