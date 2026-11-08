import AppKit

/// A profile-owned review surface. Chromium supplies the warning and offered
/// choices; this controller never infers that a blocked file may be kept.
@MainActor
final class DownloadReviewController: NSWindowController, NSTextFieldDelegate, NSTextViewDelegate {
    private(set) var review: PCNativeDownloadReview
    var onDecision: ((PCNativeDownloadReview, PCNativeDownloadReviewAction, String, String) -> Bool)?
    var onOpenLink: ((PCNativeDownloadReview, Int) -> Bool)?
    var onRefresh: (() -> PCNativeDownloadReview?)?
    var onClose: (() -> Void)?
    private let root = ThemeRendererView()
    private let stack = FlippedStackView()
    private let scroll = NSScrollView()
    private let fileName = NSTextField(labelWithString: "")
    private let source = NSTextField(labelWithString: "")
    private let warning = NSTextField(wrappingLabelWithString: "")
    private let secondary = NSTextField(wrappingLabelWithString: "")
    private let changed = NSTextField(wrappingLabelWithString: "")
    private let footer = NSStackView()
    private let passwordGroup = NSStackView()
    private let passwordLabel = NSTextField(labelWithString: "")
    private let password = NSSecureTextField(string: "")
    private let passwordError = NSTextField(wrappingLabelWithString: "")
    private let justificationGroup = NSStackView()
    private let justificationLabel = NSTextField(wrappingLabelWithString: "")
    private let justification = NSTextView()
    private let justificationCount = NSTextField(labelWithString: "0 / 280")
    private let progress = NSProgressIndicator()
    private let links = NSStackView()
    private var decisionButtons: [(PCNativeDownloadReviewAction, NSButton)] = []
    private var parentCloseObserver: NSObjectProtocol?
    private var finished = false

