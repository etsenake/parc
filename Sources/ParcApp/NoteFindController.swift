import AppKit
import Combine

@MainActor
protocol NoteFindPaintable: AnyObject {
    var findHighlights: [NoteFindHighlight] { get set }
}

extension NoteTextView: NoteFindPaintable {}

@MainActor
protocol NoteFindBarController: AnyObject {
    var query: String { get }
    var options: NoteFindOptions { get }
    var countLabel: String { get }
    var hasMatches: Bool { get }
    var canReplace: Bool { get }
    var canReplaceCurrent: Bool { get }
    var isVisible: Bool { get }
    func show(replacing: Bool)
    func hide()
    func findNext()
    func findPrevious()
    func setQuery(_ text: String)
    func setMatchCase(_ value: Bool)
    func toggleReplacing()
    func replaceCurrent()
    func replaceAll()
}

extension NoteFindBarController {
    var canReplaceCurrent: Bool { canReplace }
}

@MainActor
final class NoteFindController: NoteFindBarController {
    private struct Painted {
        weak var view: (any NoteFindPaintable)?
    }

    unowned let editor: NotePageEditor
    private(set) var query = ""
    private(set) var options = NoteFindOptions()
    private(set) var matches: [NoteFindMatch] = []
    private(set) var currentIndex: Int?
    private(set) var isReplacing = false
    var topInset: CGFloat = 4
    private var bar: NoteFindBar?
    private var panel: NoteFloatingPanel?
    private var painted: [ObjectIdentifier: Painted] = [:]
    private var origin: NotePosition?
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private weak var returnResponder: NSResponder?
    private var refreshScheduled = false
    private var paintScheduled = false

    init(editor: NotePageEditor) {
        self.editor = editor
    }

    var isVisible: Bool { panel?.isPresented == true }

    var hasMatches: Bool { !matches.isEmpty }

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

