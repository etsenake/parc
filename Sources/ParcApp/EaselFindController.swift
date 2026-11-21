import AppKit
import Combine

@MainActor
final class EaselFindController: NoteFindBarController {
    private struct Highlight {
        var rects: [NSRect]
        var object: NSRect?
        var oval = false
        var isCurrent: Bool
        var bounds: NSRect
    }

    unowned let editor: EaselEditorViewController
    private(set) var query = ""
    private(set) var options = NoteFindOptions()
    private(set) var matches: [EaselFindMatch] = []
    private(set) var currentIndex: Int?
    private(set) var isReplacing = false
    private var bar: NoteFindBar?
    private var panel: NoteFloatingPanel?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private weak var returnResponder: NSResponder?
    private var refreshScheduled = false
    private var highlights: [Highlight] = []
    private var layouts: [UUID: (item: EaselItem, layout: EaselTextLayout.Layout)] = [:]
    private let viewport = EaselViewportMover()

    init(editor: EaselEditorViewController) {
        self.editor = editor
    }

    var isVisible: Bool { panel?.isPresented == true }
    var hasMatches: Bool { !matches.isEmpty }
    var canReplace: Bool { !editor.session.isClosed && !editor.session.isDeleted }

    var currentMatch: EaselFindMatch? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    var countLabel: String {
        guard !query.isEmpty else { return "" }
        guard let currentIndex, !matches.isEmpty else { return matches.isEmpty ? "No matches" : "\(matches.count) found" }
        return "\(currentIndex + 1) of \(matches.count)"
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
        bar.refresh()
        let panel = self.panel ?? makePanel(bar)
        if !isVisible {
            observe()
            panel.present(in: editor.view, anchor: anchorRect(for: panel), edge: .below, animated: true)
            recompute(keeping: nil, reveal: true)
        } else {
            panel.contentSizeDidChange(animated: true)
            panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false)
        }
        let target = replacing && isReplacing && !query.isEmpty ? bar.replaceField : bar.findField
        target.focus()
        target.textField.currentEditor()?.selectAll(nil)
    }

    func hide() {
        hide(restoringFocus: true)
    }

    func hide(restoringFocus: Bool) {
        guard let panel, panel.isPresented else { return }
        let match = currentMatch
        subscription = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        viewport.cancel()
        panel.dismiss(animated: true)
        matches = []
        currentIndex = nil
        repaint()
        layouts.removeAll()
        guard restoringFocus, let window = editor.view.window else { return }
        if let match, canvas.selectOnly(match.itemID) {
            window.makeFirstResponder(canvas)
        } else if let responder = returnResponder, (responder as? NSView)?.window === window {
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
        guard text != query else { return }
        query = text
        recompute(keeping: nil, reveal: true)
    }

    func setMatchCase(_ value: Bool) {
        guard value != options.matchCase else { return }
        options.matchCase = value
        recompute(keeping: currentMatch, reveal: true)
    }

    func toggleReplacing() {
        guard canReplace || isReplacing else { return }
        isReplacing.toggle()
        bar?.setReplacing(isReplacing, animated: true)
        panel?.contentSizeDidChange(animated: true)
        if let panel { panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false) }
        (isReplacing ? bar?.replaceField : bar?.findField)?.focus()
    }

    func replaceCurrent() {
        guard prepareToReplace(), let match = currentMatch,
              let item = editor.session.document.items.first(where: { $0.id == match.itemID }),
              EaselFinder.isReplaceable(item) else { NSSound.beep(); return }
        let replacement = bar?.replaceField.text ?? ""
        let outcome = EaselFinder.replace([match], with: replacement, in: editor.session.document)
        guard outcome.count > 0, commit("Replace", outcome) else { NSSound.beep(); return }
        let offset = match.range.lowerBound + (replacement as NSString).length
        recompute(keeping: EaselFindMatch(itemID: match.itemID, part: match.part, range: offset..<offset), reveal: true)
    }

    func replaceAll() {
        guard prepareToReplace(), !matches.isEmpty else { NSSound.beep(); return }
        let replacement = bar?.replaceField.text ?? ""
        let outcome = EaselFinder.replace(matches, with: replacement, in: editor.session.document)
        let count = outcome.count > 0 && commit("Replace All", outcome) ? outcome.count : 0
        recompute(keeping: currentMatch, reveal: false)
        bar?.flash(count == 1 ? "Replaced 1" : "Replaced \(count)")
    }

    private func prepareToReplace() -> Bool {
        guard canReplace, canvas.finishEditingForTransfer() else { return false }
        let document = editor.session.document
        let fresh = EaselFinder.matches(of: query, in: document, options: options)
        guard fresh != matches else { return true }
        let kept = currentMatch
        matches = fresh
        currentIndex = kept.map { EaselFinder.index(of: $0, in: matches, document: document) } ?? initialIndex(in: document)
        refreshViews()
        return true
    }

    private func commit(_ name: String, _ outcome: EaselFindReplacement) -> Bool {
        var replaced: [UUID: EaselItem] = [:]
        for item in outcome.document.items where outcome.touched.contains(item.id) {
            var next = item
            if next.kind == .text {
                let height = EaselTextLayout.Layout(EaselRichTextCodec.attributed(next), width: next.frame.width).height
                next.frame.height = max(next.frame.height, Double(height))
            }
            replaced[item.id] = next
        }
        do {
            try editor.session.perform(name) { document in
                for index in document.items.indices {
                    if let next = replaced[document.items[index].id] { document.items[index] = next }
                }
            }
            return true
        } catch {
            canvas.onError?(error)
            return false
        }
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else {
            if !query.isEmpty { NSSound.beep() }
            return
        }
        let count = matches.count
        let index = currentIndex.map { ($0 + delta + count) % count } ?? (delta > 0 ? 0 : count - 1)
        currentIndex = index
        reveal(matches[index])
        refreshViews()
    }

    private func recompute(keeping match: EaselFindMatch?, reveal shouldReveal: Bool) {
        let document = editor.session.document
        matches = EaselFinder.matches(of: query, in: document, options: options)
        currentIndex = match.map { EaselFinder.index(of: $0, in: matches, document: document) } ?? initialIndex(in: document)
        if shouldReveal, let current = currentMatch { reveal(current) }
        refreshViews()
    }

    private func initialIndex(in document: EaselDocument) -> Int? {
        guard !matches.isEmpty else { return nil }
        let visible = canvas.visibleRect
        let frames = Dictionary(document.items.map { ($0.id, Self.frame($0)) }, uniquingKeysWith: { first, _ in first })
        return matches.firstIndex { frames[$0.itemID]?.intersects(visible) == true } ?? 0
    }

    private func refreshViews() {
        bar?.refresh()
        repaint()
        if let bar {
            NSAccessibility.post(element: bar, notification: .announcementRequested,
                                 userInfo: [.announcement: countLabel, .priority: NSAccessibilityPriorityLevel.low.rawValue])
        }
    }

    private func reveal(_ match: EaselFindMatch) {
        guard let item = editor.session.document.items.first(where: { $0.id == match.itemID }),
              let scroll = canvas.enclosingScrollView else { return }
        let target = textRects(for: match, in: item)?.reduce(NSRect.null) { $0.union($1) } ?? Self.frame(item)
        let inset = (panel?.frame.height ?? 0) + 16
        guard let plan = EaselViewportMover.plan(for: target.isNull ? Self.frame(item) : target, in: scroll, mode: .reveal, topInset: inset) else { return }
        viewport.move(scroll, to: plan)
    }

    private static func frame(_ item: EaselItem) -> NSRect {
        NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
    }

    private func textRects(for match: EaselFindMatch, in item: EaselItem) -> [NSRect]? {
        guard item.kind == .text, match.part == .text else { return nil }
        let layout: EaselTextLayout.Layout
        if let cached = layouts[item.id], cached.item == item {
            layout = cached.layout
        } else {
            layout = EaselTextLayout.Layout(EaselRichTextCodec.attributed(item), width: item.frame.width, height: item.frame.height)
            layouts[item.id] = (item, layout)
        }
        guard match.range.upperBound <= layout.storage.length else { return nil }
        let glyphs = layout.manager.glyphRange(forCharacterRange: NSRange(location: match.range.lowerBound, length: match.range.count),
                                               actualCharacterRange: nil)
        var rects: [NSRect] = []
        let inset = EaselTextLayout.inset
        layout.manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                               in: layout.container) { rect, _ in
            guard rect.width.isFinite, rect.height.isFinite, !rect.isEmpty else { return }
            rects.append(rect.offsetBy(dx: item.frame.x + inset.width, dy: item.frame.y + inset.height).insetBy(dx: -2, dy: -1))
        }
        return rects.isEmpty ? nil : rects
    }

    private func repaint() {
        let previous = highlights
        highlights = makeHighlights()
        for highlight in previous + highlights { canvas.setOverlayNeedsDisplay(highlight.bounds) }
        canvas.onDrawOverlay = highlights.isEmpty ? nil : { [weak self] dirty, scale in self?.draw(in: dirty, scale: scale) }
    }

    private func makeHighlights() -> [Highlight] {
        guard isVisible, !matches.isEmpty else { return [] }
        let items = Dictionary(editor.session.document.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Highlight] = []
        var ringed = Set<UUID>()
        for (index, match) in matches.enumerated() {
            guard let item = items[match.itemID] else { continue }
            let current = index == currentIndex
            if let rects = textRects(for: match, in: item) {
                let bounds = rects.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -8, dy: -8)
                result.append(Highlight(rects: rects, object: nil, isCurrent: current, bounds: bounds))
            } else if current || !ringed.contains(item.id) {
                ringed.insert(item.id)
                let frame = Self.frame(item).insetBy(dx: -6, dy: -6)
                result.append(Highlight(rects: [], object: frame, oval: item.kind == .circle, isCurrent: current,
                                        bounds: frame.insetBy(dx: -24, dy: -24)))
            }
        }
        return result.sorted { !$0.isCurrent && $1.isCurrent }
    }

    private func draw(in dirty: NSRect, scale: CGFloat) {
        let scale = max(scale, 0.1)
        for highlight in highlights where highlight.bounds.intersects(dirty) {
            if let frame = highlight.object {
                let outline = highlight.oval ? NSBezierPath(ovalIn: frame) : NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
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
        let bar = NoteFindBar(controller: self, placeholder: "Find on this Easel", label: "Find on Easel")
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
        let center = NotificationCenter.default
        guard let scroll = canvas.enclosingScrollView else { return }
        scroll.postsFrameChangedNotifications = true
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: scroll, queue: .main) { [weak self] _ in
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
            self.recompute(keeping: self.currentMatch, reveal: false)
            self.bar?.setReplaceEnabled(self.canReplace)
        }
    }
}

@MainActor
extension EaselEditorViewController {
    func performBoardKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isViewLoaded, let window = view.window, window.isKeyWindow,
              !view.isHiddenOrHasHiddenAncestor, window.attachedSheet == nil, ownsBoardKeyFocus(in: window),
              (window.firstResponder as? NSTextInputClient)?.hasMarkedText() != true else { return false }
        return find.handleKeyEquivalent(event)
    }

    private func ownsBoardKeyFocus(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder as? NSView else { return false }
        if responder === canvas || responder.superview === canvas { return true }
        return responder.isDescendant(of: view) && !responder.isDescendant(of: canvas)
    }
}
