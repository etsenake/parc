import AppKit
import Combine

@MainActor
final class NoteFindController {
    unowned let editor: NotePageEditor
    private(set) var query = ""
    private(set) var options = NoteFindOptions()
    private(set) var matches: [NoteFindMatch] = []
    private(set) var currentIndex: Int?
    private(set) var isReplacing = false
    private var bar: NoteFindBar?
    private var panel: NoteFloatingPanel?
    private let highlights = NoteFindHighlightView()
    private var origin: NotePosition?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private weak var returnResponder: NSResponder?
    private var refreshScheduled = false

    init(editor: NotePageEditor) {
        self.editor = editor
        highlights.controller = self
    }

    var isVisible: Bool { panel?.isPresented == true }

    var currentMatch: NoteFindMatch? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    var countLabel: String {
        guard !query.isEmpty else { return "" }
        guard let currentIndex, !matches.isEmpty else { return matches.isEmpty ? "No matches" : "\(matches.count) found" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    var canReplace: Bool { !editor.isReadOnly }

    func show(replacing: Bool = false) {
        let canvas = editor.canvas!
        let window = canvas.window
        if !isVisible {
            returnResponder = window?.firstResponder
            if let textView = returnResponder as? NSTextView, textView.isFieldEditor { returnResponder = nil }
            origin = Self.head(of: editor.session.selection)
        }
        let seeded = selectedSingleLineText()
        let bar = self.bar ?? makeBar()
        if !isVisible { isReplacing = false }
        if replacing && canReplace { isReplacing = true }
        if !canReplace { isReplacing = false }
        bar.setReplacing(isReplacing, animated: isVisible)
        if let seeded, !seeded.isEmpty, !isVisible || replacing {
            bar.findField.field.stringValue = seeded
            query = seeded
        }
        bar.refresh()
        let panel = self.panel ?? makePanel(bar)
        if !isVisible {
            attachHighlights()
            observe()
            panel.present(in: canvas.overlayView, anchor: anchorRect(for: panel), edge: .below, animated: true)
            recompute(keepingPosition: origin, reveal: true)
        } else {
            panel.contentSizeDidChange(animated: true)
            panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false)
        }
        let target = replacing && isReplacing && !query.isEmpty ? bar.replaceField.field : bar.findField.field
        window?.makeFirstResponder(target)
        target.currentEditor()?.selectAll(nil)
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
        panel.dismiss(animated: true)
        highlights.removeFromSuperview()
        matches = []
        currentIndex = nil
        guard restoringFocus else { return }
        if let match, editor.canvas.textHost(for: match.position) != nil {
            editor.focus(match.position)
            if let host = editor.canvas.textHost(for: match.position) {
                host.textView.selectedOffsets = match.range
                editor.textSelectionDidChange(in: host)
            }
        } else if let responder = returnResponder, let window = editor.canvas.window {
            window.makeFirstResponder(responder)
        }
    }

    func findNext() { step(1) }

    func findPrevious() { step(-1) }

    func useSelectionForFind() {
        guard let text = selectedSingleLineText(), !text.isEmpty else { NSSound.beep(); return }
        if isVisible {
            bar?.findField.field.stringValue = text
            setQuery(text)
        } else {
            show()
            bar?.findField.field.stringValue = text
            setQuery(text)
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (key, flags) {
        case ("f", [.command]): show(replacing: false); return true
        case ("f", [.command, .option]): show(replacing: true); return true
        case ("g", [.command]):
            if isVisible { findNext() } else if !query.isEmpty { show(); findNext() } else { show() }
            return true
        case ("g", [.command, .shift]):
            if isVisible { findPrevious() } else if !query.isEmpty { show(); findPrevious() } else { show() }
            return true
        case ("e", [.command]): useSelectionForFind(); return true
        default: break
        }
        if isVisible, event.keyCode == 53, flags.isEmpty, event.window?.firstResponder === bar?.findField.field.currentEditor() {
            hide()
            return true
        }
        return false
    }

    func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        recompute(keepingPosition: origin, reveal: true)
    }

    func setMatchCase(_ value: Bool) {
        guard value != options.matchCase else { return }
        options.matchCase = value
        recompute(keepingPosition: currentMatch?.position ?? origin, reveal: true)
    }

    func toggleReplacing() {
        guard canReplace || isReplacing else { return }
        isReplacing.toggle()
        bar?.setReplacing(isReplacing, animated: true)
        panel?.contentSizeDidChange(animated: true)
        if let panel { panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false) }
        editor.canvas.window?.makeFirstResponder(isReplacing ? bar?.replaceField.field : bar?.findField.field)
    }

