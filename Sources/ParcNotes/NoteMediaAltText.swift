import AppKit
import ParcKit

@MainActor
final class NoteMediaAltBadge: NoteMediaControl {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            parcTooltip = text.isEmpty ? nil : TooltipConfiguration(text, anchor: .bottomLeading, maxWidth: 280)
            setAccessibilityValue(text)
        }
    }
    var isEditable = false {
        didSet {
            guard isEditable != oldValue else { return }
            isEnabled = isEditable
            setAccessibilityRole(isEditable ? .button : .staticText)
            setAccessibilityHelp(isEditable ? "Edit the alt text." : nil)
        }
    }
    private(set) var isRevealed = false
    private static let font = NoteTheme.nunitoExtraBold(10)

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        alphaValue = 0
        isEnabled = false
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Alt text")
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addCursorUpdateArea()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        let width = ceil(("ALT" as NSString).size(withAttributes: [.font: Self.font, .kern: 0.6]).width)
        return NSSize(width: width + 12, height: 18)
    }

    func setRevealed(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        if revealed { isHidden = false }
        NoteAnimation.fade(self, visible: revealed, duration: 0.12) { [weak self] in
            guard let self, !self.isRevealed else { return }
            self.isHidden = true
        }
        if ownsPointer(atWindowPoint: window?.mouseLocationOutsideOfEventStream ?? .zero) { window?.refreshCursorUnderPointer() }
    }

    override func resetCursorRects() {}

    override func cursorUpdate(with event: NSEvent) {
        if isRevealed, isEnabled, applyNoteCursor(.pointingHand, for: event) { return }
        if isRevealed { super.cursorUpdate(with: event) } else { nextResponder?.cursorUpdate(with: event) }
    }

    override func pressDidChange() {
        guard let layer else { return }
        NoteMediaMotion.press(layer, pressed: isPressed, in: self)
    }

    override func refresh() {
        NoteMediaMotion.instant {
            layer?.backgroundColor = NoteMediaStyle.cg(isHovered && isEnabled ? NoteTheme.menuInk : NoteTheme.menuFill, in: self)
            layer?.borderColor = NoteMediaStyle.cg(NoteTheme.menuHairline, in: self)
            layer?.shadowColor = NoteTheme.menuShadow.cgColor
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = isHovered && isEnabled ? NoteTheme.menuFill : NoteTheme.menuInk
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: ink, .kern: 0.6]
        let size = ("ALT" as NSString).size(withAttributes: attributes)
        ("ALT" as NSString).draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()),
                                 withAttributes: attributes)
    }
}

@MainActor
package final class NoteMediaAltTextEditor: NSView, NoteFloatingPanelContent {
    package var preferredSizeDidChange: (() -> Void)?
    package var onCommit: ((String) -> Void)?
    private let title: NSTextField
    private let field = NoteSearchField(placeholder: "Describe this image…")
    private let hint: NSTextField
    private var finished = false
    private static let width: CGFloat = 320
    private static let padding: CGFloat = 12

    package init(text: String) {
        title = NoteMediaStyle.label("Alt text", font: NoteTheme.chromeFont(13), color: NoteTheme.menuInk)
        hint = NoteMediaStyle.label("Screen readers read this aloud. Press Return to save.", font: NoteMediaStyle.smallFont,
                                    color: NoteTheme.menuTertiaryInk, lines: 2)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        field.showsIcon = false
        field.text = text
        field.textField.setAccessibilityLabel("Alt text")
        field.textField.setAccessibilityHelp("Describe the image for people who can't see it. Return saves, Escape cancels.")
        field.onSubmit = { [weak self] value in self?.commit(value) }
        for view in [title, field, hint] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Alt text")
        setFrameSize(intrinsicContentSize)
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }

    package override var intrinsicContentSize: NSSize {
        let hintHeight = ceil(hint.sizeThatFits(NSSize(width: Self.width - Self.padding * 2, height: 100)).height)
        return NSSize(width: Self.width, height: Self.padding + 18 + 8 + NoteTheme.fieldHeight + 8 + hintHeight + Self.padding)
    }

    package override var fittingSize: NSSize { intrinsicContentSize }

    package override func layout() {
        super.layout()
        let width = bounds.width - Self.padding * 2
        title.frame = NSRect(x: Self.padding, y: Self.padding, width: width, height: 18)
        field.frame = NSRect(x: Self.padding, y: title.frame.maxY + 8, width: width, height: NoteTheme.fieldHeight)
        let hintHeight = ceil(hint.sizeThatFits(NSSize(width: width, height: 100)).height)
        hint.frame = NSRect(x: Self.padding, y: field.frame.maxY + 8, width: width, height: hintHeight)
    }

    package func focus() {
        field.focus()
        field.textField.currentEditor()?.selectAll(nil)
    }

    package func cancel() {
        finished = true
    }

    package func commitIfPending() {
        guard !finished else { return }
        commit(field.text)
    }

    private func commit(_ value: String) {
        guard !finished else { return }
        finished = true
        onCommit?(value)
    }
}
