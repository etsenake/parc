import AppKit
import ParcCore

@MainActor
final class NoteCreditLabel: NSView {
    var parts: [NoteMediaCredit.Part] = [] { didSet { if parts != oldValue { contentDidChange() } } }
    var font: NSFont = NoteMediaStyle.smallFont { didSet { contentDidChange() } }
    var linkFont: NSFont? { didSet { contentDidChange() } }
    var ink: NSColor = NoteTheme.tertiaryInk { didSet { needsDisplay = true } }
    var linkInk: NSColor = NoteTheme.secondaryInk { didSet { needsDisplay = true } }
    var onOpen: ((URL) -> Void)?
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressed: Int?
    private var tracking: NSTrackingArea?
    private var linkElements: [NoteCreditLinkElement]?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    convenience init(credit: NoteMediaCredit) {
        self.init(frame: .zero)
        parts = credit.parts
        contentDidChange()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var sentence: String {
        parts.map { part in
            switch part {
            case .text(let text): return text
            case .link(let text, _): return text
            }
        }.joined()
    }

    private var lineHeight: CGFloat {
        let tallest = [font, linkFont ?? font].map { $0.ascender - $0.descender + $0.leading }.max() ?? 0
        return ceil(tallest)
    }

    private func face(for part: NoteMediaCredit.Part) -> NSFont {
        if case .link = part { return linkFont ?? font }
        return font
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(attributed(hovered: nil).size().width) + 1, height: lineHeight + 2)
    }

    private func contentDidChange() {
        hovered = nil
        pressed = nil
        linkElements = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        setAccessibilityLabel(sentence)
    }

    private func attributed(hovered: Int?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            switch part {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]))
            case .link(let text, _):
                var attributes: [NSAttributedString.Key: Any] = [.font: face(for: part), .foregroundColor: linkInk, .paragraphStyle: paragraph]
                if index == hovered { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                result.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        return result
    }

    struct LinkSpan {
        var index: Int
        var rect: NSRect
        var url: URL
        var title: String
    }

    func linkSpans() -> [LinkSpan] {
        var x: CGFloat = 0
        var spans: [LinkSpan] = []
        let top = max(0, (bounds.height - lineHeight) / 2)
        for (index, part) in parts.enumerated() {
            let text: String
            var url: URL?
            switch part {
            case .text(let value): text = value
            case .link(let value, let target): text = value; url = target
            }
            let width = NSAttributedString(string: text, attributes: [.font: face(for: part)]).size().width
            if let url {
                let rect = NSRect(x: x, y: top, width: width, height: lineHeight).intersection(bounds)
                if !rect.isEmpty { spans.append(LinkSpan(index: index, rect: rect.integral, url: url, title: text)) }
            }
            x += width
        }
        return spans
    }

    private func span(at point: NSPoint) -> LinkSpan? {
        linkSpans().first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }
    }

    override func layout() {
        super.layout()
        linkElements = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let rect = NSRect(x: 0, y: max(0, (bounds.height - lineHeight) / 2), width: bounds.width, height: lineHeight)
            attributed(hovered: hovered).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, !isHidden, alphaValue > 0.01 else { return nil }
        return span(at: convert(point, from: superview)) == nil ? nil : self
    }

    override func resetCursorRects() {
        for span in linkSpans() { addCursorRect(span.rect, cursor: .pointingHand) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { hovered = span(at: convert(event.locationInWindow, from: nil))?.index }
    override func mouseEntered(with event: NSEvent) { hovered = span(at: convert(event.locationInWindow, from: nil))?.index }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        pressed = span(at: convert(event.locationInWindow, from: nil))?.index
        if pressed == nil { super.mouseDown(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let pressed, let span = span(at: convert(event.locationInWindow, from: nil)), span.index == pressed else { return }
        onOpen?(span.url)
    }

    fileprivate func open(_ url: URL) {
        onOpen?(url)
    }

    override func accessibilityChildren() -> [Any]? {
        if let linkElements { return linkElements }
        let elements = linkSpans().map { NoteCreditLinkElement(label: self, span: $0) }
        linkElements = elements
        return elements
    }
}

@MainActor
final class NoteCreditLinkElement: NSAccessibilityElement {
    private weak var label: NoteCreditLabel?
    private let span: NoteCreditLabel.LinkSpan

    init(label: NoteCreditLabel, span: NoteCreditLabel.LinkSpan) {
        self.label = label
        self.span = span
        super.init()
        setAccessibilityRole(.link)
        setAccessibilityLabel(span.title)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityParent() -> Any? { label }

    override func accessibilityFrame() -> NSRect {
        guard let label, let window = label.window else { return .zero }
        return window.convertToScreen(label.convert(span.rect, to: nil))
    }

    override func accessibilityPerformPress() -> Bool {
        guard let label else { return false }
        label.open(span.url)
        return true
    }
}