    func replaceCurrent() {
        guard canReplace, let match = currentMatch else { NSSound.beep(); return }
        let replacement = bar?.replaceField.field.stringValue ?? ""
        let after = NotePageFinder.positionAfterReplacing(match, with: replacement)
        editor.session.edit("Replace", kind: .text, affected: [match.block]) { page in
            NotePageFinder.replace([match], with: replacement, in: &page)
        }
        origin = after
        recompute(keepingPosition: after, reveal: true)
    }

    func replaceAll() {
        guard canReplace, !matches.isEmpty else { NSSound.beep(); return }
        let replacement = bar?.replaceField.field.stringValue ?? ""
        let targets = matches
        let blocks = Set(targets.map(\.block))
        editor.session.edit("Replace All", kind: .text, affected: blocks) { page in
            NotePageFinder.replace(targets, with: replacement, in: &page)
        }
        recompute(keepingPosition: origin, reveal: false)
        let count = targets.count
        bar?.flash(count == 1 ? "Replaced 1 match" : "Replaced \(count) matches")
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else {
            if !query.isEmpty { NSSound.beep() }
            return
        }
        let count = matches.count
        let index = currentIndex.map { ($0 + delta + count) % count } ?? (delta > 0 ? 0 : count - 1)
        currentIndex = index
        origin = matches[index].position
        reveal(matches[index])
        refreshViews()
    }

    private func recompute(keepingPosition position: NotePosition?, reveal shouldReveal: Bool) {
        let page = editor.session.page
        matches = NotePageFinder.matches(of: query, in: page, options: options)
        currentIndex = NotePageFinder.firstIndex(atOrAfter: position, in: matches, page: page)
        if shouldReveal, let match = currentMatch { reveal(match) }
        refreshViews()
    }

    private func refreshViews() {
        bar?.refresh()
        highlights.refresh()
        if let bar {
            NSAccessibility.post(element: bar, notification: .announcementRequested,
                                 userInfo: [.announcement: countLabel, .priority: NSAccessibilityPriorityLevel.low.rawValue])
        }
    }

    private func reveal(_ match: NoteFindMatch) {
        expandAncestors(of: match.block)
        let canvas = editor.canvas!
        canvas.scrollBlockToVisible(match.block)
        canvas.layoutSubtreeIfNeeded()
        guard let host = canvas.textHost(for: match.position) else { return }
        let rects = host.textView.selectionRects(for: clamped(match.range, in: host.textView))
        guard let first = rects.first else { return }
        let rect = rects.dropFirst().reduce(canvas.convert(first, from: host.textView)) { $0.union(canvas.convert($1, from: host.textView)) }
        let clipped = canvas.visibleRect.intersection(canvas.bounds)
        let visible = clipped.isEmpty ? canvas.bounds : clipped
        let barHeight = (panel?.frame.height ?? 0) + 24
        let safe = NSRect(x: visible.minX, y: visible.minY + barHeight, width: visible.width, height: max(0, visible.height - barHeight - 40))
        guard !safe.contains(rect) else { return }
        let margin = max(60, visible.height * 0.3)
        canvas.scrollToVisible(NSRect(x: rect.minX, y: rect.minY - margin, width: rect.width, height: rect.height + margin * 2))
    }

    private func expandAncestors(of id: NoteBlockID) {
        let page = editor.session.page
        guard let path = page.path(of: id), path.count > 1 else { return }
        var collapsed: [NoteBlockID] = []
        var cursor = id
        while let parent = page.parent(of: cursor) {
            if let block = page.block(parent), block.isToggle, !block.props.expanded { collapsed.append(parent) }
            cursor = parent
        }
        guard !collapsed.isEmpty else { return }
        editor.session.edit("Expand Toggle", affected: Set(collapsed)) { page in
            for toggle in collapsed { page.update(toggle) { $0.props.expanded = true } }
        }
    }

    private func clamped(_ range: Range<Int>, in textView: NSTextView) -> Range<Int> {
        let length = (textView.string as NSString).length
        let lower = min(range.lowerBound, length)
        return lower..<min(max(lower, range.upperBound), length)
    }

