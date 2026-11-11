import AppKit

@MainActor
final class EaselWebInput: NSViewController, NSTextFieldDelegate, NSPopoverDelegate {
    private let popover = NSPopover()
    private let mode = PointingHandSegmentedControl(labels: ["Address", "Search"], trackingMode: .selectOne, target: nil, action: nil)
    private let field = NSTextField()
    private let category = PointingHandPopUpButton(frame: .zero, pullsDown: false)
    private let errorLabel = NSTextField(labelWithString: "")
    private let submitButton: NSButton
    private weak var anchor: NSView?
    private weak var parentWindow: NSWindow?
    private weak var previousResponder: NSResponder?
    private let allowsSearch: Bool
    private var draft: EaselWebNavigation.Draft
    private var validOwner: () -> Bool
    private var submit: (URL, EaselWebNavigation.Draft) -> Bool
    private var observations: [NSObjectProtocol] = []
    private var ended = false
    var onClose: (() -> Void)?

    init(draft: EaselWebNavigation.Draft = .init(), submitTitle: String = "Open", allowsSearch: Bool = true,
         validOwner: @escaping () -> Bool, submit: @escaping (URL, EaselWebNavigation.Draft) -> Bool) {
        self.draft = draft; self.allowsSearch = allowsSearch; self.validOwner = validOwner; self.submit = submit
        submitButton = EaselPaletteButton(title: submitTitle, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        popover.behavior = .semitransient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = self; popover.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = EaselSurfaceView(frame: NSRect(x: 0, y: 0, width: 368, height: allowsSearch ? 158 : 76))
        mode.frame = NSRect(x: 14, y: 116, width: 340, height: 27)
        mode.selectedSegment = draft.mode.rawValue; mode.target = self; mode.action = #selector(modeChanged)
        field.frame = NSRect(x: 14, y: 78, width: 340, height: 28)
        field.font = .systemFont(ofSize: 14); field.delegate = self; field.stringValue = draft.text
        field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .exterior
        field.wantsLayer = true; field.layer?.cornerRadius = 8; field.layer?.cornerCurve = .continuous
        category.frame = NSRect(x: 14, y: 38, width: 150, height: 27)
        category.addItems(withTitles: EaselWebNavigation.Category.allCases.map(\.title))
        category.selectItem(at: EaselWebNavigation.Category.allCases.firstIndex(of: draft.category) ?? 1)
        category.setAccessibilityLabel("Search category")
        category.target = self; category.action = #selector(categoryChanged)
        submitButton.frame = NSRect(x: 254, y: 38, width: 100, height: 28)
        submitButton.bezelStyle = .rounded; submitButton.target = self; submitButton.action = #selector(submitInput)
        errorLabel.frame = NSRect(x: 14, y: 10, width: 340, height: 18)
        errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .secondaryLabelColor
        for child in [mode, field, category, submitButton, errorLabel] { view.addSubview(child) }
        if !allowsSearch {
            mode.isHidden = true
            field.frame = NSRect(x: 10, y: 38, width: 260, height: 28)
            submitButton.frame = NSRect(x: 280, y: 38, width: 78, height: 28)
            errorLabel.frame = NSRect(x: 10, y: 10, width: 348, height: 18)
        }
        refreshMode()
    }
    func show(from anchor: NSView) -> Bool {
        guard !ended, validOwner(), let window = anchor.window, window.isKeyWindow,
              window.attachedSheet == nil, !anchor.isHiddenOrHasHiddenAncestor else { return false }
        self.anchor = anchor; parentWindow = window; previousResponder = window.firstResponder
        _ = view
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel(restoreFocus: false) }
            })
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        view.window?.makeFirstResponder(field); field.selectText(nil)
        return true
    }
    func validate() {
        guard !ended else { return }
        if !ownerIsCurrent { cancel(restoreFocus: false) }
    }
    private var ownerIsCurrent: Bool {
        validOwner() && anchor?.window === parentWindow && anchor?.isHiddenOrHasHiddenAncestor == false
            && parentWindow?.isVisible == true && parentWindow?.attachedSheet == nil
    }
    func cancel(restoreFocus: Bool = true) {
        guard !ended else { return }; ended = true
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
        popover.close()
        if restoreFocus, validOwner(), let parentWindow, parentWindow.isKeyWindow, parentWindow.attachedSheet == nil,
           let previousResponder {
            if let previousView = previousResponder as? NSView {
                if SavedFocus.mayReturn(to: previousView, in: parentWindow) { parentWindow.makeFirstResponder(previousView) }
            } else { parentWindow.makeFirstResponder(previousResponder) }
        }
        popover.contentViewController = nil; onClose?(); onClose = nil
    }
    func popoverDidClose(_ notification: Notification) { cancel() }
    @objc private func modeChanged() {
        draft.mode = EaselWebNavigation.Mode(rawValue: mode.selectedSegment) ?? .address
        refreshMode(); view.window?.makeFirstResponder(field)
    }
    @objc private func categoryChanged() {
        guard EaselWebNavigation.Category.allCases.indices.contains(category.indexOfSelectedItem) else { return }
        draft.category = EaselWebNavigation.Category.allCases[category.indexOfSelectedItem]
        errorLabel.stringValue = "Search with DuckDuckGo"
    }
    private func refreshMode() {
        field.placeholderString = draft.mode == .address ? "Paste a URL" : "Search the web"
        field.setAccessibilityLabel(draft.mode == .address ? "Webpage address" : "Search query")
        category.isHidden = !allowsSearch || draft.mode != .search
        errorLabel.stringValue = draft.mode == .search ? "Search with DuckDuckGo" : ""
    }
    func controlTextDidChange(_ notification: Notification) {
        errorLabel.stringValue = ""; errorLabel.textColor = .secondaryLabelColor; field.layer?.borderWidth = 0
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { submitInput(); return true }
        return false
    }
    @objc private func submitInput() {
        guard ownerIsCurrent, !ended else { cancel(restoreFocus: false); return }
        guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        draft.text = field.stringValue
        guard let url = EaselWebNavigation.destination(draft) else {
            errorLabel.stringValue = draft.mode == .address ? "Enter an http or https webpage address." : "Enter a search query."
            errorLabel.textColor = EaselAppearance.error
            field.effectiveAppearance.performAsCurrentDrawingAppearance { field.layer?.borderColor = EaselAppearance.error.cgColor }
            field.layer?.borderWidth = 2
            NSAccessibility.post(element: errorLabel, notification: .valueChanged); return
        }
        if submit(url, draft) { cancel() }
        else { errorLabel.stringValue = "The original Easel page is unavailable. Try again." }
    }
}