    ///
    /// whose window appearance is Dark Aqua.
    init(review: PCNativeDownloadReview, theme: SpaceTheme, incognito: Bool = false) {
        self.review = review
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Review Download"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        if incognito { panel.appearance = NSAppearance(named: .darkAqua) }
        super.init(window: panel)
        root.incognito = incognito
        root.theme = theme
        panel.contentView = root
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 24, bottom: 24, right: 24)
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 340)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        root.addSubview(scroll)
        root.onLayout = { [weak self] in
            guard let self else { return }
            self.scroll.frame = self.root.bounds
            for label in [self.warning, self.secondary, self.changed, self.justificationLabel] {
                label.preferredMaxLayoutWidth = max(200, self.scroll.contentSize.width - 48)
            }
            self.stack.frame = NSRect(x: 0, y: 0, width: self.scroll.contentSize.width,
                height: max(self.stack.fittingSize.height, self.scroll.contentSize.height))
        }

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 10
        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.shield",
                                             accessibilityDescription: "Download warning")!)
        icon.contentTintColor = .systemOrange
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let title = NSTextField(labelWithString: "Review Download")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        header.addArrangedSubview(icon)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 5
        identity.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        identity.wantsLayer = true
        identity.layer?.cornerRadius = 10
        fileName.font = .systemFont(ofSize: 13, weight: .semibold)
        fileName.lineBreakMode = .byTruncatingMiddle
        source.font = .systemFont(ofSize: 11)
        source.lineBreakMode = .byTruncatingMiddle
        identity.addArrangedSubview(fileName)
        identity.addArrangedSubview(source)
        stack.addArrangedSubview(identity)
        identity.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        fileName.widthAnchor.constraint(lessThanOrEqualTo: identity.widthAnchor, constant: -28).isActive = true
        source.widthAnchor.constraint(lessThanOrEqualTo: identity.widthAnchor, constant: -28).isActive = true

        for label in [warning, secondary, changed] {
            label.font = .systemFont(ofSize: label === warning ? 13 : 12)
            label.preferredMaxLayoutWidth = 472
            label.isSelectable = true
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        progress.style = .bar
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        stack.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 6).isActive = true

        passwordGroup.orientation = .vertical
        passwordGroup.alignment = .leading
        passwordGroup.spacing = 6
        passwordLabel.font = .systemFont(ofSize: 12, weight: .medium)
        password.delegate = self
        password.font = .systemFont(ofSize: 13)
        passwordError.font = .systemFont(ofSize: 11)
        passwordError.textColor = .systemRed
        for field in [passwordLabel, password, passwordError] {
            passwordGroup.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: passwordGroup.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(passwordGroup)
        passwordGroup.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true

        justificationGroup.orientation = .vertical
        justificationGroup.alignment = .leading
        justificationGroup.spacing = 6
        justificationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        justificationLabel.preferredMaxLayoutWidth = 472
        justificationGroup.addArrangedSubview(justificationLabel)
        let justificationScroll = NSScrollView()
        justificationScroll.hasVerticalScroller = true
        justificationScroll.borderType = .bezelBorder
        justification.isRichText = false
        justification.isAutomaticQuoteSubstitutionEnabled = false
        justification.isAutomaticDashSubstitutionEnabled = false
        justification.isAutomaticTextReplacementEnabled = false
        justification.font = .systemFont(ofSize: 13)
        justification.delegate = self
        justification.frame = NSRect(x: 0, y: 0, width: 472, height: 74)
        justification.minSize = NSSize(width: 0, height: 74)
        justification.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                       height: CGFloat.greatestFiniteMagnitude)
        justification.isVerticallyResizable = true
        justification.isHorizontallyResizable = false
        justification.autoresizingMask = [.width]
        justification.textContainer?.widthTracksTextView = true
        justification.textContainerInset = NSSize(width: 6, height: 6)
        justificationScroll.documentView = justification
        justificationGroup.addArrangedSubview(justificationScroll)
        justificationScroll.widthAnchor.constraint(equalTo: justificationGroup.widthAnchor).isActive = true
        justificationScroll.heightAnchor.constraint(equalToConstant: 74).isActive = true
        justificationCount.font = .systemFont(ofSize: 11)
        justificationGroup.addArrangedSubview(justificationCount)
        stack.addArrangedSubview(justificationGroup)
        justificationGroup.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        justificationLabel.widthAnchor.constraint(equalTo: justificationGroup.widthAnchor).isActive = true

        links.orientation = .vertical
        links.alignment = .leading
        links.spacing = 5
        stack.addArrangedSubview(links)
        links.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        changed.stringValue = "This download changed. Review the current warning before continuing."
        changed.isHidden = true
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        root.onPaletteChange = { [weak self, weak identity, weak title] palette in
            self?.fileName.textColor = palette.foregroundPrimary
            self?.source.textColor = palette.foregroundSecondary
            self?.warning.textColor = palette.foregroundPrimary
            self?.secondary.textColor = palette.foregroundSecondary
            self?.changed.textColor = palette.foregroundPrimary
            self?.passwordLabel.textColor = palette.foregroundPrimary
            self?.justificationLabel.textColor = palette.foregroundPrimary
            self?.justificationCount.textColor = palette.foregroundSecondary
            title?.textColor = palette.foregroundPrimary
            identity?.layer?.backgroundColor = palette.backgroundExtra.cgColor(in: palette.contentAppearance)
        }
        root.onPaletteChange?(root.palette)
        update(review)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(on parent: NSWindow) {
        guard let window, parent.attachedSheet == nil, !finished else { return }
        parentCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        parent.beginSheet(window) { [weak self] _ in self?.finish() }
    }

    func update(_ current: PCNativeDownloadReview) {
        guard !finished, current.identifier == review.identifier,
              current.profilePath == review.profilePath else { return }
        let resetPassword = current.needsPassword != review.needsPassword ||
            current.incorrectPassword != review.incorrectPassword || current.scanning != review.scanning
        let resetJustification = current.needsJustification != review.needsJustification ||
            current.warning != review.warning
        review = current
        if resetPassword || !current.needsPassword { password.stringValue = "" }
        if resetJustification || !current.needsJustification { justification.string = "" }
        passwordGroup.isHidden = !current.needsPassword
        passwordLabel.stringValue = current.passwordLabel
        password.setAccessibilityLabel(current.passwordLabel)
        passwordError.stringValue = current.incorrectPassword ? current.passwordError : ""
        passwordError.isHidden = passwordError.stringValue.isEmpty
        justificationGroup.isHidden = !current.needsJustification
        justificationLabel.stringValue = current.justificationLabel
        justification.setAccessibilityLabel(current.justificationLabel)
        progress.isHidden = !current.scanning
        if current.scanning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        links.arrangedSubviews.forEach { links.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, title) in current.linkTitles.enumerated() {
            let button = ActionButton(title) { [weak self] in self?.openLink(index) }
            button.isBordered = false
            button.contentTintColor = .linkColor
            button.alignment = .left
            button.cell?.wraps = true
            links.addArrangedSubview(button)
            button.widthAnchor.constraint(lessThanOrEqualTo: links.widthAnchor).isActive = true
        }
        links.isHidden = current.linkTitles.isEmpty
        fileName.stringValue = current.fileName
        source.stringValue = URL(string: current.sourceURL)?.host ?? current.sourceURL
        source.toolTip = current.sourceURL
        source.isHidden = source.stringValue.isEmpty
        warning.stringValue = current.warning
        secondary.stringValue = current.secondaryWarning
        secondary.isHidden = current.secondaryWarning.isEmpty
        footer.arrangedSubviews.forEach { footer.removeArrangedSubview($0); $0.removeFromSuperview() }
        let close = ActionButton("Not Now") { [weak self] in self?.dismiss() }
        close.keyEquivalent = "\u{1b}"
        close.contentTintColor = .labelColor
        footer.addArrangedSubview(close)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        decisionButtons.removeAll()
        for choice in current.buttons {
            let button = decisionButton(choice.title, action: choice.action)
            decisionButtons.append((choice.action, button))
            footer.addArrangedSubview(button)
        }
        let requiredButtonWidth = footer.arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.fittingSize.width } +
            CGFloat(max(0, footer.arrangedSubviews.count - 1)) * footer.spacing
        footer.orientation = requiredButtonWidth > 472 ? .vertical : .horizontal
        footer.alignment = footer.orientation == .vertical ? .trailing : .centerY
        updateInputState()
        root.layoutSubtreeIfNeeded()
        let availableHeight = (window?.sheetParent?.screen ?? window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        window?.setContentSize(NSSize(width: 520,
            height: min(availableHeight * 0.8, max(280, stack.fittingSize.height))))
        root.onLayout?()
    }

    private func decisionButton(_ title: String, action: PCNativeDownloadReviewAction) -> NSButton {
        let button = ActionButton(title) { [weak self] in self?.decide(action) }
        button.isBordered = true
        button.bezelStyle = .rounded
        button.contentTintColor = .labelColor
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func decide(_ action: PCNativeDownloadReviewAction) {
        guard !finished else { return }
        let displayed = review
        if action == .scan && displayed.needsPassword && password.stringValue.isEmpty {
            passwordError.stringValue = displayed.passwordEmptyError
            passwordError.isHidden = false
            window?.makeFirstResponder(password)
            NSAccessibility.post(element: passwordError, notification: .valueChanged)
            return
        }
        if onDecision?(displayed, action, action == .scan ? password.stringValue : "",
                       action == .keep ? justification.string : "") == true {
            password.stringValue = ""
            if action == .scan || action == .cancelScan {
                guard let current = onRefresh?() else { dismiss(); return }
                update(current)
            } else { dismiss() }
            return
        }
        guard let current = onRefresh?() else { dismiss(); return }
        changed.isHidden = false
        update(current)
        NSAccessibility.post(element: changed, notification: .valueChanged)
    }

    func controlTextDidChange(_ notification: Notification) { updateInputState() }
    func textDidChange(_ notification: Notification) { updateInputState() }

    private func updateInputState() {
        let count = justification.string.utf16.count
        justificationCount.stringValue = "\(count) / 280"
        justificationCount.textColor = count > 280 ? .systemRed : root.palette.foregroundSecondary
        for (action, button) in decisionButtons {
            button.isEnabled = action != .keep || !review.needsJustification || (count > 0 && count <= 280)
        }
    }

    private func openLink(_ index: Int) {
        guard !finished else { return }
        if onOpenLink?(review, index) == true { return }
        guard let current = onRefresh?() else { dismiss(); return }
        changed.isHidden = false
        update(current)
    }

    func dismiss() {
        guard !finished else { return }
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        window?.orderOut(nil)
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        password.stringValue = ""
        justification.string = ""
        progress.stopAnimation(nil)
        if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
        parentCloseObserver = nil
        let callback = onClose
        onClose = nil
        callback?()
    }
}
