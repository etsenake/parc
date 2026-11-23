import AppKit
import ParcCore
import ParcKit
import ParcNotes

@MainActor
private final class EaselPopoverHandle: EaselPanelHandle {
    let popover: NotePagePopover
    init(_ popover: NotePagePopover) { self.popover = popover }
    var isOpen: Bool { popover.isOpen }
    func close() { popover.close() }
}

@MainActor
private final class EaselHoverArea: NSObject {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    @objc func mouseEntered(_ event: NSEvent) { entered?() }
    @objc func mouseExited(_ event: NSEvent) { exited?() }
}

@MainActor
final class EaselPanels: EaselPanelPresenting {
    private let containerProvider: () -> NSView?
    private var container: NSView? { containerProvider() }
    private let search: (String, Int) -> [NoteReference]
    var follow: ((String) -> Void)?
    var copy: ((String) -> Void)?
    var toast: ((ParcToastContent) -> Void)?
    private var editor: EaselPopoverHandle?
    private var hover: NoteFloatingPanel?
    private var hoverKey: String?
    private var hoverArea: EaselHoverArea?
    private var hoverTracking: NSTrackingArea?
    private var hoverMonitor: Any?
    private var pendingKey: String?
    private var latest: EaselLinkHoverRequest?
    private var pendingShow: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?

    init(container: @escaping () -> NSView?, search: @escaping (String, Int) -> [NoteReference]) {
        containerProvider = container
        self.search = search
    }

    deinit {
        nonisolated(unsafe) let monitor = hoverMonitor
        let card = hover
        guard monitor != nil || card != nil else { return }
        Task { @MainActor in
            if let monitor { NSEvent.removeMonitor(monitor) }
            card?.dismiss(animated: false)
        }
    }

    func closeAll(animated: Bool = false) {
        hideHover(animated: animated)
        editor?.close()
    }

    func presentLinkEditor(_ request: EaselLinkRequest) -> EaselPanelHandle? {
        guard let container, container.window != nil else { return nil }
        closeAll()
        let webOnly = request.webOnly
        let view = NoteLinkEditorView(existingLink: request.link,
                                      search: { [weak self] query in webOnly ? [] : self?.search(query, NoteLinkEditorView.resultLimit) ?? [] },
                                      linkTarget: { $0.absoluteString })
        view.accepts = webOnly ? { EaselObjectLink.normalized($0) != nil } : { EaselRichText.validLink($0) }
        if webOnly {
            view.field.placeholder = "Paste a link"
            view.emptyTitle = "Paste a link"
            view.noMatchTitle = "Enter a web link, like example.com."
        } else {
            view.noMatchTitle = "That’s not a link I can keep, and no notes match."
        }
        view.refresh()
        let popover = NotePagePopover(content: view)
        let handle = EaselPopoverHandle(popover)
        let previous = container.window?.firstResponder
        popover.onClose = { [weak self, weak handle, weak previous] in
            guard let self else { return }
            if self.editor === handle { self.editor = nil }
            self.restoreFocus(previous)
        }
        view.onAction = { [weak self, weak popover] action in
            switch action {
            case .apply(let link):
                popover?.close(animated: true)
                request.commit(link)
            case .remove:
                popover?.close(animated: true)
                request.commit(nil)
            case .open(let link):
                popover?.close(animated: true)
                self?.follow?(link)
            case .cancel:
                popover?.close(animated: true)
            }
        }
        editor = handle
        popover.present(in: container, anchor: container.convert(request.anchor, from: request.host), edge: .below)
        view.focusField()
        return handle
    }