    private var header: NotePageHeaderView? { editor.canvas.headerView as? NotePageHeaderView }

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
            bar.findField.text = seeded
            query = seeded
        }
        bar.refresh()
        let panel = self.panel ?? makePanel(bar)
        if !isVisible {
            observe()
            panel.present(in: canvas.overlayView, anchor: anchorRect(for: panel), edge: .below, animated: true)
            recompute(keepingPosition: origin, reveal: true)
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
        subscriptions.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        panel.dismiss(animated: true)
        matches = []
        currentIndex = nil
        paint()
        guard restoringFocus else { return }
        if let match, match.isTitle, let header {
            header.focusTitle(selecting: match.range)
        } else if let match, editor.canvas.textHost(for: match.position) != nil {
            editor.focus(match.position)
            if let host = editor.canvas.textHost(for: match.position) {
                host.textView.selectedOffsets = match.range
                editor.textSelectionDidChange(in: host)
            }
        } else if let responder = returnResponder, let window = editor.canvas.window,
                  (responder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: window) }) ?? true {
            window.makeFirstResponder(responder)
        }
    }

    func findNext() { step(1) }

    func findPrevious() { step(-1) }

    func useSelectionForFind() {
        guard let text = selectedSingleLineText(), !text.isEmpty else { NSSound.beep(); return }
        if isVisible {
            bar?.findField.text = text
            setQuery(text)
        } else {
            show()
            bar?.findField.text = text
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
        if isVisible, event.keyCode == 53, flags.isEmpty, event.window?.firstResponder === bar?.findField.textField.currentEditor() {
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

    func titleDidChange() {
        guard isVisible else { return }
        scheduleRefresh()
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
        guard canReplace, let match = currentMatch else { NSSound.beep(); return }
        let replacement = bar?.replaceField.text ?? ""
        let after = NotePageFinder.positionAfterReplacing(match, with: replacement)
        if match.isTitle {
            guard let header, header.replaceTitleText([match], with: replacement) else { NSSound.beep(); return }
        } else {
            editor.session.edit("Replace", kind: .text, affected: [match.block]) { page in
                NotePageFinder.replace([match], with: replacement, in: &page)
            }
        }
        origin = after
        recompute(keepingPosition: after, reveal: true)
    }

    func replaceAll() {
        guard canReplace, !matches.isEmpty else { NSSound.beep(); return }
        let replacement = bar?.replaceField.text ?? ""
        let targets = matches
        let titleTargets = targets.filter(\.isTitle)
        let bodyTargets = targets.filter { !$0.isTitle }
        var count = 0
        if !titleTargets.isEmpty, let header {
            let before = header.title
            if header.replaceTitleText(titleTargets, with: replacement) {
                count += NotePageFinder.titleReplacementCount(before, matches: titleTargets)
            }
        }
        if !bodyTargets.isEmpty {
            var preview = editor.session.page
            let outcome = NotePageFinder.replaceCounting(bodyTargets, with: replacement, in: &preview)
            if outcome.count > 0 {
                editor.session.edit("Replace All", kind: .text, affected: outcome.touched) { page in
                    NotePageFinder.replace(bodyTargets, with: replacement, in: &page)
                }
                count += outcome.count
            }
        }
        recompute(keepingPosition: origin, reveal: false)
        bar?.flash(count == 1 ? "Replaced 1" : "Replaced \(count)")
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
        matches = NotePageFinder.matches(of: query, in: page, title: header?.title, options: options)
        currentIndex = NotePageFinder.firstIndex(atOrAfter: position, in: matches, page: page)
        if shouldReveal, let match = currentMatch { reveal(match) }
        refreshViews()
    }

    private func refreshViews() {
        bar?.refresh()
        paint()
        if let bar {
            NSAccessibility.post(element: bar, notification: .announcementRequested,
                                 userInfo: [.announcement: countLabel, .priority: NSAccessibilityPriorityLevel.low.rawValue])
        }
    }

    private func reveal(_ match: NoteFindMatch) {
        let canvas = editor.canvas!
        let target: (view: NSView, rects: [NSRect])
        if match.isTitle {
            guard let header else { return }
            canvas.layoutSubtreeIfNeeded()
            target = (header.titleView, header.titleView.rects(for: match.range))
        } else {
            expandAncestors(of: match.block)
            canvas.scrollBlockToVisible(match.block)
            canvas.layoutSubtreeIfNeeded()
            guard let host = canvas.textHost(for: match.position) else { return }
            target = (host.textView, host.textView.selectionRects(for: clamped(match.range, in: host.textView)))
        }
        guard let first = target.rects.first else { return }
        let rect = target.rects.dropFirst().reduce(canvas.convert(first, from: target.view)) { $0.union(canvas.convert($1, from: target.view)) }
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

    private func paint() {
        var next: [ObjectIdentifier: (view: any NoteFindPaintable, highlights: [NoteFindHighlight])] = [:]
        if isVisible, !matches.isEmpty, let canvas = editor.canvas {
            let clipped = canvas.visibleRect.intersection(canvas.bounds)
            let visible = (clipped.isEmpty ? canvas.bounds : clipped).insetBy(dx: 0, dy: -600)
            for (index, match) in matches.enumerated() {
                let current = index == currentIndex
                guard let view = paintable(for: match, within: visible, current: current) else { continue }
                let key = ObjectIdentifier(view)
                var entry = next[key] ?? (view, [])
                entry.highlights.append(NoteFindHighlight(range: match.range, isCurrent: current))
                next[key] = entry
            }
        }
        for (key, item) in painted where next[key] == nil { item.view?.findHighlights = [] }
        var stored: [ObjectIdentifier: Painted] = [:]
        for (key, entry) in next {
            entry.view.findHighlights = entry.highlights
            stored[key] = Painted(view: entry.view)
        }
        painted = stored
    }

    private func paintable(for match: NoteFindMatch, within visible: NSRect, current: Bool) -> (any NoteFindPaintable)? {
        if match.isTitle { return header?.titleView }
        let canvas = editor.canvas!
        if let frame = canvas.frame(of: match.block), !frame.intersects(visible) { return nil }
        guard let view = canvas.existingBlockView(for: match.block) else { return nil }
        if let host = view.textHosts.first(where: { $0.field == match.field }) { return host.textView }
        return current ? view.textHost(for: match.field)?.textView : nil
    }

    private func schedulePaint() {
        guard !paintScheduled else { return }
        paintScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.paintScheduled = false
            self.paint()
        }
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
        return NSRect(x: max(visible.minX + 12, visible.maxX - width - 16), y: visible.minY + topInset, width: width, height: 0)
    }

    private func observe() {
        subscriptions.removeAll()
        editor.session.changes.sink { [weak self] change in
            guard let self, change.kind != .selection else { return }
            self.scheduleRefresh()
        }.store(in: &subscriptions)
        let canvas = editor.canvas!
        canvas.blockViewDidMaterialize.sink { [weak self] _ in self?.schedulePaint() }.store(in: &subscriptions)
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
        panel.reposition(anchor: anchorRect(for: panel), edge: .below, animated: false)
        paint()
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
        if let header, let window = editor.canvas.window, window.firstResponder === header.titleView {
            let range = header.titleView.selectedRange()
            guard range.length > 0, range.length <= 200 else { return nil }
            return (header.titleView.string as NSString).substring(with: range)
        }
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
final class NoteFindBar: NSView {
    static let width: CGFloat = 440
    static let rowHeight: CGFloat = NoteTheme.fieldHeight
    static let padding: CGFloat = 6

    unowned let controller: any NoteFindBarController
    let findField = NoteSearchField(placeholder: "Find in note")
    let replaceField = NoteSearchField(placeholder: "Replace with")
    let countLabel = NSTextField(labelWithString: "")
    let disclosure = NoteToolbarButton(icon: .symbol("chevron.right"), label: "Replace", shortcut: "⌥⌘F")
    let matchCase = NoteToolbarButton(.text("Aa"), label: "Match Case")
    let previous = NoteToolbarButton(icon: .symbol("chevron.up"), label: "Previous Match", shortcut: "⇧⌘G")
    let next = NoteToolbarButton(icon: .symbol("chevron.down"), label: "Next Match", shortcut: "⌘G")
    let close = NoteToolbarButton(icon: .symbol("xmark"), label: "Close", shortcut: "ESC")
    let replaceOne = NoteChip("Replace", style: .filled)
    let replaceEvery = NoteChip("Replace All", style: .filled)
    private(set) var isReplacing = false

    init(controller: any NoteFindBarController, placeholder: String = "Find in note", label: String = "Find in Note") {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.rowHeight + Self.padding * 2))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(label)
        findField.placeholder = placeholder
        countLabel.font = NoteTheme.chromeFont(12)
        countLabel.textColor = NoteTheme.menuTertiaryInk
        countLabel.alignment = .right
        countLabel.lineBreakMode = .byClipping
        countLabel.setAccessibilityElement(false)
        findField.textField.setAccessibilityLabel("Find")
        replaceField.textField.setAccessibilityLabel("Replace")
        replaceField.showsIcon = false
        findField.onChange = { [unowned controller] text in controller.setQuery(text) }
        findField.onCommand = { [unowned self] selector in self.command(selector, in: self.findField) }
        replaceField.onCommand = { [unowned self] selector in self.command(selector, in: self.replaceField) }
        disclosure.iconPointSize = 11
        previous.iconPointSize = 12
        next.iconPointSize = 12
        close.iconPointSize = 11
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
        replaceOne.setToolTip("Replace", shortcut: "↩")
        replaceEvery.setToolTip("Replace All", shortcut: "⌘↩")
        for view in [disclosure, findField, countLabel, matchCase, previous, next, close, replaceField, replaceOne, replaceEvery] as [NSView] {
            addSubview(view)
        }
        for view in [replaceField, replaceOne, replaceEvery] as [NSView] { view.isHidden = true }
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
        disclosure.setAccessibilityLabel(value ? "Hide Replace" : "Show Replace")
        rotateDisclosure(animated: animated)
        for view in [replaceField, replaceOne, replaceEvery] as [NSView] {
            view.isHidden = !value
            if value && animated, let layer = view.layer {
                NoteAnimation.withoutAnimation { layer.opacity = 0 }
                NoteAnimation.fade(layer, to: 1, duration: NoteAnimation.revealDuration)
            }
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redisplayChromeSubtree()
    }

    func setReplaceEnabled(_ enabled: Bool) {
        disclosure.isEnabled = enabled
        replaceField.textField.isEditable = enabled
        refresh()
    }

    private func rotateDisclosure(animated: Bool) {
        let symbol = isReplacing ? "chevron.down" : "chevron.right"
        guard disclosure.content != .icon(.symbol(symbol)) else { return }
        disclosure.content = .icon(.symbol(symbol))
        if animated { NoteAnimation.pop(disclosure, from: 0.8, spring: .toggle) }
    }

    func refresh() {
        countLabel.stringValue = controller.countLabel
        countLabel.textColor = !controller.hasMatches && !controller.query.isEmpty
            ? NoteTheme.destructiveInk : NoteTheme.menuTertiaryInk
        let hasMatches = controller.hasMatches
        previous.isEnabled = hasMatches
        next.isEnabled = hasMatches
        replaceOne.isEnabled = hasMatches && controller.canReplaceCurrent
        replaceEvery.isEnabled = hasMatches && controller.canReplace
        matchCase.isChecked = controller.options.matchCase
        if findField.text != controller.query && findField.textField.currentEditor() == nil {
            findField.text = controller.query
        }
        needsLayout = true
    }

    func flash(_ message: String) {
        replaceEvery.flash(message)
    }

    override func layout() {
        super.layout()
        let pad = Self.padding, row = Self.rowHeight
        let button = NoteTheme.toolbarButtonSize
        let buttonY = pad + (row - button.height) / 2
        disclosure.frame = NSRect(x: pad, y: buttonY, width: button.width, height: button.height)
        let x = disclosure.frame.maxX + 4
        var trailing = bounds.width - pad
        for view in [close, next, previous] {
            trailing -= button.width
            view.frame = NSRect(x: trailing, y: buttonY, width: button.width, height: button.height)
        }
        let caseWidth = max(button.width, matchCase.intrinsicContentSize.width)
        trailing -= caseWidth + 2
        matchCase.frame = NSRect(x: trailing, y: buttonY, width: caseWidth, height: button.height)
        let countWidth = max(56, ceil(countLabel.intrinsicContentSize.width))
        trailing -= countWidth + 6
        let labelHeight = ceil(countLabel.intrinsicContentSize.height)
        countLabel.frame = NSRect(x: trailing, y: pad + (row - labelHeight) / 2, width: countWidth, height: labelHeight)
        findField.frame = NSRect(x: x, y: pad, width: max(80, trailing - 6 - x), height: row)
        let second = pad * 2 + row
        let chipY = second + (row - NoteTheme.chipHeight) / 2
        let allWidth = replaceEvery.intrinsicContentSize.width
        let oneWidth = replaceOne.intrinsicContentSize.width
        replaceEvery.frame = NSRect(x: bounds.width - pad - allWidth, y: chipY, width: allWidth, height: NoteTheme.chipHeight)
        replaceOne.frame = NSRect(x: replaceEvery.frame.minX - 4 - oneWidth, y: chipY, width: oneWidth, height: NoteTheme.chipHeight)
        replaceField.frame = NSRect(x: x, y: second, width: max(80, replaceOne.frame.minX - 6 - x), height: row)
    }

    private func command(_ selector: Selector, in field: NoteSearchField) -> Bool {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            controller.hide()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if field === replaceField {
                if flags.contains(.command) { controller.replaceAll() } else { controller.replaceCurrent() }
            } else if flags.contains(.shift) {
                controller.findPrevious()
            } else {
                controller.findNext()
            }
            return true
        case #selector(NSResponder.insertTab(_:)):
            guard field === findField, isReplacing else { return false }
            replaceField.focus()
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard field === replaceField else { return false }
            findField.focus()
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
        case ("\r", [.command]) where replaceField.textField.currentEditor() != nil: controller.replaceAll(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
