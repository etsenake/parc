import AppKit
import Combine
import ParcCore
import ParcKit
import ParcNotes

@MainActor
final class EaselFindController: NoteFindBarController {
    private struct Highlight {
        var rects: [NSRect]
        var object: NSRect?
        var oval = false
        var radius: CGFloat = 10
        var isCurrent: Bool
        var bounds: NSRect
    }

    unowned let editor: EaselEditorViewController
    private(set) var state = EaselFindSession()
    private(set) var isReplacing = false
    private var notice: String?
    private var bar: NoteFindBar?
    private var panel: NoteFloatingPanel?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private weak var returnResponder: NSResponder?
    private var refreshScheduled = false
    private var highlights: [Highlight] = []
    private var paintedZoom: CGFloat = 1
    private var zoomDependent = false
    private var layouts: [UUID: (item: EaselItem, layout: EaselTextLayout.Layout)] = [:]
    private let viewport = EaselViewportMover()

    init(editor: EaselEditorViewController) {
        self.editor = editor
    }

    var query: String { state.query }
    var options: NoteFindOptions { state.options }
    var matches: [EaselFindMatch] { state.matches }
    var currentMatch: EaselFindMatch? { state.currentMatch }
    var isVisible: Bool { panel?.isPresented == true }
    var hasMatches: Bool { !state.matches.isEmpty }
    var canReplace: Bool { !editor.session.isClosed && !editor.session.isDeleted }
    var canReplaceCurrent: Bool { canReplace && state.replaceability(in: editor.session.document) == .replaceable }

    var countLabel: String {
        if let notice, !state.query.isEmpty { return notice }
        return state.countLabel(replacing: isReplacing, in: editor.session.document)
    }

    private var canvas: EaselCanvasView { editor.canvas }

