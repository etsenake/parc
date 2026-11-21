import AppKit
import Combine

@MainActor
final class NoteFormatBarController {
    unowned let editor: NotePageEditor
    var onToast: ((ParcToastContent) -> Void)?
    var colorDefaults: UserDefaults = .standard
    private(set) var state: NoteFormatState?
    private var panel: NoteFloatingPanel?
    private var bar: NoteFormatBarView?
    private var menu: Menu?
    private var pendingShow: DispatchWorkItem?
    private var watchingMouse = false
    private var refreshQueued = false
    private var dismissedSelection: NotePageSelection?
    private var isParked = false
    private var subscription: AnyCancellable?
    private var clipObservers: [NSObjectProtocol] = []
    private weak var observedClip: NSClipView?
    private weak var keyboardReturn: NoteTextView?
    private var hover: NoteLinkHoverController?

    static let keyboardSettle: TimeInterval = 0.22
    static let pointerSettle: TimeInterval = 0.03
    static let mousePoll: TimeInterval = 1.0 / 30

    private struct Menu {
        enum Kind {
            case turnInto(NoteMenuList)
            case color(NoteColorMenuView)
            case link(NoteLinkEditorView)
        }
        var kind: Kind
        var panel: NoteFloatingPanel
        var item: NoteFormatItem
        var selection: NotePageSelection
        var origin: NoteMenuList.Origin
        weak var returnView: NoteTextView?

        var isLink: Bool {
            if case .link = kind { return true }
            return false
        }
    }

    init(editor: NotePageEditor) {
        self.editor = editor
        subscription = editor.session.changes.sink { [weak self] change in self?.sessionDidChange(change) }
        attachHoverIfNeeded()
    }

    var isVisible: Bool { panel?.isPresented == true || menu != nil }
    var isShowingMenu: Bool { menu != nil }
    var isShowingLinkEditor: Bool { menu?.isLink == true }
    var isKeyboardFocused: Bool { bar?.isKeyboardActive == true }

    func selectionDidChange() {
        attachHoverIfNeeded()
        let next = resolveState()
        if let menu {
            if menu.isLink {
                if next?.selection == menu.selection || editor.session.selection == menu.selection { return }
                closeMenu(restoreFocus: false, animated: true)
            } else if next?.selection != menu.selection {
                closeMenu(restoreFocus: false, animated: true)
            }
        }
        guard let next else {
            state = nil
            dismissedSelection = nil
            hideBar(animated: true)
            return
        }
        state = next
        guard next.selection != dismissedSelection else { return }
        dismissedSelection = nil
        if panel?.isPresented == true || isParked {
            bar?.update(next)
            reposition(animated: true)
        } else if menu == nil {
            scheduleShow()
        }
    }

    func layoutDidChange() {
        guard state != nil, panel?.isPresented == true || isParked else { return }
        reposition(animated: false)
    }

    func dismiss(animated: Bool = true) {
        dismissedSelection = state?.selection
        let keyboard = isKeyboardFocused
        closeMenu(restoreFocus: false, animated: animated)
        hideBar(animated: animated)
        hover?.hide(animated: animated)
        if keyboard { returnFromKeyboard() }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if let menu, handleMenuKey(event, menu: menu) { return true }
        hover?.hide(animated: true)
        if eligibleState() != nil {
            if NoteFormatShortcut.focusToolbar.matches(event) { return focusToolbar() }
            if NoteFormatShortcut.link.matches(event) { return openLinkEditor() }
            if NoteFormatShortcut.lastColor.matches(event) { return applyLastColor() }
            if NoteFormatShortcut.equation.matches(event) { return toggleEquation() }
        }
        guard panel?.isPresented == true || pendingShow != nil || watchingMouse else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53, flags.isEmpty {
            dismiss(animated: true)
            return true
        }
        if Self.isTypingKey(event) { hideBar(animated: true) }
        return false
    }

