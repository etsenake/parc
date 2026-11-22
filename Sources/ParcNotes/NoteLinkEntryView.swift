import AppKit

@MainActor
package final class NoteLinkEntryView: NoteMediaContentHostlessCard, NSTextFieldDelegate {
    package enum Style { case bookmark, embed }

    package static let defaultHeight: CGFloat = 52
    package var onSubmit: ((URL) -> Void)?
    package var onTextChange: ((String) -> Void)?
    package var onCommand: ((Selector) -> Bool)?
    package var onUnrecognized: ((String) -> Bool)?
    package var onCancel: (() -> Void)?
    package var parseLink: (String) -> URL? = { NoteMediaSource.webURL(from: $0) }
    package var editable = true { didSet { applyMode() } }
    private let icon = NSImageView()
    private let field = NoteInputField()
    private let submit: NoteChip
    private let readOnlyLabel: NSTextField
    private let hint: NSTextField
    private let style: Style

    package init(style: Style) {
        self.style = style
        submit = NoteChip(style == .embed ? "Embed link" : "Create bookmark", icon: .symbol(style == .embed ? "rectangle.on.rectangle" : "bookmark"))
        readOnlyLabel = NoteMediaStyle.label(style == .embed ? "No embed here yet" : "No bookmark here yet",
                                             font: NoteMediaStyle.titleFont, color: NoteTheme.secondaryInk)
        hint = NoteMediaStyle.label("That doesn’t look like a link.", font: NoteMediaStyle.smallFont, color: NoteMediaStyle.warningInk)
        super.init(frame: .zero)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NoteTheme.tertiaryInk
        icon.image = NoteMediaStyle.symbol(style == .embed ? "rectangle.on.rectangle" : "bookmark", size: 16, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteTheme.nunitoRegular(14)
        field.textColor = NoteTheme.ink
        setPlaceholder(style == .embed ? "Paste a link to embed…" : "Paste a link to bookmark…")
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel(style == .embed ? "Link to embed" : "Link to bookmark")
        submit.onPress = { [weak self] in self?.submitLink() }
        hint.isHidden = true
        for view in [icon, field, submit, readOnlyLabel, hint] as [NSView] { addSubview(view) }
        applyMode()
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var height: CGFloat { Self.defaultHeight }

    package var text: String {
        get { field.stringValue }
        set {
            field.stringValue = newValue
            if !hint.isHidden { hint.isHidden = true; needsLayout = true }
        }
    }

    var isComposing: Bool { (field.currentEditor() as? NSTextView)?.hasMarkedText() == true }

    func setPlaceholder(_ text: String) {
        field.placeholderAttributedString = NSAttributedString(
            string: text, attributes: [.font: NoteTheme.nunitoRegular(14), .foregroundColor: NoteTheme.placeholderInk])
    }

    func setFieldLabel(_ text: String) { field.setAccessibilityLabel(text) }

    private func applyMode() {
        field.isHidden = !editable
        submit.isHidden = !editable
        readOnlyLabel.isHidden = editable
        needsLayout = true
    }

    package func beginEditing(selectingAll: Bool = false) -> Bool {
        guard editable, let window, window.makeFirstResponder(field) else { return false }
        if selectingAll { field.currentEditor()?.selectAll(nil) }
        return true
    }

    package func refuse(_ message: String = "That doesn’t look like a link.") {
        hint.stringValue = message
        hint.isHidden = false
        needsLayout = true
        if let layer = field.layer ?? { field.wantsLayer = true; return field.layer }(), !NoteAnimation.reduceMotion {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -6, 5, -3, 2, 0]
            shake.duration = 0.32
            layer.add(shake, forKey: "link.shake")
        }
    }

    private func submitLink() {
        guard let url = parseLink(field.stringValue) else {
            if onUnrecognized?(field.stringValue) == true { return }
            refuse()
            return
        }
        onSubmit?(url)
    }

    package func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if !textView.hasMarkedText(), onCommand?(commandSelector) == true { return true }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): submitLink(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            field.stringValue = ""
            hint.isHidden = true
            window?.makeFirstResponder(nil)
            onCancel?()
            return true
        default: return false
        }
    }

    package func controlTextDidChange(_ obj: Notification) {
        if !hint.isHidden { hint.isHidden = true; needsLayout = true }
        onTextChange?(field.stringValue)
    }

    package override func layout() {
        super.layout()
        let height = bounds.height
        icon.frame = NSRect(x: 16, y: (height - 18) / 2, width: 18, height: 18)
        let size = submit.intrinsicContentSize
        submit.frame = NSRect(x: bounds.width - 12 - size.width, y: (height - size.height) / 2, width: size.width, height: size.height)
        let hintWidth = hint.isHidden ? 0 : min(190, ceil(hint.intrinsicContentSize.width))
        let fieldWidth = max(40, submit.frame.minX - 8 - 44 - (hintWidth > 0 ? hintWidth + 8 : 0))
        field.frame = NSRect(x: 44, y: (height - 20) / 2, width: fieldWidth, height: 20)
        hint.frame = NSRect(x: field.frame.maxX + 8, y: (height - 16) / 2, width: hintWidth, height: 16)
        readOnlyLabel.frame = NSRect(x: 44, y: (height - 20) / 2, width: max(0, bounds.width - 56), height: 20)
    }

    package override func mouseDown(with event: NSEvent) {
        guard editable else { return }
        window?.makeFirstResponder(field)
    }
}

@MainActor
open class NoteMediaContentHostlessCard: NSView, Sendable {
    private let card = CALayer()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.cornerRadius = NoteMediaStyle.cardRadius
        card.cornerCurve = .continuous
        card.borderWidth = 1
        layer?.addSublayer(card)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    open override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            card.frame = bounds
            card.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}