    func show(replacing: Bool = false) {
        guard !editor.session.isClosed, let window = editor.view.window else { return }
        if !isVisible {
            returnResponder = window.firstResponder
            if let textView = returnResponder as? NSTextView, textView.isFieldEditor { returnResponder = nil }
        }
        let bar = self.bar ?? makeBar()
        if !isVisible { isReplacing = false }
        if replacing && canReplace { isReplacing = true }
        if !canReplace { isReplacing = false }
        bar.setReplacing(isReplacing, animated: isVisible)
        bar.setReplaceEnabled(canReplace)
        let panel = self.panel ?? makePanel(bar)
        if !isVisible {
            observe()
            panel.present(in: editor.view, anchor: anchorRect(for: panel), edge: .below, animated: true)
            recompute(keeping: nil, reveal: true)
        } else {
            refreshViews()
            panel.contentSizeDidChange(animated: true)
            panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false)
        }
        let target = replacing && isReplacing && !state.query.isEmpty ? bar.replaceField : bar.findField
        target.focus()
        target.textField.currentEditor()?.selectAll(nil)
    }

    func hide() {
        hide(restoringFocus: true)
    }

    func hide(restoringFocus: Bool) {
        guard let panel, panel.isPresented else { return }
        let match = state.currentMatch
        subscription = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        viewport.cancel()
        panel.dismiss(animated: true)
        state.clear()
        notice = nil
        repaint()
        layouts.removeAll()
        guard restoringFocus, let window = editor.view.window else { return }
        if let match, canvas.selectOnly(match.itemID) {
            window.makeFirstResponder(canvas)
        } else if let responder = returnResponder as? NSView, SavedFocus.mayReturn(to: responder, in: window) {
            window.makeFirstResponder(responder)
        } else {
            window.makeFirstResponder(canvas)
        }
    }

    func findNext() { step(1) }

    func findPrevious() { step(-1) }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (key, flags) {
        case ("f", [.command]): show(replacing: false); return true
        case ("f", [.command, .option]): show(replacing: true); return true
        case ("g", [.command]) where isVisible: findNext(); return true
        case ("g", [.command, .shift]) where isVisible: findPrevious(); return true
        default: return false
        }
    }

    func setQuery(_ text: String) {
        guard text != state.query else { return }
        state.query = text
        recompute(keeping: nil, reveal: true)
    }

    func setMatchCase(_ value: Bool) {
        guard value != state.options.matchCase else { return }
        state.options.matchCase = value
        recompute(keeping: state.currentMatch, reveal: true)
    }

    func toggleReplacing() {
        guard canReplace || isReplacing else { return }
        isReplacing.toggle()
        bar?.setReplacing(isReplacing, animated: true)
        refreshViews()
        panel?.contentSizeDidChange(animated: true)
        if let panel { panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false) }
        (isReplacing ? bar?.replaceField : bar?.findField)?.focus()
    }

    func replaceCurrent() {
        guard canReplace, canvas.finishEditingForTransfer() else { NSSound.beep(); return }
        notice = nil
        switch state.replaceCurrent(with: bar?.replaceField.text ?? "", in: editor.session.document) {
        case .replaced(let outcome, let next):
            if !outcome.touched.isEmpty, !commit("Replace", outcome) { NSSound.beep(); return }
            state.refresh(in: editor.session.document, keeping: next)
            revealCurrent()
            refreshViews()
        case .moved, .skipped:
            revealCurrent()
            refreshViews()
        case .refused:
            NSSound.beep()
            refreshViews()
        }
    }

    func replaceAll() {
        guard canReplace, canvas.finishEditingForTransfer(), hasMatches else { NSSound.beep(); return }
        let outcome = state.replaceAll(with: bar?.replaceField.text ?? "", in: editor.session.document)
        let count = !outcome.touched.isEmpty && commit("Replace All", outcome) ? outcome.count : 0
        state.refresh(in: editor.session.document, keeping: state.currentMatch)
        let summary = EaselFindSession.summary(outcome)
        notice = summary.isEmpty ? nil : summary
        refreshViews()
        bar?.flash(count == 1 ? "Replaced 1" : "Replaced \(count)")
        if let bar, !summary.isEmpty {
            NSAccessibility.post(element: bar, notification: .announcementRequested,
                                 userInfo: [.announcement: summary, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private func commit(_ name: String, _ outcome: EaselFindReplacement) -> Bool {
        var replaced: [UUID: EaselItem] = [:]
        var resized = Set<UUID>()
        for item in outcome.document.items where outcome.touched.contains(item.id) {
            var next = item
            if next.kind == .table, let table = next.table,
               let original = editor.session.document.items.first(where: { $0.id == item.id }), let before = original.table {
                let rows = Set(Self.changedRows(before, table))
                next = canvas.normalizedTable(next, table, hugging: rows, previous: before)
                if next.frame != original.frame { resized.insert(item.id) }
            }
            if next.kind == .text {
                let height = EaselTextLayout.Layout(EaselRichTextCodec.attributed(next), width: next.frame.width).height
                next.frame.height = max(next.frame.height, Double(height))
            } else if next.kind == .sticky {
                next = EaselBoardObjects.fitted(next) { EaselStickyText.height($0) }
            } else if next.kind == .code {
                next.frame.height = EaselCodeLayoutCache.height(for: next)
            }
            replaced[item.id] = next
        }
        do {
            try editor.session.perform(name) { document in
                let previous = document
                for index in document.items.indices {
                    if let next = replaced[document.items[index].id] { document.items[index] = next }
                }
                if !resized.isEmpty { document = EaselDependents.settle(document, previous: previous, moved: resized) }
            }
            return true
        } catch {
            canvas.onError?(error)
            return false
        }
    }

    private static func changedRows(_ before: EaselTable, _ after: EaselTable) -> [Int] {
        after.cells.indices.filter { row in
            !before.cells.indices.contains(row) || before.cells[row].map(\.text) != after.cells[row].map(\.text)
        }
    }

    private func step(_ delta: Int) {
        guard hasMatches else {
            if !state.query.isEmpty { NSSound.beep() }
            return
        }
        notice = nil
        state.step(delta)
        revealCurrent()
        refreshViews()
        if let match = state.currentMatch { canvas.pulseObjects([match.itemID]) }
    }

    private func recompute(keeping match: EaselFindMatch?, reveal shouldReveal: Bool) {
        notice = nil
        let visible = canvas.visibleRect
        let frames = Dictionary(canvas.session.document.items.map { ($0.id, Self.frame($0)) }, uniquingKeysWith: { first, _ in first })
        state.refresh(in: editor.session.document, keeping: match) { matches in
            matches.firstIndex { frames[$0.itemID]?.intersects(visible) == true }
        }
        if shouldReveal { revealCurrent() }
        refreshViews()
    }

    private func refreshViews() {
        bar?.refresh()
        repaint()
        if let bar {
            NSAccessibility.post(element: bar, notification: .announcementRequested,
                                 userInfo: [.announcement: countLabel, .priority: NSAccessibilityPriorityLevel.low.rawValue])
        }
    }

    func pageChanged() {
        guard isVisible else { return }
        repaint()
    }

    private func revealCurrent() {
        if let match = state.currentMatch { canvas.showPage(containing: match.itemID) }
        guard let match = state.currentMatch,
              let item = editor.session.document.items.first(where: { $0.id == match.itemID }),
              let scroll = canvas.enclosingScrollView else { return }
        let target = highlightGeometry(for: match, in: item).rects.reduce(NSRect.null) { $0.union($1) }
        let inset = (panel?.frame.height ?? 0) + 16
        guard let plan = EaselViewportMover.plan(for: target.isNull ? Self.frame(item) : target, in: scroll, mode: .reveal, topInset: inset) else { return }
        viewport.move(scroll, to: plan)
    }

    private static func frame(_ item: EaselItem) -> NSRect {
        NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
    }

    private func highlightGeometry(for match: EaselFindMatch, in item: EaselItem) -> (rects: [NSRect], exact: Bool) {
        switch item.kind {
        case .text:
            if let rects = textRects(match.range, in: item, text: EaselRichTextCodec.attributed(item),
                                     origin: NSPoint(x: item.frame.x, y: item.frame.y), width: item.frame.width, height: item.frame.height) {
                return (rects, true)
            }
        case .sticky:
            let box = EaselBoardObjects.stickyTextBox(item)
            if let rects = textRects(match.range, in: item, text: EaselStickyText.presented(item, adaptive: false),
                                     origin: NSPoint(x: box.x, y: box.y), width: box.width, height: 1_000_000) {
                return (rects, true)
            }
        case .section:
            return ([EaselSectionArt.titleTab(item, zoom: Double(canvas.enclosingScrollView?.magnification ?? 1))], false)
        case .arrow:
            if let label = canvas.connectorLabelRect(item) { return ([label], false) }
        case .code:
            if match.part == .text, let rects = EaselCodeLayout.rects(for: match.range, in: item), !rects.isEmpty { return (rects, true) }
        case .table:
            if case .cell(let row, let column) = match.part, let table = item.table,
               let cell = EaselTableLayout(table: table, frame: item.frame).rect(of: EaselTableCoordinate(row: row, column: column), in: table) {
                return ([NSRect(x: cell.x, y: cell.y, width: cell.width, height: cell.height)], false)
            }
        default:
            break
        }
        return ([Self.frame(item)], false)
    }

    private func textRects(_ range: Range<Int>, in item: EaselItem, text: @autoclosure () -> NSAttributedString,
                           origin: NSPoint, width: Double, height: Double) -> [NSRect]? {
        let layout: EaselTextLayout.Layout
        if let cached = layouts[item.id], cached.item == item {
            layout = cached.layout
        } else {
            layout = EaselTextLayout.Layout(text(), width: width, height: height, scale: EaselTextLayout.scale(for: item))
            layouts[item.id] = (item, layout)
        }
        guard range.upperBound <= layout.storage.length else { return nil }
        let glyphs = layout.manager.glyphRange(forCharacterRange: NSRange(location: range.lowerBound, length: range.count), actualCharacterRange: nil)
        var rects: [NSRect] = []
        let inset = layout.inset
        layout.manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                               in: layout.container) { rect, _ in
            guard rect.width.isFinite, rect.height.isFinite, !rect.isEmpty else { return }
            rects.append(rect.offsetBy(dx: origin.x + inset.width, dy: origin.y + inset.height).insetBy(dx: -2, dy: -1))
        }
        return rects.isEmpty ? nil : rects
    }

    private func repaint() {
        let previous = highlights
        paintedZoom = canvas.enclosingScrollView?.magnification ?? 1
        highlights = makeHighlights()
        for highlight in previous + highlights { canvas.setOverlayNeedsDisplay(highlight.bounds) }
        canvas.onDrawOverlay = highlights.isEmpty ? nil : { [weak self] dirty, scale in self?.draw(in: dirty, scale: scale) }
    }

    private func makeHighlights() -> [Highlight] {
        zoomDependent = false
        guard isVisible, hasMatches else { return [] }
        var items: [UUID: EaselItem] = [:]
        for item in canvas.session.document.items where items[item.id] == nil { items[item.id] = item }
        var result: [Highlight] = []
        var ringed = Set<EaselFindMatch>()
        for (index, match) in state.matches.enumerated() {
            guard let item = items[match.itemID] else { continue }
            let current = index == state.currentIndex
            let geometry = highlightGeometry(for: match, in: item)
            if item.kind == .section { zoomDependent = true }
            if geometry.exact {
                let bounds = geometry.rects.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -8, dy: -8)
                result.append(Highlight(rects: geometry.rects, object: nil, isCurrent: current, bounds: bounds))
            } else if let first = geometry.rects.first {
                let key = EaselFindMatch(itemID: item.id, part: match.part, range: 0..<0)
                guard current || !ringed.contains(key) else { continue }
                ringed.insert(key)
                let cell = item.kind == .table
                let frame = cell ? first.insetBy(dx: 2, dy: 2) : first.insetBy(dx: -6, dy: -6)
                result.append(Highlight(rects: [], object: frame, oval: item.kind == .circle, radius: cell ? 5 : 10, isCurrent: current,
                                        bounds: frame.insetBy(dx: -24, dy: -24)))
            }
        }
        return result.sorted { !$0.isCurrent && $1.isCurrent }
    }

    private func draw(in dirty: NSRect, scale: CGFloat) {
        if zoomDependent, abs(scale - paintedZoom) > 0.001 {
            paintedZoom = scale
            DispatchQueue.main.async { [weak self] in self?.repaint() }
        }
        let scale = max(scale, 0.1)
        for highlight in highlights where highlight.bounds.intersects(dirty) {
            if let frame = highlight.object {
                let outline = highlight.oval ? NSBezierPath(ovalIn: frame)
                    : NSBezierPath(roundedRect: frame, xRadius: highlight.radius, yRadius: highlight.radius)
                if highlight.isCurrent {
                    NoteTheme.findMatch.setFill()
                    outline.fill()
                    NoteTheme.findCurrentMatch.setStroke()
                    outline.lineWidth = 3 / scale
                } else {
                    NoteTheme.findCurrentMatch.withAlphaComponent(0.45).setStroke()
                    outline.lineWidth = 2 / scale
                }
                outline.stroke()
            } else {
                for rect in highlight.rects {
                    let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
                    NoteTheme.findMatch.setFill()
                    path.fill()
                    if highlight.isCurrent {
                        NoteTheme.findCurrentMatch.setStroke()
                        path.lineWidth = 2 / scale
                        path.stroke()
                    }
                }
            }
        }
    }

    private func makeBar() -> NoteFindBar {
        let bar = NoteFindBar(controller: self, placeholder: "Find in Easel", label: "Find in Easel")
        self.bar = bar
        return bar
    }

    private func makePanel(_ bar: NoteFindBar) -> NoteFloatingPanel {
        let panel = NoteFloatingPanel(content: bar)
        panel.setAccessibilityElement(false)
        self.panel = panel
        return panel
    }

    private func anchorRect(for panel: NoteFloatingPanel) -> NSRect {
        let host = editor.view
        let area = canvas.enclosingScrollView.map { host.convert($0.bounds, from: $0) } ?? host.bounds
        let width = panel.preferredSize.width
        return NSRect(x: max(area.minX + 12, area.maxX - width - 16), y: area.minY + 4, width: width, height: 0)
    }

    private func observe() {
        subscription = editor.session.$document.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }
        guard let scroll = canvas.enclosingScrollView else { return }
        scroll.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, let panel = self.panel else { return }
                panel.reposition(anchor: self.anchorRect(for: panel), edge: .below, animated: false)
            }
        })
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            guard self.isVisible else { return }
            self.state.refresh(in: self.editor.session.document, keeping: self.state.currentMatch)
            self.bar?.setReplaceEnabled(self.canReplace)
            self.refreshViews()
        }
    }
}