    static func isTypingKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control])
        guard flags.isEmpty else { return false }
        let navigation: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121, 48, 53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        return !navigation.contains(event.keyCode)
    }

    @discardableResult
    func openLinkEditor() -> Bool { openLinkEditor(origin: .keyboard) }

    @discardableResult
    func applyLastColor() -> Bool {
        guard let state = eligibleState(), let style = NoteColorRecents.load(from: colorDefaults).first else { return false }
        editor.session.setColor(style, in: state.selection)
        NoteColorRecents.record(style, in: colorDefaults)
        return true
    }

    @discardableResult
    func toggleEquation() -> Bool {
        guard let state = eligibleState(), state.segments.count == 1, let segment = state.segments.first else { return false }
        let position = segment.position
        guard let text = editor.session.page.block(position.block)?.text(in: position.field) else { return false }
        let changed: (text: NoteText, range: Range<Int>)
        if state.isEquation {
            changed = NoteInlineEquation.unwrap(text, range: segment.range)
        } else {
            guard let wrapped = NoteInlineEquation.wrap(text, range: segment.range) else { return false }
            changed = (wrapped.text, wrapped.atom)
        }
        let selection = NotePageSelection.text(anchor: NotePosition(position.block, changed.range.lowerBound, field: position.field),
                                               head: NotePosition(position.block, changed.range.upperBound, field: position.field))
        editor.session.edit("Equation", kind: .text, affected: [position.block], selection: selection) { page in
            page.update(position.block) { $0.setText(changed.text, in: position.field) }
        }
        restoreTextFocus(selection)
        return true
    }

    @discardableResult
    func focusToolbar() -> Bool {
        guard eligibleState() != nil else { return false }
        if panel?.isPresented != true { showNow() }
        guard panel?.isPresented == true, let bar, let window = bar.window else { return false }
        keyboardReturn = focusedTextView() ?? keyboardReturn
        bar.focusFirst()
        window.makeFirstResponder(bar)
        return true
    }

    func perform(_ item: NoteFormatItem) {
        guard let bar, let button = bar.button(for: item) else { return }
        perform(item, button: button, origin: .keyboard)
    }

    private func sessionDidChange(_ change: NotePageChange) {
        if change.kind == .text, change.origin != nil, panel?.isPresented == true || pendingShow != nil {
            hideBar(animated: true)
        }
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.selectionDidChange()
        }
    }

    private func eligibleState() -> NoteFormatState? {
        guard let next = resolveState() else { return nil }
        state = next
        return next
    }

    private func resolveState() -> NoteFormatState? {
        guard !editor.slashMenu.isOpen, editorHasFocus else { return nil }
        return NoteFormatState.resolve(session: editor.session, isPlainText: editor.environment.isPlainText, isReadOnly: editor.isReadOnly)
    }

    private var editorHasFocus: Bool {
        guard let canvas = editor.canvas, let window = canvas.window else { return true }
        guard let responder = window.firstResponder as? NSView else { return false }
        if let header = canvas.headerView, responder.isDescendant(of: header) { return false }
        return responder === canvas || responder.isDescendant(of: canvas)
    }

    private func focusedTextView() -> NoteTextView? {
        guard let canvas = editor.canvas, let view = canvas.window?.firstResponder as? NoteTextView,
              view.isDescendant(of: canvas) else { return nil }
        return view
    }

    private func scheduleShow() {
        cancelPendingShow()
        if NSEvent.pressedMouseButtons & 1 != 0 {
            watchMouse()
            return
        }
        let type = NSApp.currentEvent?.type
        let pointer = type == .leftMouseUp || type == .leftMouseDown || type == .leftMouseDragged
        let work = DispatchWorkItem { [weak self] in self?.showNow() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (pointer ? Self.pointerSettle : Self.keyboardSettle), execute: work)
    }

    private func watchMouse() {
        guard !watchingMouse else { return }
        watchingMouse = true
        pollMouse()
    }

    private func pollMouse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.mousePoll) { [weak self] in
            guard let self, self.watchingMouse else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 { self.pollMouse(); return }
            self.watchingMouse = false
            guard self.state != nil, self.menu == nil else { return }
            let work = DispatchWorkItem { [weak self] in self?.showNow() }
            self.pendingShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pointerSettle, execute: work)
        }
    }

    private func cancelPendingShow() {
        pendingShow?.cancel()
        pendingShow = nil
        watchingMouse = false
    }

    private func showNow() {
        cancelPendingShow()
        guard menu == nil, let next = resolveState(), next.selection != dismissedSelection else { return }
        state = next
        let bar = ensureBar()
        bar.update(next)
        guard let target = anchor(for: next, size: bar.fittingSize) else {
            isParked = true
            observeViewport()
            return
        }
        let panel = ensurePanel()
        isParked = false
        bar.tooltipAnchor = target.edge == .above ? .top : .bottom
        panel.present(in: editor.canvas.overlayView, anchor: target.anchor, edge: target.edge, animated: true)
        observeViewport()
    }

    private func hideBar(animated: Bool) {
        cancelPendingShow()
        isParked = false
        if bar?.isKeyboardActive == true, menu == nil { bar?.isKeyboardActive = false }
        if let panel, panel.isPresented { panel.dismiss(animated: animated) }
        if menu == nil { stopObservingViewport() }
    }

    private func ensureBar() -> NoteFormatBarView {
        if let bar { return bar }
        let view = NoteFormatBarView(frame: .zero)
        view.onAction = { [weak self] item, button, origin in self?.perform(item, button: button, origin: origin) }
        view.onExitKeyboard = { [weak self] in self?.returnFromKeyboard() }
        view.keyInterceptor = { [weak self] event in self?.barKey(event) ?? false }
        bar = view
        return view
    }

    private func ensurePanel() -> NoteFloatingPanel {
        if let panel { return panel }
        let made = NoteFloatingPanel(content: ensureBar())
        made.alignment = .center
        made.gap = NoteFormatBarPlacement.gap
        made.margin = NoteFormatBarPlacement.margin
        made.setAccessibilityElement(false)
        panel = made
        return made
    }

    private func selectionRects(for state: NoteFormatState) -> [NSRect] {
        guard let canvas = editor.canvas, let selection = editor.selection else { return [] }
        let overlay = canvas.overlayView
        var rects: [NSRect] = []
        for segment in state.segments where !segment.range.isEmpty {
            rects += selection.layout.selectionRects(for: segment.position, range: segment.range)
                .map { NoteFloatingPanel.topDown(overlay.convert($0, from: canvas), in: overlay) }
        }
        if rects.isEmpty, let bounds = selection.selectionBounds {
            rects = [NoteFloatingPanel.topDown(overlay.convert(bounds, from: canvas), in: overlay)]
        }
        return rects
    }

    private var visibleTopDown: NSRect {
        let overlay = editor.canvas.overlayView
        let visible = overlay.visibleRect.isEmpty ? overlay.bounds : overlay.visibleRect
        return NoteFloatingPanel.topDown(visible, in: overlay)
    }

    private func anchor(for state: NoteFormatState, size: NSSize) -> (anchor: NSRect, edge: NoteFloatingPanel.Edge, placement: NoteFormatBarPlacement)? {
        let rects = selectionRects(for: state)
        guard let placement = NoteFormatBarPlacement.compute(lineRects: rects, size: size, visible: visibleTopDown),
              let lines = NoteFormatBarPlacement.lines(of: rects) else { return nil }
        let overlay = editor.canvas.overlayView
        let centre = placement.frame.midX
        let anchor: NSRect
        let edge: NoteFloatingPanel.Edge
        switch placement.edge {
        case .above:
            anchor = NSRect(x: centre, y: lines.top.minY, width: 0, height: lines.top.height)
            edge = .above
        case .below:
            anchor = NSRect(x: centre, y: lines.bottom.minY, width: 0, height: lines.bottom.height)
            edge = .below
        case .pinned:
            anchor = NSRect(x: centre, y: placement.frame.minY - NoteFormatBarPlacement.gap, width: 0, height: 0)
            edge = .below
        }
        return (NoteFloatingPanel.topDown(anchor, in: overlay), edge, placement)
    }

    private func reposition(animated: Bool) {
        guard let state, let bar else { return }
        guard let target = anchor(for: state, size: bar.fittingSize) else {
            if let panel, panel.isPresented { panel.dismiss(animated: true) }
            isParked = true
            return
        }
        bar.tooltipAnchor = target.edge == .above ? .top : .bottom
        let panel = ensurePanel()
        if isParked || !panel.isPresented {
            isParked = false
            guard menu == nil || menu?.isLink == false else { return }
            panel.present(in: editor.canvas.overlayView, anchor: target.anchor, edge: target.edge, animated: true)
        } else {
            panel.reposition(anchor: target.anchor, edge: target.edge, animated: animated)
        }
    }

    private func observeViewport() {
        guard let clip = editor.canvas.enclosingScrollView?.contentView, clip !== observedClip else { return }
        stopObservingViewport()
        observedClip = clip
        let center = NotificationCenter.default
        clipObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification].map { name in
            center.addObserver(forName: name, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewportDidChange() }
            }
        }
    }

    private func stopObservingViewport() {
        for observer in clipObservers { NotificationCenter.default.removeObserver(observer) }
        clipObservers.removeAll()
        observedClip = nil
    }

    private func viewportDidChange() {
        hover?.hide(animated: true)
        guard state != nil, state?.selection != dismissedSelection else { return }
        if panel?.isPresented == true || isParked { reposition(animated: false) }
    }

    private func perform(_ item: NoteFormatItem, button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard let state = eligibleState() else { return }
        if let menu {
            let same = menu.item == item
            closeMenu(restoreFocus: false, animated: true)
            if same { return }
        }
        if let key = item.markKey {
            editor.session.toggleMark(key, in: state.selection)
            return
        }
        switch item {
        case .turnInto: openTurnInto(from: button, state: state, origin: origin)
        case .link: openLinkEditor(origin: origin)
        case .equation: toggleEquation()
        case .color: openColorMenu(from: button, state: state, origin: origin)
        case .mention: mention(state)
        default: break
        }
    }

    private func openTurnInto(from button: NoteToolbarButton, state: NoteFormatState, origin: NoteMenuList.Origin) {
        let columns = editor.session.columnSplitLimit(state.bodyBlocks)
        let list = NoteTurnIntoMenu.makeList(for: state, origin: origin, columns: columns, onPick: { [weak self] option in
            self?.turnInto(option)
        }, onColumns: { [weak self] count in
            self?.turnIntoColumns(count)
        }, onCancel: { [weak self] in
            self?.closeMenu(restoreFocus: true, animated: true)
        })
        presentMenu(.turnInto(list), content: list, item: .turnInto, from: button, state: state, origin: origin)
    }

    private func openColorMenu(from button: NoteToolbarButton, state: NoteFormatState, origin: NoteMenuList.Origin) {
        let grid = NoteColorMenuView(model: NoteColorMenuModel(recents: NoteColorRecents.load(from: colorDefaults), summary: state.color))
        grid.onPick = { [weak self] choice in self?.applyColor(choice) }
        grid.onCancel = { [weak self] in self?.closeMenu(restoreFocus: true, animated: true) }
        grid.prepare(origin: origin)
        presentMenu(.color(grid), content: grid, item: .color, from: button, state: state, origin: origin)
    }

    private func presentMenu(_ kind: Menu.Kind, content: NSView, item: NoteFormatItem, from button: NoteToolbarButton,
                             state: NoteFormatState, origin: NoteMenuList.Origin) {
        let overlay = editor.canvas.overlayView
        let made = NoteFloatingPanel(content: content)
        made.alignment = .leading
        made.present(in: overlay, anchor: overlay.convert(button.bounds, from: button), edge: .below, animated: true)
        menu = Menu(kind: kind, panel: made, item: item, selection: state.selection, origin: origin, returnView: focusedTextView())
        bar?.openItem = item
    }

    private func closeMenu(restoreFocus: Bool, animated: Bool) {
        guard let current = menu else { return }
        menu = nil
        bar?.openItem = nil
        current.panel.dismiss(animated: animated)
        if current.isLink {
            if restoreFocus {
                restoreTextFocus(current.selection, returnView: current.returnView)
                DispatchQueue.main.async { [weak self] in self?.selectionDidChange() }
            }
        } else if restoreFocus, bar?.isKeyboardActive == true, let bar, let window = bar.window, window.firstResponder !== bar {
            window.makeFirstResponder(bar)
        }
    }

    private func handleMenuKey(_ event: NSEvent, menu: Menu) -> Bool {
        switch menu.kind {
        case .turnInto(let list):
            if event.keyCode == 53 {
                closeMenu(restoreFocus: true, animated: true)
                return true
            }
            return list.handleKeyDown(event)
        case .color(let grid):
            return grid.handleKeyDown(event)
        case .link:
            return false
        }
    }

    private func barKey(_ event: NSEvent) -> Bool {
        guard let menu else { return false }
        if case .turnInto = menu.kind, event.keyCode == 123 || event.keyCode == 124 {
            closeMenu(restoreFocus: true, animated: true)
            return false
        }
        return handleMenuKey(event, menu: menu)
    }

    private func returnFromKeyboard() {
        closeMenu(restoreFocus: false, animated: true)
        bar?.isKeyboardActive = false
        if let view = keyboardReturn, let window = view.window {
            window.makeFirstResponder(view)
        } else if let selection = state?.selection {
            restoreTextFocus(selection)
        }
        keyboardReturn = nil
    }

    private func restoreTextFocus(_ selection: NotePageSelection, returnView: NoteTextView? = nil) {
        if bar?.isKeyboardActive == true { bar?.isKeyboardActive = false }
        DispatchQueue.main.async { [weak self] in self?.focusText(selection, preferred: returnView) }
    }

    private func focusText(_ selection: NotePageSelection, preferred: NoteTextView?) {
        guard case .text(_, let head) = selection, let canvas = editor.canvas, canvas.window != nil else { return }
        if editor.session.page.block(head.block) == nil {
            if let preferred, let window = preferred.window { window.makeFirstResponder(preferred) }
            return
        }
        editor.selection.select(selection, reveal: false)
    }

    private func turnInto(_ option: NoteTurnIntoOption) {
        guard let state else { return }
        let origin = menu?.origin
        closeMenu(restoreFocus: false, animated: true)
        editor.session.turnInto(state.bodyBlocks, kind: option.kind, configure: option.configure)
        if origin == .keyboard || focusedTextView() == nil { restoreTextFocus(state.selection) }
    }

    private func turnIntoColumns(_ count: Int) {
        guard let state else { return }
        let origin = menu?.origin
        closeMenu(restoreFocus: false, animated: true)
        editor.session.turnIntoColumns(state.bodyBlocks, count: count)
        if origin == .keyboard || focusedTextView() == nil { restoreTextFocus(state.selection) }
    }

    private func applyColor(_ choice: NoteColorChoice) {
        guard let state else { return }
        let origin = menu?.origin
        closeMenu(restoreFocus: false, animated: true)
        if let style = choice.style {
            editor.session.setColor(style, in: state.selection)
            NoteColorRecents.record(style, in: colorDefaults)
        } else {
            editor.session.updateMarks(in: state.selection, name: "Color") { choice.apply(to: &$0) }
        }
        if origin == .keyboard { restoreTextFocus(state.selection) }
    }

    private func mention(_ state: NoteFormatState) {
        guard state.segments.count == 1, let segment = state.segments.first,
              let host = editor.canvas.textHost(for: segment.position) else { return }
        let view = host.textView
        if let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) }
        let query = state.selectedText.replacingOccurrences(of: "\n", with: " ")
        dismissedSelection = nil
        hideBar(animated: true)
        view.insertText("@" + query, replacementRange: NSRange(location: segment.range.lowerBound, length: segment.range.count))
    }

    @discardableResult
    private func openLinkEditor(origin: NoteMenuList.Origin) -> Bool {
        guard let state = eligibleState() else { return false }
        closeMenu(restoreFocus: false, animated: false)
        let returnView = focusedTextView() ?? keyboardReturn
        let rects = selectionRects(for: state)
        guard let lines = NoteFormatBarPlacement.lines(of: rects) else { return false }
        let environment = editor.environment
        let view = NoteLinkEditorView(existingLink: state.link ?? state.firstLink,
                                      search: { [weak environment] query in environment?.searchNotes(query, limit: NoteLinkEditorView.resultLimit) ?? [] },
                                      linkTarget: { [weak environment] url in environment?.linkTarget(for: url) ?? url.absoluteString })
        view.onAction = { [weak self] action in self?.linkAction(action) }
        hideBar(animated: true)
        bar?.isKeyboardActive = false
        let overlay = editor.canvas.overlayView
        let anchorTopDown = NSRect(x: lines.top.minX, y: lines.bottom.minY, width: max(1, min(lines.top.width, lines.union.width)),
                                   height: lines.bottom.height)
        let made = NoteFloatingPanel(content: view)
        made.alignment = .leading
        made.present(in: overlay, anchor: NoteFloatingPanel.topDown(anchorTopDown, in: overlay), edge: .below, animated: true)
        menu = Menu(kind: .link(view), panel: made, item: .link, selection: state.selection, origin: origin, returnView: returnView)
        observeViewport()
        view.focusField()
        return true
    }

    private func linkAction(_ action: NoteLinkEditorView.Action) {
        guard let current = menu, current.isLink else { return }
        let selection = current.selection
        switch action {
        case .apply(let link):
            guard !NoteLinkInput.isUnsafe(link) else { return }
            closeMenu(restoreFocus: false, animated: true)
            editor.session.setLink(link, in: selection)
            if case .text(let anchor, let head) = selection {
                let end = editor.session.orderedEnds(anchor, head).1
                editor.session.setSelection(.caret(end))
                restoreTextFocus(.caret(end), returnView: current.returnView)
            }
        case .open(let link):
            closeMenu(restoreFocus: true, animated: true)
            open(link)
        case .remove:
            closeMenu(restoreFocus: true, animated: true)
            removeLink(in: selection)
        case .cancel:
            closeMenu(restoreFocus: true, animated: true)
        }
    }

    func removeLink(in selection: NotePageSelection) {
        guard case .text(let anchor, let head) = selection else { return }
        let (start, end) = editor.session.orderedEnds(anchor, head)
        guard start.block == end.block, start.field == end.field,
              let text = editor.session.page.block(start.block)?.text(in: start.field) else {
            editor.session.setLink(nil, in: selection)
            return
        }
        var lower = start.offset, upper = end.offset
        if let span = NoteLinkSpan.at(lower, in: text) { lower = min(lower, span.range.lowerBound); upper = max(upper, span.range.upperBound) }
        if upper > lower, let span = NoteLinkSpan.at(upper - 1, in: text) { upper = max(upper, span.range.upperBound) }
        editor.session.setLink(nil, in: .text(anchor: NotePosition(start.block, lower, field: start.field),
                                              head: NotePosition(start.block, upper, field: start.field)))
    }

    func resolve(_ link: String) -> URL? {
        if NoteLinkInput.isRelative(link) { return editor.environment.resolveNoteLink(link) }
        return URL(string: link)
    }

    static func canOpen(_ link: String) -> Bool {
        !link.hasPrefix("#") && !NoteLinkInput.isUnsafe(link)
    }

    func open(_ link: String) {
        guard Self.canOpen(link), let url = resolve(link), !NoteLinkInput.isUnsafe(url.absoluteString) else { return }
        editor.open(url)
    }

    func follow(_ link: String) {
        guard Self.canOpen(link), let url = resolve(link), !NoteLinkInput.isUnsafe(url.absoluteString) else { return }
        editor.follow(url, event: NSApp.currentEvent)
    }

    func copy(_ link: String) {
        let url = resolve(link)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url, !url.isFileURL { pasteboard.writeObjects([url as NSURL]) }
        pasteboard.setString(url?.absoluteString ?? link, forType: .string)
        showToast(url.map { .copiedLinks([$0]) } ?? .standard("Copied Link"))
    }

    func showToast(_ content: ParcToastContent) {
        if let onToast { onToast(content); return }
        (editor.canvas.window?.windowController as? BrowserWindowController)?.showToast(content)
    }

    func editLink(_ target: NoteLinkHoverController.Target) {
        let selection = NotePageSelection.text(anchor: NotePosition(target.block, target.range.lowerBound, field: target.field),
                                               head: NotePosition(target.block, target.range.upperBound, field: target.field))
        editor.selection.select(selection, reveal: false)
        if editor.session.selection != selection { editor.session.setSelection(selection) }
        dismissedSelection = nil
        _ = openLinkEditor(origin: .pointer)
    }

    private func attachHoverIfNeeded() {
        guard hover == nil, let canvas = editor.canvas else { return }
        let made = NoteLinkHoverController(controller: self)
        made.attach(to: canvas.overlayView)
        hover = made
    }
}

