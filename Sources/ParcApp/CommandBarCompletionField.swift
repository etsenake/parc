import AppKit

final class CommandBarInputField: NSTextField {
    private let fade: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()
    private var fadeWidth: CGFloat = 0
    private var fades = false

    func setTrailingFade(_ shows: Bool, width: CGFloat) {
        guard shows != fades || width != fadeWidth else { return }
        fades = shows; fadeWidth = width
        applyFade()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if fades { applyFade() }
    }

    private func applyFade() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard fades, fadeWidth > 0, bounds.width > 0 else {
            if layer.mask === fade { layer.mask = nil }
            return
        }
        fade.frame = bounds
        fade.locations = CommandBarFieldAnchor.fadeLocations(width: bounds.width, fade: fadeWidth).map { NSNumber(value: $0) }
        if layer.mask !== fade { layer.mask = fade }
    }
}

final class CommandBarCompletionTitleLabel: NSTextField {
    var spokenTitle = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityValue() -> String? { spokenTitle }

    static func make() -> CommandBarCompletionTitleLabel {
        let label = CommandBarCompletionTitleLabel(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true
        label.baseWritingDirection = .leftToRight
        label.textColor = CommandBarPalette.textSecondary
        label.isHidden = true
        label.setAccessibilityRole(.staticText)
        label.setAccessibilityHelp("Title of the page the address completes to")
        return label
    }
}

private final class CommandBarClipObservation {
    private let tokens: [NSObjectProtocol]
    init(_ tokens: [NSObjectProtocol]) { self.tokens = tokens }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

class CommandBarAnchoredEditor: NSTextView {
    var anchorsScroll: (() -> Bool)?
    var onClipChange: ((Bool) -> Void)?
    var onUserScroll: (() -> Void)?
    private var clipObservation: CommandBarClipObservation?
    private var revealing = false

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaX != 0 { onUserScroll?() }
        super.scrollWheel(with: event)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(scrollToEndOfDocument(_:)) || selector == #selector(scrollToBeginningOfDocument(_:)) {
            onUserScroll?()
        }
        super.doCommand(by: selector)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        if revealing || anchorsScroll?() != true { super.scrollRangeToVisible(range) }
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        if !revealing, anchorsScroll?() == true { return true }
        return super.scrollToVisible(rect)
    }

    func reveal(_ range: NSRange) {
        revealing = true
        defer { revealing = false }
        scroll(NSPoint(x: 0, y: visibleRect.minY))
        super.scrollRangeToVisible(range)
    }

    var textEnd: CGFloat? {
        guard let storage = textStorage, storage.length <= CommandBarFieldAnchor.measuredLength else { return nil }
        return textContainerOrigin.x + trailingPadding + storage.size().width
    }

    var trailingPadding: CGFloat { textContainer?.lineFragmentPadding ?? 0 }

    var visibleEnd: CGFloat {
        (superview as? NSClipView).map { convert($0.bounds, from: $0).maxX } ?? visibleRect.maxX
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        clipObservation = nil
        if let clip = superview as? NSClipView {
            clip.postsBoundsChangedNotifications = true
            clip.postsFrameChangedNotifications = true
            clipObservation = CommandBarClipObservation(
                [(NSView.boundsDidChangeNotification, false), (NSView.frameDidChangeNotification, true)].map { name, resized in
                    NotificationCenter.default.addObserver(forName: name, object: clip, queue: nil) { [weak self] _ in
                        MainActor.assumeIsolated { self?.onClipChange?(resized) }
                    }
                })
        }
        onClipChange?(true)
    }
}
