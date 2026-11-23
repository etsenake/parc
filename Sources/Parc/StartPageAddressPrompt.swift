import AppKit
import ParcCore
import ParcKit

@MainActor
final class StartPageAddressPrompt: NSView {
    static let title = "Search or Enter URL…"
    static let accessibilityTitle = "Search or Enter URL"
    static let cornerRadius: CGFloat = 12
    static let inset: CGFloat = 22

    var onActivate: (() -> Void)?
    private let label = NSTextField(labelWithString: StartPageAddressPrompt.title)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .placeholderTextColor
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.accessibilityTitle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.05)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: Self.inset, y: ((bounds.height - height) / 2).rounded(),
                             width: max(0, bounds.width - 2 * Self.inset), height: height)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }

    override func mouseDown(with event: NSEvent) { onActivate?() }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\r", " ": onActivate?()
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return onActivate != nil
    }
}
