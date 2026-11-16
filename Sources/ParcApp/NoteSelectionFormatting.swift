import AppKit

@MainActor
final class NoteSelectionTarget {
    let document: NoteFormattingTarget
    let ranges: [NSRange]
    init?(text: EaselStyledTextView, document: NoteDocument) {
        ranges = text.selectedRanges.map(\.rangeValue)
        guard EaselStyledTextView.validFormattingRanges(ranges, length: text.attributedString().length),
              ranges.allSatisfy({ $0.length > 0 && Range($0, in: text.string) != nil }),
              let first = ranges.first,
              let target = NoteFormattingTarget(text: text, document: document, range: first) else { return nil }
        let source = text.string as NSString
        func scalarBoundary(_ index: Int) -> Bool {
            guard index > 0, index < source.length else { return true }
            return !(0xdc00...0xdfff).contains(source.character(at: index)) ||
                !(0xd800...0xdbff).contains(source.character(at: index - 1))
        }
        guard ranges.allSatisfy({ scalarBoundary($0.location) && scalarBoundary(NSMaxRange($0)) }) else { return nil }
        let selected = ranges.map { source.substring(with: $0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, selected != "\u{fffc}" else { return nil }
        self.document = target
    }
    func matches(text: EaselStyledTextView, document: NoteDocument) -> Bool {
        self.document.matches(text: text, document: document) && text.selectedRanges.map(\.rangeValue) == ranges
    }
}

@MainActor
enum NoteSelectionGeometry {
    static let size = NSSize(width: 225.5, height: 50.5)
    static func frame(text: NSTextView, range: NSRange, in host: NSView) -> NSRect? {
        guard let container = text.textContainer, let layout = text.layoutManager,
              range.length > 0, range.location < text.attributedString().length else { return nil }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var firstLineGlyphs = NSRange()
        let first = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &firstLineGlyphs)
        let firstSelected = layout.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, firstLineGlyphs), in: container)
        let glyphRect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let origin = text.textContainerOrigin
        let selected = host.convert(glyphRect.offsetBy(dx: origin.x, dy: origin.y), from: text)
        let line = host.convert(first.offsetBy(dx: origin.x, dy: origin.y), from: text)
        let firstSelection = host.convert(firstSelected.offsetBy(dx: origin.x, dy: origin.y), from: text)
        let visible = host.visibleRect.insetBy(dx: 2, dy: 2)
        guard visible.width > 0, visible.height >= size.height, visible.intersects(selected) else { return nil }
        let width = min(size.width, visible.width)
        let below = selected.minY + line.height
        let above = selected.minY - size.height - 5
        let y = below + size.height <= visible.maxY ? below : max(visible.minY, above)
        return NSRect(x: min(max(visible.minX, firstSelection.minX), visible.maxX - width),
                      y: min(max(visible.minY, y), visible.maxY - size.height), width: width, height: size.height)
    }
}

@MainActor
final class NoteSelectionFormatting: NSObject {
    private weak var text: EaselStyledTextView?
    private weak var host: NoteFormattingView?
    private let session: NoteSession
    private weak var owner: NSWindow?
    private var target: NoteSelectionTarget?
    private var linkTarget: NoteSelectionTarget?
    private var bar: NoteSelectionBar?
    private var paragraphMenu: NSMenu?
    private var pending: UInt64 = 0
    private var performing = false
    private var geometry = NSRect.zero
    private let linkAnchor = NSView()
    nonisolated(unsafe) private var monitor: Any?
    nonisolated(unsafe) private var linkPopoverObserver: NoteAccessibility.PopoverCloseObserver?
    var isPresenting: Bool { bar != nil }
    var frame: NSRect? { bar?.frame }
    func settleMotion() { bar?.settleMotion() }