    func highlightRects(in view: NSView) -> [(rect: NSRect, current: Bool)] {
        guard isVisible, !matches.isEmpty, let canvas = editor.canvas else { return [] }
        let clipped = canvas.visibleRect.intersection(canvas.bounds)
        let visible = (clipped.isEmpty ? canvas.bounds : clipped).insetBy(dx: 0, dy: -240)
        var result: [(NSRect, Bool)] = []
        for (index, match) in matches.enumerated() {
            if let frame = canvas.frame(of: match.block), !frame.intersects(visible) { continue }
            guard let host = canvas.textHost(for: match.position) else { continue }
            let textView = host.textView
            guard textView.window === canvas.window, !textView.isHiddenOrHasHiddenAncestor else { continue }
            let range = clamped(match.range, in: textView)
            guard !range.isEmpty else { continue }
            for rect in textView.selectionRects(for: range) {
                let converted = view.convert(rect, from: textView)
                if converted.intersects(visible) { result.append((converted, index == currentIndex)) }
            }
        }
        return result
    }

    private func makeBar() -> NoteFindBar {
        let bar = NoteFindBar(controller: self)
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
        let overlay = editor.canvas.overlayView
        let clipped = overlay.visibleRect.intersection(overlay.bounds)
        let visible = clipped.isEmpty ? overlay.bounds : clipped
        let width = panel.preferredSize.width
        return NSRect(x: max(visible.minX + 12, visible.maxX - width - 16), y: visible.minY + 4, width: width, height: 0)
    }

    private func attachHighlights() {
        let canvas = editor.canvas!
        if highlights.superview !== canvas {
            highlights.removeFromSuperview()
            canvas.addSubview(highlights, positioned: .below, relativeTo: canvas.subviews.first)
        }
        highlights.frame = canvas.bounds
    }

    private func observe() {
        subscription = editor.session.changes.sink { [weak self] change in
            guard let self, change.kind != .selection else { return }
            self.scheduleRefresh()
        }
        let canvas = editor.canvas!
        let center = NotificationCenter.default
        if let clip = canvas.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewportDidChange() }
            })
        }
        canvas.postsFrameChangedNotifications = true
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: canvas, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportDidChange() }
        })
    }

    private func viewportDidChange() {
        guard isVisible, let panel else { return }
        attachHighlights()
        panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false)
        highlights.refresh()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            guard self.isVisible else { return }
            self.recompute(keepingPosition: self.currentMatch?.position ?? self.origin, reveal: false)
            self.bar?.setReplaceEnabled(self.canReplace)
        }
    }

    private func selectedSingleLineText() -> String? {
        guard case .text(let anchor, let head) = editor.session.selection, anchor != head,
              anchor.block == head.block, anchor.field == head.field,
              let text = editor.session.page.text(of: anchor) else { return nil }
        let lower = min(anchor.offset, head.offset), upper = max(anchor.offset, head.offset)
        let value = text.slice(lower..<upper).plainText
        guard !value.contains("\n"), (value as NSString).length <= 200 else { return nil }
        return value
    }

    private static func head(of selection: NotePageSelection) -> NotePosition? {
        switch selection {
        case .text(let anchor, let head):
            return anchor.offset <= head.offset || anchor.block != head.block ? anchor : head
        case .blocks(let ids): return ids.first.map { NotePosition($0, 0) }
        case .cells(let table, let anchor, _): return NotePosition(table, 0, field: .cell(row: anchor.row, column: anchor.column))
        case .none: return nil
        }
    }
}

@MainActor
final class NoteFindHighlightView: NSView {
    weak var controller: NoteFindController?
    static let soft = NoteTheme.adaptive("Find.Soft", light: NoteTheme.rgb(0xFFE16B, 0.5), dark: NoteTheme.rgb(0xE8C33A, 0.28))
    static let strong = NoteTheme.adaptive("Find.Strong", light: NoteTheme.rgb(0xFFB020, 0.62), dark: NoteTheme.rgb(0xFFB020, 0.5))
    private var drawn: [(rect: NSRect, current: Bool)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func refresh() {
        guard let superview else { return }
        if frame != superview.bounds { frame = superview.bounds }
        let next = controller?.highlightRects(in: self) ?? []
        for item in drawn { setNeedsDisplay(item.rect.insetBy(dx: -3, dy: -3)) }
        for item in next { setNeedsDisplay(item.rect.insetBy(dx: -3, dy: -3)) }
        drawn = next
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in drawn where item.rect.insetBy(dx: -3, dy: -3).intersects(dirtyRect) {
            (item.current ? Self.strong : Self.soft).setFill()
            NSBezierPath(roundedRect: item.rect.insetBy(dx: -1.5, dy: 0), xRadius: 3, yRadius: 3).fill()
        }
    }
}

@MainActor
final class NoteFindBar: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 420
    static let rowHeight: CGFloat = 32
    static let padding: CGFloat = 6