@MainActor
final class NoteLinkHoverController: NSResponder {
    struct Target: Equatable {
        var block: NoteBlockID
        var field: NoteTextField
        var range: Range<Int>
        var link: String
    }

    static let showDelay: TimeInterval = 0.5
    static let switchDelay: TimeInterval = 0.15
    static let hideGrace: TimeInterval = 0.3

    unowned let controller: NoteFormatBarController
    private weak var host: NSView?
    private var area: NSTrackingArea?
    private var panel: NoteFloatingPanel?
    private(set) var current: Target?
    private var pendingTarget: Target?
    private var pendingShow: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?
    private var lastPoint = NSPoint.zero

    init(controller: NoteFormatBarController) {
        self.controller = controller
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var editor: NotePageEditor { controller.editor }

    deinit {
        let area = self.area, host = self.host, panel = self.panel
        pendingShow?.cancel()
        pendingHide?.cancel()
        MainActor.assumeIsolated {
            if let area { host?.removeTrackingArea(area) }
            panel?.dismiss(animated: false)
        }
    }

    func attach(to view: NSView) {
        guard host !== view else { return }
        detach()
        let made = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        view.addTrackingArea(made)
        host = view
        area = made
    }

    func detach() {
        hide(animated: false)
        if let area { host?.removeTrackingArea(area) }
        area = nil
        host = nil
    }

    var isShowing: Bool { panel?.isPresented == true }

    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseEntered(with event: NSEvent) { track(event) }

    override func mouseExited(with event: NSEvent) {
        cancelPendingShow()
        if current != nil { scheduleHide() }
    }

    private func track(_ event: NSEvent) {
        guard let host else { return }
        let point = host.convert(event.locationInWindow, from: nil)
        lastPoint = point
        if let panel, panel.isPresented, panel.frame.insetBy(dx: -6, dy: -6).contains(point) {
            cancelHide()
            cancelPendingShow()
            return
        }
        guard canShow(at: event.locationInWindow), let target = target(at: point) else {
            cancelPendingShow()
            if current != nil { scheduleHide() }
            return
        }
        if target == current {
            cancelHide()
            return
        }
        guard target != pendingTarget else { return }
        cancelPendingShow()
        pendingTarget = target
        let work = DispatchWorkItem { [weak self] in self?.show(target) }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (current == nil ? Self.showDelay : Self.switchDelay), execute: work)
    }

