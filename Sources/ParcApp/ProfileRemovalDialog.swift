import AppKit

/// Shared DeleteProfileDialog / DeleteUnusedProfilesDialog presentation. The
/// native deletion transaction remains in ProfileRemovalController.
@MainActor
class ProfileRemovalDialog: NSWindowController, NSTextFieldDelegate {
    let confirmation = NSTextField(string: "")
    let removeButton = ProfileRemovalButton("Delete", destructive: true)
    let cancelButton = ProfileRemovalButton("Cancel")
    let detail = NSTextView()
    let results = NSTextView()
    let feedback = NSTextView()
    private let heading = NSTextField(labelWithString: "")
    private let surface = ProfileRemovalSurface()
    private let fieldBorder = ProfileRemovalFieldBorder()
    private let detailScroll = NSScrollView()
    private let resultsScroll = NSScrollView()
    private let feedbackScroll = NSScrollView()
    private let expectedConfirmation: String
    private var busy = false
    private var recovery = false
    private(set) var completed = false
    private(set) var submitted = false
    var onConfirm: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(title: String, detail: NSAttributedString, confirmation expected: String, accessibilityLabel: String) {
        expectedConfirmation = expected
        let window = ProfileRemovalWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 340),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = surface
        window.onCancel = { [weak self] in self?.onCancel?() }
        heading.stringValue = title
        heading.font = .systemFont(ofSize: 18, weight: .bold)
        heading.textColor = Self.titleColor
        surface.addSubview(heading)
        configure(self.detail, scroll: detailScroll, label: "Profile removal explanation")
        self.detail.textStorage?.setAttributedString(detail)
        configure(results, scroll: resultsScroll, label: "Profile removal results")
        configure(feedback, scroll: feedbackScroll, label: "Profile removal status")
        confirmation.font = .systemFont(ofSize: 13)
        confirmation.textColor = Self.titleColor
        confirmation.isBordered = false
        confirmation.drawsBackground = false
        confirmation.focusRingType = .exterior
        confirmation.placeholderString = expected
        confirmation.delegate = self
        confirmation.setAccessibilityLabel(accessibilityLabel)
        fieldBorder.addSubview(confirmation)
        surface.addSubview(fieldBorder)
        for button in [cancelButton, removeButton] {
            button.font = .systemFont(ofSize: 13)
            button.target = self
            surface.addSubview(button)
        }
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.action = #selector(cancel)
        removeButton.keyEquivalent = "\r"
        removeButton.contentTintColor = .systemRed
        removeButton.action = #selector(confirm)
        removeButton.isEnabled = false
        window.initialFirstResponder = confirmation
        updateKeyLoop()
        layoutContent()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static let titleColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white :
            NSColor(srgbRed: 0.094, green: 0.106, blue: 0.122, alpha: 1)
    }
    static let backgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ?
            NSColor(srgbRed: 21 / 255, green: 28 / 255, blue: 48 / 255, alpha: 1) :
            NSColor(srgbRed: 250 / 255, green: 251 / 255, blue: 1, alpha: 1)
    }
    static func copy(_ text: String, emphasizing ranges: [NSRange] = [], size: CGFloat = 14,
                     color: NSColor? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: color ?? titleColor, .paragraphStyle: paragraph])
        for range in ranges where range.location != NSNotFound && NSMaxRange(range) <= result.length {
            result.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: range)
        }
        return result
    }

    private func configure(_ text: NSTextView, scroll: NSScrollView, label: String) {
        text.isEditable = false; text.isSelectable = true; text.isRichText = true
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel(label)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = text
        surface.addSubview(scroll)
    }

    var matchesConfirmation: Bool {
        confirmation.stringValue.caseInsensitiveCompare(expectedConfirmation) == .orderedSame
    }
    func controlTextDidChange(_ notification: Notification) {
        removeButton.isEnabled = !busy && !completed && (recovery || matchesConfirmation)
    }
    func focusConfirmation() {
        window?.makeFirstResponder(confirmation.isEnabled ? confirmation : (completed || busy ? cancelButton : removeButton))
    }
    @objc private func confirm() {
        guard !busy, !completed, recovery || matchesConfirmation, window?.sheetParent != nil, let onConfirm else { return }
        submitted = true
        willSubmit()
        // Latch before invoking a synchronous producer, including its refusal
        // callbacks. Repeated Return cannot issue a second authorization.
        showState("Preparing this profile for removal…", busy: true, canCancel: true)
        onConfirm(confirmation.stringValue)
    }
    func willSubmit() {}
    @objc private func cancel() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    func showState(_ text: String, busy: Bool = false, canCancel: Bool = true,
                   recovery: Bool = false, error: Bool = false, complete: Bool = false) {
        let wasBusy = self.busy
        let wasComplete = completed
        let wasEditing = confirmation.currentEditor() != nil
        self.busy = busy; self.recovery = recovery; completed = complete
        confirmation.isEnabled = !busy && !recovery && !complete
        removeButton.isEnabled = !busy && !complete && (recovery || matchesConfirmation)
        removeButton.isHidden = complete
        removeButton.title = busy ? "Removing…" : (submitted || recovery ? "Retry" : "Delete")
        cancelButton.title = complete ? "Done" : (busy ? (canCancel ? "Cancel" : "Close") : (submitted || recovery ? "Close" : "Cancel"))
        cancelButton.keyEquivalent = "\u{1b}"
        window?.defaultButtonCell = (complete ? cancelButton : removeButton).cell as? NSButtonCell
        let changed = feedback.string != text
        let styledFeedback = Self.copy(text, size: 12, color: error ? .systemRed : Self.titleColor)
        if feedback.attributedString() != styledFeedback {
            feedback.textStorage?.setAttributedString(styledFeedback)
        }
        updateKeyLoop()
        layoutContent()
        if (complete && !wasComplete) || (wasBusy && !busy) || (!confirmation.isEnabled && wasEditing) {
            window?.makeFirstResponder(complete || busy ? cancelButton : (recovery ? removeButton : confirmation))
        }
        if changed, let window, window.isVisible {
            NSAccessibility.post(element: feedback, notification: .valueChanged)
            NSAccessibility.post(element: window, notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    func setResults(_ text: NSAttributedString) {
        guard results.attributedString() != text else { return }
        let offset = resultsScroll.contentView.bounds.origin
        results.textStorage?.setAttributedString(text)
        layoutContent()
        resultsScroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset.y, max(0, results.frame.height - resultsScroll.contentSize.height))))
        resultsScroll.reflectScrolledClipView(resultsScroll.contentView)
    }
    private func updateKeyLoop() {
        confirmation.nextKeyView = cancelButton
        cancelButton.nextKeyView = removeButton.isHidden ? cancelButton : removeButton
        removeButton.nextKeyView = confirmation.isEnabled ? confirmation : cancelButton
    }
    private func textHeight(_ text: NSTextView, width: CGFloat) -> CGFloat {
        text.frame.size.width = width
        text.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let layout = text.layoutManager, let container = text.textContainer else { return 0 }
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }
    private func place(_ text: NSTextView, in scroll: NSScrollView, y: CGFloat, maximum: CGFloat) -> CGFloat {
        // Decide overflow without a scroller first. Once needed, a legacy
        // scroller consumes width; measure again in that actual clip viewport.
        // The narrower width cannot turn an overflowing document into a fit.
        let unscrolledHeight = max(1, textHeight(text, width: 374))
        scroll.hasVerticalScroller = unscrolledHeight > maximum
        scroll.frame = NSRect(x: 38, y: y, width: 374, height: min(unscrolledHeight, maximum))
        text.frame.size.height = unscrolledHeight
        scroll.tile()
        let width = scroll.contentSize.width
        let height = max(1, textHeight(text, width: width))
        let visibleHeight = min(height, maximum)
        scroll.frame.size.height = visibleHeight
        text.frame = NSRect(x: 0, y: 0, width: width, height: max(height, visibleHeight))
        return visibleHeight
    }
    private func layoutContent() {
        guard let window else { return }
        heading.frame = NSRect(x: 38, y: 38, width: 374, height: 24)
        var y: CGFloat = 74
        y += place(detail, in: detailScroll, y: y, maximum: 180) + 8
        fieldBorder.frame = NSRect(x: 38, y: y, width: 374, height: 34)
        confirmation.frame = NSRect(x: 8, y: 7, width: 358, height: 20)
        y += 46
        resultsScroll.isHidden = results.string.isEmpty
        if !resultsScroll.isHidden { y += place(results, in: resultsScroll, y: y, maximum: 140) + 12 }
        feedbackScroll.isHidden = feedback.string.isEmpty
        if !feedbackScroll.isHidden { y += place(feedback, in: feedbackScroll, y: y, maximum: 90) + 12 }
        y += 16
        let primaryWidth = removeButton.preferredWidth, cancelWidth = cancelButton.preferredWidth
        removeButton.frame = NSRect(x: 412 - primaryWidth, y: y, width: primaryWidth, height: 36)
        cancelButton.frame = NSRect(x: 412 - cancelWidth - (completed ? 0 : primaryWidth + 8), y: y, width: cancelWidth, height: 36)
        window.setContentSize(NSSize(width: 450, height: y + 36 + 28))
        surface.needsDisplay = true
    }
}

@MainActor
private final class ProfileRemovalSurface: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        ProfileRemovalDialog.backgroundColor.setFill(); bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}
@MainActor
private final class ProfileRemovalFieldBorder: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.056) : NSColor.black.withAlphaComponent(0.047)).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        path.lineWidth = 1; path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Escape remains available when Done owns the Return default. Native field
/// editors retain first refusal for an active marked-text composition.
@MainActor
private final class ProfileRemovalWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