    unowned let controller: NoteFindController
    let findField = NotePageFieldBox(placeholder: "Find in note", symbol: "magnifyingglass")
    let replaceField = NotePageFieldBox(placeholder: "Replace with")
    let countLabel = NSTextField(labelWithString: "")
    let disclosure = NotePageChromeButton("Show Replace", symbol: "chevron.right", style: .icon)
    let matchCase = NotePageChromeButton("Match Case", style: .chip)
    let previous = NotePageChromeButton("Previous Match", symbol: "chevron.up", style: .icon)
    let next = NotePageChromeButton("Next Match", symbol: "chevron.down", style: .icon)
    let close = NotePageChromeButton("Close", symbol: "xmark", style: .icon)
    let replaceOne = NotePageChromeButton("Replace", style: .chip)
    let replaceEvery = NotePageChromeButton("Replace All", style: .chip)
    private(set) var isReplacing = false
    private var flashing: String?
    private var flashGeneration = 0

    init(controller: NoteFindController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.rowHeight + Self.padding * 2))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Find in Note")
        countLabel.font = NotePageChrome.labelFont(11, weight: .medium)
        countLabel.textColor = NoteTheme.tertiaryInk
        countLabel.alignment = .right
        countLabel.setAccessibilityElement(false)
        findField.trailingAccessory = countLabel
        findField.field.delegate = self
        findField.field.setAccessibilityLabel("Find")
        replaceField.field.delegate = self
        replaceField.field.setAccessibilityLabel("Replace")
        matchCase.label = "Aa"
        matchCase.setAccessibilityLabel("Match Case")
        disclosure.symbolSize = 10
        previous.symbolSize = 11
        next.symbolSize = 11
        close.symbolSize = 10
        disclosure.onPress = { [unowned controller] in controller.toggleReplacing() }
        matchCase.onPress = { [unowned self, unowned controller] in
            controller.setMatchCase(!controller.options.matchCase)
            self.matchCase.isChecked = controller.options.matchCase
        }
        previous.onPress = { [unowned controller] in controller.findPrevious() }
        next.onPress = { [unowned controller] in controller.findNext() }
        close.onPress = { [unowned controller] in controller.hide() }
        replaceOne.onPress = { [unowned controller] in controller.replaceCurrent() }
        replaceEvery.onPress = { [unowned controller] in controller.replaceAll() }
        disclosure.parcTooltip = TooltipConfiguration("Replace", shortcut: .fixed(KeyboardShortcut(key: "f", flags: [.command, .option])))
        matchCase.parcTooltip = TooltipConfiguration("Match Case")
        previous.parcTooltip = TooltipConfiguration("Previous Match", shortcut: .fixed(KeyboardShortcut(key: "g", flags: [.command, .shift])))
        next.parcTooltip = TooltipConfiguration("Next Match", shortcut: .fixed(KeyboardShortcut(key: "g", flags: [.command])))
        close.parcTooltip = TooltipConfiguration("Close", shortcut: .fixed(KeyboardShortcut(key: "\u{1b}", flags: [])))
        for view in [disclosure, findField, matchCase, previous, next, close, replaceField, replaceOne, replaceEvery] as [NSView] {
            addSubview(view)
        }
        replaceField.isHidden = true
        replaceOne.isHidden = true
        replaceEvery.isHidden = true
        setReplaceEnabled(controller.canReplace)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: Self.padding * 2 + Self.rowHeight * (isReplacing ? 2 : 1) + (isReplacing ? Self.padding : 0))
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    func setReplacing(_ value: Bool, animated: Bool) {
        guard value != isReplacing else { return }
        isReplacing = value
        disclosure.label = value ? "Hide Replace" : "Show Replace"
        rotateDisclosure(animated: animated)
        for view in [replaceField, replaceOne, replaceEvery] as [NSView] {
            view.isHidden = !value
            if value && animated { NotePageChrome.fade(view, to: 1, duration: 0.12) } else { view.alphaValue = 1; view.layer?.opacity = 1 }
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func setReplaceEnabled(_ enabled: Bool) {
        disclosure.isEnabled = enabled
        replaceOne.isEnabled = enabled
        replaceEvery.isEnabled = enabled
        replaceField.field.isEditable = enabled
    }

    private func rotateDisclosure(animated: Bool) {
        guard let layer = disclosure.layer else { return }
        let size = disclosure.bounds.size
        var transform = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        transform = CATransform3DRotate(transform, isReplacing ? .pi / 2 : 0, 0, 0, 1)
        transform = CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0)
        if animated && !NoteTheme.reduceMotion {
            NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: transform), spring: .toggle, key: "note.find.disclosure")
        } else {
            NotePageChrome.withoutAnimation { layer.transform = transform }
        }
    }

    func refresh() {
        countLabel.stringValue = flashing ?? controller.countLabel
        countLabel.textColor = controller.matches.isEmpty && !controller.query.isEmpty && flashing == nil
            ? NoteTheme.color(.text(.red)) : NoteTheme.tertiaryInk
        let hasMatches = !controller.matches.isEmpty
        previous.isEnabled = hasMatches
        next.isEnabled = hasMatches
        replaceOne.isEnabled = hasMatches && controller.canReplace
        replaceEvery.isEnabled = hasMatches && controller.canReplace
        matchCase.isChecked = controller.options.matchCase
        if findField.field.stringValue != controller.query && findField.field.currentEditor() == nil {
            findField.field.stringValue = controller.query
        }
        findField.needsLayout = true
    }

    func flash(_ message: String) {
        flashGeneration += 1
        let generation = flashGeneration
        flashing = message
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.flashing = nil
            self.refresh()
        }
    }

    override func layout() {
        super.layout()
        let pad = Self.padding, row = Self.rowHeight
        var x = pad
        disclosure.frame = NSRect(x: x, y: pad + 2, width: 24, height: row - 4)
        rotateDisclosure(animated: false)
        x += 28
        let trailingButtons: CGFloat = 32 + 28 * 3 + 6
        findField.frame = NSRect(x: x, y: pad, width: bounds.width - x - pad - trailingButtons, height: row)
        var trailing = findField.frame.maxX + 6
        matchCase.frame = NSRect(x: trailing, y: pad + 2, width: 32, height: row - 4)
        trailing += 32
        previous.frame = NSRect(x: trailing, y: pad + 2, width: 28, height: row - 4)
        trailing += 28
        next.frame = NSRect(x: trailing, y: pad + 2, width: 28, height: row - 4)
        trailing += 28
        close.frame = NSRect(x: trailing, y: pad + 2, width: 28, height: row - 4)
        let second = pad * 2 + row
        let allWidth = replaceEvery.intrinsicContentSize.width
        let oneWidth = replaceOne.intrinsicContentSize.width
        replaceEvery.frame = NSRect(x: bounds.width - pad - allWidth, y: second + 2, width: allWidth, height: row - 4)
        replaceOne.frame = NSRect(x: replaceEvery.frame.minX - 4 - oneWidth, y: second + 2, width: oneWidth, height: row - 4)
        replaceField.frame = NSRect(x: x, y: second, width: replaceOne.frame.minX - 6 - x, height: row)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === findField.field else { return }
        flashing = nil
        controller.setQuery(findField.field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            controller.hide()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if control === replaceField.field {
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true { controller.replaceAll() } else { controller.replaceCurrent() }
            } else if shift { controller.findPrevious() } else { controller.findNext() }
            return true
        case #selector(NSResponder.insertTab(_:)):
            guard control === findField.field, isReplacing else { return false }
            window?.makeFirstResponder(replaceField.field)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard control === replaceField.field else { return false }
            window?.makeFirstResponder(findField.field)
            return true
        default:
            return false
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard controller.isVisible, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (key, flags) {
        case ("g", [.command]): controller.findNext(); return true
        case ("g", [.command, .shift]): controller.findPrevious(); return true
        case ("f", [.command]): controller.show(replacing: false); return true
        case ("f", [.command, .option]): controller.show(replacing: true); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