    func presentTextSizeEditor(_ request: EaselTextSizeRequest) -> EaselPanelHandle? {
        guard let container, container.window != nil else { return nil }
        closeAll()
        let view = EaselFieldMenuView(frame: .zero)
        let current = request.points.map { Int($0.rounded()) }
        view.field.placeholder = "8 to 400"
        view.field.text = current.map(String.init) ?? ""
        view.field.textField.setAccessibilityLabel("Text size in points")
        view.list.items = Self.sizePresets.map { size in
            NoteMenuList.Item(id: "size-\(size)", title: "\(size) pt", isChecked: size == current)
        }
        let popover = NotePagePopover(content: view)
        let handle = EaselPopoverHandle(popover)
        let previous = container.window?.firstResponder
        popover.onClose = { [weak self, weak handle, weak previous] in
            guard let self else { return }
            if self.editor === handle { self.editor = nil }
            self.restoreFocus(previous)
        }
        let apply: (String) -> Void = { [weak view, weak popover] text in
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let points = Double(value), points.isFinite, EaselTextStyle.customSizes.contains(points.rounded()) else {
                view?.notice = "Pick a size from 8 to 400."
                NSSound.beep()
                return
            }
            popover?.close(animated: true)
            request.commit(points.rounded())
        }
        view.field.onChange = { [weak view] _ in view?.notice = nil }
        view.field.onSubmit = apply
        view.list.onActivate = { item in
            guard item.id.hasPrefix("size-") else { return }
            apply(String(item.id.dropFirst(5)))
        }
        view.list.onCancel = { [weak popover] in popover?.close() }
        view.field.onCommand = { [weak view, weak popover] selector in
            guard let view else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                return view.list.handle(command: selector)
            case #selector(NSResponder.insertNewline(_:)):
                return view.field.text.trimmingCharacters(in: .whitespaces).isEmpty && view.list.activateHighlighted()
            case #selector(NSResponder.cancelOperation(_:)):
                popover?.close()
                return true
            default:
                return false
            }
        }
        popover.onKeyDown = { [weak view] event in
            guard let view else { return false }
            if [UInt16(36), UInt16(76)].contains(event.keyCode), !view.field.text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            return view.list.handleKeyDown(event)
        }
        editor = handle
        popover.present(in: container, anchor: container.convert(request.anchor, from: request.host), edge: .below)
        view.list.prepare(origin: .keyboard)
        view.field.focus()
        view.field.textField.currentEditor()?.selectAll(nil)
        return handle
    }

    static let sizePresets = [12, 14, 16, 18, 24, 36, 48, 72, 96, 144]

    private func restoreFocus(_ previous: NSResponder?) {
        guard let window = container?.window, let target = previous as? NSView, target.window === window else { return }
        let responder = window.firstResponder
        guard responder == nil || responder === window || (responder as? NSText)?.isFieldEditor == true else { return }
        window.makeFirstResponder(target)
    }

    func hoverLink(_ request: EaselLinkHoverRequest?) {
        guard let request else {
            cancelPendingShow()
            if hoverKey != nil, !pointerIsOverCard { scheduleHide() }
            return
        }
        guard editor?.isOpen != true else { return }
        if request.key == hoverKey {
            latest = request
            cancelHide()
            return
        }
        guard request.key != pendingKey else { latest = request; return }
        cancelPendingShow()
        pendingKey = request.key
        latest = request
        let work = DispatchWorkItem { [weak self] in self?.showHover() }
        pendingShow = work
        let delay = hoverKey == nil ? NoteLinkHoverController.showDelay : NoteLinkHoverController.switchDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func showHover() {
        pendingShow = nil
        guard let request = latest, request.key == pendingKey, let container, let window = container.window, window.isKeyWindow,
              NSEvent.pressedMouseButtons == 0, NotePagePopover.topmost == nil,
              NoteFloatingPanel.allowsHover(for: container, at: window.mouseLocationOutsideOfEventStream) else {
            pendingKey = nil
            return
        }
        pendingKey = nil
        let link = request.link
        let presentation = NoteLinkHoverController.presentation(for: link, resolve: { URL(string: $0) }, search: search)
        var actions: [NoteLinkHoverCard.Action] = []
        if NoteFormatBarController.canOpen(link) { actions.append(.open) }
        actions.append(.copy)
        if request.canEdit { actions += [.edit, .remove] }
        let card = NoteLinkHoverCard(title: presentation.title, icon: presentation.icon, actions: actions)
        card.onAction = { [weak self] action in
            self?.hideHover(animated: true)
            switch action {
            case .open: self?.follow?(link)
            case .copy:
                self?.copy?(link)
                self?.toast?(URL(string: link).map { .copiedLinks([$0]) } ?? .standard("Copied Link"))
            case .edit: request.edit()
            case .remove: request.remove()
            }
        }
        let previous = hover
        let made = NoteFloatingPanel(content: card)
        made.alignment = .leading
        made.present(in: container, anchor: container.convert(request.anchor, from: request.host), edge: .below, animated: previous == nil)
        previous?.dismiss(animated: false)
        removeHoverTracking()
        hover = made
        hoverKey = request.key
        installHoverTracking(on: made)
        cancelHide()
    }

    private var pointerIsOverCard: Bool {
        guard let hover, let window = hover.window else { return false }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return hover.bounds.insetBy(dx: -6, dy: -6).contains(hover.convert(point, from: nil))
    }

    private func installHoverTracking(on panel: NoteFloatingPanel) {
        let area = EaselHoverArea()
        area.entered = { [weak self] in self?.cancelHide() }
        area.exited = { [weak self] in self?.scheduleHide() }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: area)
        panel.addTrackingArea(tracking)
        hoverArea = area
        hoverTracking = tracking
        if hoverMonitor == nil {
            hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.hover != nil else { return }
                    if event.type == .leftMouseDown || event.type == .rightMouseDown, self.pointerIsOverCard { return }
                    self.hideHover(animated: false)
                }
                return event
            }
        }
    }

    private func removeHoverTracking() {
        if let hoverTracking { hover?.removeTrackingArea(hoverTracking) }
        hoverTracking = nil
        hoverArea = nil
    }

    private func scheduleHide() {
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            if self.pointerIsOverCard { return }
            self.hideHover(animated: true)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NoteLinkHoverController.hideGrace, execute: work)
    }

    private func cancelHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func cancelPendingShow() {
        pendingShow?.cancel()
        pendingShow = nil
        pendingKey = nil
    }

    func hideHover(animated: Bool) {
        cancelPendingShow()
        cancelHide()
        hoverKey = nil
        removeHoverTracking()
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
        hoverMonitor = nil
        guard let hover else { return }
        self.hover = nil
        hover.dismiss(animated: animated)
    }
}