    private func canShow(at windowPoint: NSPoint) -> Bool {
        guard NSEvent.pressedMouseButtons == 0, !controller.isShowingMenu, !editor.slashMenu.isOpen,
              let canvas = editor.canvas, canvas.window?.isKeyWindow != false else { return false }
        return NoteFloatingPanel.allowsHover(for: canvas, at: windowPoint)
    }

    private func target(at point: NSPoint) -> Target? {
        guard let host, let canvas = editor.canvas else { return nil }
        let canvasPoint = canvas.convert(point, from: host)
        var hosts: [NoteTextHost] = []
        if let superview = canvas.superview, let hit = canvas.hitTest(superview.convert(canvasPoint, from: canvas)),
           let textView = sequence(first: hit, next: { $0.superview }).compactMap({ $0 as? NoteTextView }).first,
           let textHost = textView.host {
            hosts.append(textHost)
        }
        if hosts.isEmpty, let id = canvas.blockID(at: canvasPoint), let view = canvas.blockView(for: id) {
            hosts = view.textHosts
        }
        for textHost in hosts {
            let textView = textHost.textView
            let local = textView.convert(canvasPoint, from: canvas)
            guard textView.bounds.contains(local), let index = Self.characterIndex(at: local, in: textView),
                  let text = editor.session.page.block(textHost.blockID)?.text(in: textHost.field),
                  let span = NoteLinkSpan.at(index, in: text) else { continue }
            return Target(block: textHost.blockID, field: textHost.field, range: span.range, link: span.link)
        }
        return nil
    }