    init(text: EaselStyledTextView?, session: NoteSession, host: NoteFormattingView) {
        self.text = text; self.session = session; self.host = host
        super.init()
        linkAnchor.setAccessibilityElement(false); host.addSubview(linkAnchor)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResigned(_:)), name: NSWindow.didResignKeyNotification, object: nil)
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        linkPopoverObserver?.invalidate()
    }
    func hitTest(_ point: NSPoint) -> NSView? {
        guard let bar, bar.frame.contains(point) else { return nil }
        return bar.hitTest(point)
    }
    func selectionChanged() {
        guard !performing else { return }
        dismiss(restoreFocus: false)
        let request = pending
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pending == request else { return }
            self.present()
        }
    }
    func localBodyPublished(previous: NoteDocument) {
        guard let text else { return }
        for token in [target, linkTarget].compactMap({ $0 }) where token.matches(text: text, document: previous) {
            token.document.localBodyPublished(text: text, previous: previous, current: session.document)
        }
    }
    func contentsChanged() { if !performing { dismiss(restoreFocus: false) } }
    func editingEnded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let token = self.target else { return }
            if !self.valid(token) { self.dismiss(restoreFocus: false) }
        }
    }
    func reconcileGeometry() {
        guard let host, let text, bar != nil else { return }
        if host.convert(text.bounds, from: text) != geometry || host.visibleRect != visibleAtAdmission {
            dismiss(restoreFocus: false)
        }
    }
    private var visibleAtAdmission = NSRect.zero
    func present(focus: Bool = false) {
        guard let text, let host, !host.blocksSelectionMenu, let window = host.window,
              text.window === window, window.isKeyWindow, window.attachedSheet == nil,
              !host.isHiddenOrHasHiddenAncestor,
              focus || window.firstResponder === text else { return }
        if focus, !window.makeFirstResponder(text) { return }
        guard let token = NoteSelectionTarget(text: text, document: session.document) else { return }
        if focus { NoteAccessibility.reveal(token.ranges[0], in: text) }
        guard let frame = NoteSelectionGeometry.frame(text: text, range: token.ranges[0], in: host) else { return }
        dismiss(restoreFocus: false)
        target = token; owner = window; geometry = host.convert(text.bounds, from: text); visibleAtAdmission = host.visibleRect
        let bar = NoteSelectionBar(text: text, ranges: token.ranges,
            canInteract: { [weak self] in self?.valid(token) == true },
            onFormat: { [weak self] in self?.showParagraphMenu() },
            onEmphasis: { [weak self] in self?.perform($0) },
            onLink: { [weak self] in self?.editLink() },
            onCancel: { [weak self] in self?.dismiss() })
        self.bar = bar; bar.frame = frame
        NoteMotion.presentImmediately(bar, in: host)
        if focus { window.makeFirstResponder(bar) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let host = self.host, let bar = self.bar, self.paragraphMenu == nil else { return }
                if event.type == .scrollWheel || event.window !== self.owner ||
                    !bar.frame.contains(host.convert(event.locationInWindow, from: nil)) { self.dismiss(restoreFocus: false) }
            }
            return event
        }
    }
    func pressEnter() { bar?.pressEnter() }
    func dismiss(restoreFocus: Bool = true) {
        pending &+= 1
        paragraphMenu?.cancelTracking(); paragraphMenu = nil
        let old = bar; bar?.invalidate(); NoteMotion.dismissImmediately(bar); bar = nil; target = nil; linkTarget = nil; owner = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if restoreFocus, let text { NoteAccessibility.restoreBodyIfMenuRelinquished(text, owned: old) }
    }
    @objc private func windowResigned(_ note: Notification) {
        if note.object as? NSWindow === owner { dismiss(restoreFocus: false) }
    }
    private func valid(_ token: NoteSelectionTarget, requireCurrent: Bool = true) -> Bool {
        guard let text, let host, let window = text.window,
              (requireCurrent ? target === token : linkTarget === token), host.window === window,
              !host.isHiddenOrHasHiddenAncestor, !host.blocksSelectionMenu,
              token.matches(text: text, document: session.document), window.attachedSheet == nil else { return false }
        return !requireCurrent || (host.convert(text.bounds, from: text) == geometry && host.visibleRect == visibleAtAdmission &&
            owner === window && window.isKeyWindow &&
            (window.firstResponder === text || (window.firstResponder as? NSView).map { first in
                bar.map { first === $0 || first.isDescendant(of: $0) } ?? false
            } == true))
    }
    private func apply(_ change: (EaselStyledTextView, [NSRange]) -> Void) -> Bool {
        guard let token = target, valid(token), let text else { return false }
        let hadKeyboardFocus = owner?.firstResponder === bar
        let selectedIndex = bar?.selectedIndex
        performing = true
        change(text, token.ranges)
        performing = false
        present(focus: hadKeyboardFocus)
        if hadKeyboardFocus { bar?.restoreKeyboardSelection(selectedIndex) }
        return true
    }
    func perform(_ emphasis: EaselStyledTextView.Emphasis) {
        if !apply({ $0.toggle(emphasis, ranges: $1) }) { dismiss() }
    }
    func performMenuCommand(_ command: TextFormatCommand) -> Bool {
        if let emphasis = command.emphasis { return apply { $0.toggle(emphasis, ranges: $1) } }
        if let kind = command.paragraph { return apply { $0.changeParagraph(kind, ranges: $1) } }
        return false
    }
    func editLinkFromMenu() {
        guard let text else { return }
        if target.map({ valid($0) }) != true {
            _ = NoteAccessibility.returnFocus(to: text, in: text.window)
            if let range = text.selectedRanges.first?.rangeValue { NoteAccessibility.reveal(range, in: text) }
            present()
        }
        if target.map({ valid($0) }) == true { editLink(); return }
        guard text.window?.firstResponder === text,
              let token = NoteSelectionTarget(text: text, document: session.document) else { return }
        dismiss(restoreFocus: false); linkTarget = token
        text.editLink(relativeTo: text, rect: text.revealedSelectionRect(), ranges: token.ranges, validate: { [weak self] in
            self?.valid(token, requireCurrent: false) == true
        })
        stopLinkPopoverObserver()
        linkPopoverObserver = NoteAccessibility.observePopoverClose(positioning: text, restore: text)
    }
    func makeParagraphMenu() -> NSMenu? {
        guard let token = target, valid(token), let text else { return nil }
        let menu = NSMenu(title: "Format Selection"); menu.autoenablesItems = false
        let kinds: [EaselParagraphEditing.Kind] = [.text, .heading1, .heading2, .heading3, .bullets, .numbers]
        let value = text.attributedString()
        let selectedKinds = token.ranges.flatMap { EaselParagraphEditing.ranges(text.string, selection: $0) }.map { range in
            EaselParagraphEditing.kind(value.attributes(at: range.location, effectiveRange: nil))
        }
        for kind in kinds {
            if kind == .bullets { menu.addItem(.separator()) }
            let item = NSMenuItem(title: kind == .text ? "Plain Text" : kind.rawValue, action: #selector(applyParagraph(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = NoteParagraphChoice(kind: kind, target: token)
            item.state = !selectedKinds.isEmpty && selectedKinds.allSatisfy({ $0 == kind }) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
    private func showParagraphMenu() {
        guard let menu = makeParagraphMenu(), let bar, let host else { return }
        paragraphMenu = menu
        menu.popUp(positioning: nil, at: bar.frame.origin, in: host)
        if paragraphMenu === menu { paragraphMenu = nil }
    }
    @objc private func applyParagraph(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? NoteParagraphChoice, valid(choice.target), let text else { dismiss(); return }
        performing = true
        text.changeParagraph(choice.kind, ranges: choice.target.ranges)
        performing = false
        present()
    }
    private func editLink() {
        guard let token = target, valid(token), let text, let bar, let host, let window = owner else { dismiss(); return }
        linkAnchor.frame = bar.frame; host.addSubview(linkAnchor)
        dismiss(restoreFocus: false); linkTarget = token
        text.editLink(relativeTo: linkAnchor, ranges: token.ranges, validate: { [weak self, weak window] in
            guard let self, let window, self.text?.window === window else { return false }
            return self.valid(token, requireCurrent: false)
        })
        stopLinkPopoverObserver()
        linkPopoverObserver = NoteAccessibility.observePopoverClose(positioning: linkAnchor, restore: text)
    }
    func stopLinkPopoverObserver() {
        linkPopoverObserver?.invalidate(); linkPopoverObserver = nil
    }
}

@MainActor
private final class NoteParagraphChoice: NSObject {
    let kind: EaselParagraphEditing.Kind
    let target: NoteSelectionTarget
    init(kind: EaselParagraphEditing.Kind, target: NoteSelectionTarget) { self.kind = kind; self.target = target }
}

@MainActor
final class NoteSelectionBar: NSView {
    private let scroll = NSScrollView()
    private let content = NSView()
    private let surface = NSView()
    private var buttons: [NoteFormatButton] = []
    private var highlights: [NSView] = []
    private var actions: [() -> Void] = []
    private var separators: [NSView] = []
    private let canInteract: () -> Bool
    private let cancel: () -> Void
    private var active = true
    private(set) var selectedIndex: Int?
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    init(text: EaselStyledTextView, ranges: [NSRange], canInteract: @escaping () -> Bool,
         onFormat: @escaping () -> Void, onEmphasis: @escaping (EaselStyledTextView.Emphasis) -> Void,
         onLink: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.canInteract = canInteract; cancel = onCancel
        super.init(frame: .zero)
        surface.wantsLayer = true; surface.layer?.cornerRadius = 7
        surface.layer?.shadowColor = NSColor.black.cgColor
        surface.layer?.shadowOpacity = 0.12; surface.layer?.shadowRadius = 7
        surface.setAccessibilityElement(false); addSubview(surface)
        NoteAccessibility.configureSelectionBar(self)
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.documentView = content; surface.addSubview(scroll)
        add(.text, label: "Format Selection", checked: false, disclosure: true, action: onFormat)
        for (emphasis, action) in [(EaselStyledTextView.Emphasis.bold, NoteFormatAction.bold),
                                   (.italic, .italic), (.underline, .underline), (.strikethrough, .strikethrough)] {
            add(action, label: emphasis.rawValue.capitalized, checked: text.hasEmphasis(emphasis, ranges: ranges)) { onEmphasis(emphasis) }
        }
        let primary = text.selectedRange(), attributed = text.attributedString()
        let linked = primary.length > 0 && primary.location < attributed.length &&
            attributed.attribute(.link, at: primary.location, effectiveRange: nil) != nil
        add(.link, label: "Link", checked: linked, action: onLink)
        for _ in 0..<2 {
            let divider = NSView(); divider.wantsLayer = true; divider.setAccessibilityElement(false)
            content.addSubview(divider); separators.append(divider)
        }
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func add(_ action: NoteFormatAction, label: String, checked: Bool, disclosure: Bool = false, action callback: @escaping () -> Void) {
        let button = NoteFormatButton(item: .action(action), target: self, action: #selector(activate(_:)), showsDisclosure: disclosure)
        button.tag = buttons.count; button.setAccessibilityLabel(label); button.toolTip = label
        button.setAccessibilityRole(.button); button.state = checked ? .on : .off
        let highlight = NoteMotion.makeHighlight()
        content.addSubview(button); content.addSubview(highlight, positioned: .below, relativeTo: button)
        buttons.append(button); highlights.append(highlight); actions.append(callback)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshAppearance()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAppearance() }
    private func refreshAppearance() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            surface.layer?.backgroundColor = NoteFormattingAppearance.background.cgColor
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            surface.layer?.borderColor = (dark ? NoteFormattingAppearance.border : NSColor.clear).cgColor
            surface.layer?.borderWidth = 0.5
            separators.forEach { $0.layer?.backgroundColor = NoteFormattingAppearance.border.withAlphaComponent(0.2).cgColor }
        }
        CATransaction.commit()
        highlights.forEach(NoteMotion.refreshHighlight)
        buttons.forEach { $0.needsDisplay = true }
    }
    override func layout() {
        super.layout()
        surface.frame = NSRect(x: 0, y: max(0, (bounds.height - 34) / 2), width: bounds.width, height: min(34, bounds.height))
        scroll.frame = surface.bounds.insetBy(dx: 6, dy: 0)
        content.frame = NSRect(x: 0, y: 0, width: 213.5, height: scroll.contentSize.height)
        let starts: [CGFloat] = [0, 42, 74, 106, 138, 181.5]
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: starts[index], y: 0, width: index == 0 ? 36 : 32, height: content.bounds.height)
            if highlights.indices.contains(index) { NoteMotion.layoutHighlight(highlights[index], over: button) }
        }
        for (index, divider) in separators.enumerated() {
            divider.frame = NSRect(x: index == 0 ? 40 : 175.5, y: 8, width: 1, height: max(0, content.bounds.height - 16))
        }
    }
    func invalidate() {
        active = false; settleMotion()
        buttons.forEach { $0.isEnabled = false; $0.target = nil; $0.action = nil }
    }
    func settleMotion() {
        NoteMotion.settle(self)
        for (index, highlight) in highlights.enumerated() {
            highlight.alphaValue = highlightOwns(index) ? 1 : 0
        }
        buttons.forEach { $0.alphaValue = 1 }
    }
    private func highlightOwns(_ index: Int) -> Bool {
        buttons.indices.contains(index) && buttons[index].tag == selectedIndex && buttons[index].state != .on
    }
    func restoreKeyboardSelection(_ index: Int?, animated: Bool = false) {
        selectedIndex = index.flatMap { buttons.indices.contains($0) ? $0 : nil }
        for (offset, button) in buttons.enumerated() {
            button.keyboardSelected = button.tag == selectedIndex
            if highlights.indices.contains(offset) {
                NoteMotion.setHighlight(highlights[offset], selected: highlightOwns(offset), animated: animated)
            }
        }
    }
    func pressEnter() {
        guard let selectedIndex, buttons.indices.contains(selectedIndex) else { return }
        activate(buttons[selectedIndex])
    }
    @objc private func activate(_ sender: NSButton) {
        guard active, sender.isEnabled, actions.indices.contains(sender.tag),
              buttons[sender.tag] === sender else { return }
        guard canInteract() else { cancel(); return }
        actions[sender.tag]()
    }
    override func keyDown(with event: NSEvent) {
        guard active else { return }
        guard canInteract() else { cancel(); return }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53, 48: cancel()
        case 123, 124:
            let enabled = buttons.indices.filter { buttons[$0].isEnabled }
            guard let next = NoteAccessibility.nextIndex(from: selectedIndex, enabled: enabled, step: event.keyCode == 124 ? 1 : -1) else { return }
            restoreKeyboardSelection(next, animated: true); NoteAccessibility.reveal(buttons[next])
        case 36, 76, 49:
            if let selectedIndex { activate(buttons[selectedIndex]) }
        default: super.keyDown(with: event)
        }
    }
}