    static func characterIndex(at point: NSPoint, in view: NSTextView) -> Int? {
        guard let layoutManager = view.layoutManager, let container = view.textContainer else { return nil }
        let origin = view.textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.insetBy(dx: -1, dy: 0).contains(local) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    private func show(_ target: Target) {
        pendingShow = nil
        pendingTarget = nil
        guard let host, canShow(at: host.convert(lastPoint, to: nil)),
              let textHost = editor.canvas.textHost(for: NotePosition(target.block, target.range.lowerBound, field: target.field)) else { return }
        let rects = textHost.textView.selectionRects(for: target.range).map { host.convert($0, from: textHost.textView) }
        guard let line = rects.first(where: { $0.insetBy(dx: -2, dy: -2).contains(lastPoint) }) ?? rects.first else { return }
        let presentation = Self.presentation(for: target.link, controller: controller)
        let actions: [NoteLinkHoverCard.Action] = (editor.isReadOnly ? [.open, .copy] : NoteLinkHoverCard.Action.allCases)
            .filter { $0 != .open || NoteFormatBarController.canOpen(target.link) }
        let card = NoteLinkHoverCard(title: presentation.title, icon: presentation.icon, actions: actions)
        card.onAction = { [weak self] action in self?.perform(action, on: target) }
        let previous = panel
        let made = NoteFloatingPanel(content: card)
        made.alignment = .leading
        made.present(in: host, anchor: line, edge: .below, animated: previous == nil)
        previous?.dismiss(animated: false)
        panel = made
        current = target
        cancelHide()
    }

    static func presentation(for link: String, controller: NoteFormatBarController) -> (title: String, icon: NoteIcon) {
        presentation(for: link, resolve: { controller.resolve($0) },
                     search: { controller.editor.environment.searchNotes($0, limit: $1) })
    }

    static func presentation(for link: String, resolve: (String) -> URL?,
                             search: (String, Int) -> [NoteReference]) -> (title: String, icon: NoteIcon) {
        if link.hasPrefix("#") { return (String(link.dropFirst()), .symbol("number")) }
        if link.lowercased().hasPrefix("mailto:") { return (NoteLinkInput.displayText(link), .symbol("envelope")) }
        if let url = resolve(link), url.isFileURL {
            let title = url.deletingPathExtension().lastPathComponent
            if NoteFileKind(url: url) != nil {
                let match = search(title, 8).first { $0.url.standardizedFileURL == url.standardizedFileURL }
                return (match?.title ?? title, NoteIcon.note(match?.icon, at: url))
            }
            return (url.lastPathComponent, .symbol("doc"))
        }
        return (NoteLinkInput.displayText(link), .symbol("globe"))
    }

    private func perform(_ action: NoteLinkHoverCard.Action, on target: Target) {
        hide(animated: true)
        switch action {
        case .open: controller.follow(target.link)
        case .copy: controller.copy(target.link)
        case .edit: controller.editLink(target)
        case .remove:
            controller.removeLink(in: .text(anchor: NotePosition(target.block, target.range.lowerBound, field: target.field),
                                            head: NotePosition(target.block, target.range.upperBound, field: target.field)))
        }
    }

    private func scheduleHide() {
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingHide = nil
            self?.hide(animated: true)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideGrace, execute: work)
    }

    private func cancelHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func cancelPendingShow() {
        pendingShow?.cancel()
        pendingShow = nil
        pendingTarget = nil
    }

    func hide(animated: Bool) {
        cancelPendingShow()
        cancelHide()
        current = nil
        guard let panel else { return }
        self.panel = nil
        panel.dismiss(animated: animated)
    }
}
