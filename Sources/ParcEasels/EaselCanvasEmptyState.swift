import AppKit
import ParcCore
import ParcNotes

enum EaselEmptyStateAction: Equatable {
    case tool(EaselTool)
    case findAnything
}

@MainActor
struct EaselEmptyStateRow {
    let title: String
    let view: NSView
    let inset: CGFloat
    let fit: (_ width: CGFloat, _ height: CGFloat) -> NSSize
}

struct EaselEmptyStateHint: Equatable {
    let title: String
    let keys: [String]
    let help: String
    let name: String
    let shortcut: String?
    let action: EaselEmptyStateAction

    static var all: [EaselEmptyStateHint] {
        func key(_ tool: EaselTool) -> String { tool.key?.label ?? "" }
        func hint(_ title: String, _ tools: [EaselTool], _ help: String) -> EaselEmptyStateHint {
            let keys = tools.map(key).filter { !$0.isEmpty }
            return EaselEmptyStateHint(title: title, keys: keys, help: help + (keys.isEmpty ? "" : " (" + keys.joined(separator: " or ") + ")"),
                                       name: help, shortcut: keys.first, action: .tool(tools[0]))
        }
        return [
            hint("Sticky", [.sticky], "Sticky note"),
            hint("Shape", [.rectangle, .ellipse], "Rectangle or ellipse"),
            hint("Connector", [.elbowConnector], "Connector"),
            hint("Text", [.text], "Text"),
            hint("Draw", [.marker], "Marker"),
            EaselEmptyStateHint(title: "Find anything", keys: ["⌘", "/"], help: "Find any tool or command (⌘/)",
                                name: "Find any tool or command", shortcut: "⌘/", action: .findAnything),
        ]
    }
}

@MainActor
final class EaselCanvasEmptyStateView: NSView {
    static let leading: CGFloat = 24
    static let origin = NSPoint(x: 40 - leading, y: 50)
    static let textWidth: CGFloat = 560
    static let maximumWidth: CGFloat = 680
    private static let titleFont = NoteTheme.nunitoExtraBold(28)
    private static let bodyFont = NoteTheme.nunitoRegular(15)
    private static let headingFont = NoteTheme.nunitoBold(13)
    private static let title = "A place for your ideas"
    private static let body = "Press a key, then click to drop it in. Everything saves right here on your Mac."
    private static let bodyTop: CGFloat = 46
    private static let chipHeight: CGFloat = 28
    private static let chipGap: CGFloat = 6
    private static let sectionGap: CGFloat = 26
    private static let headingHeight: CGFloat = 18

    var onAction: ((EaselEmptyStateAction) -> Void)?
    var showsFindAnything = true { didSet { if showsFindAnything != oldValue { rebuild() } } }
    var row: EaselEmptyStateRow? {
        didSet {
            guard row?.view !== oldValue?.view else { return }
            oldValue?.view.removeFromSuperview()
            if let view = row?.view { addSubview(view) }
            laidOutWidth = 0
            needsLayout = true; needsDisplay = true
        }
    }
    var availableHeight: CGFloat = .greatestFiniteMagnitude {
        didSet { if availableHeight != oldValue { laidOutWidth = 0; needsLayout = true } }
    }
    private(set) var isPresented = true
    private var chips: [EaselEmptyStateChip] = []
    private var laidOutWidth: CGFloat = 0
    private var headingTop: CGFloat?
    private var contentHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Empty Easel. " + Self.body)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPresented, !isHidden else { return nil }
        let local = convert(point, from: superview)
        if let chip = chips.first(where: { $0.frame.contains(local) }) { return chip }
        if let view = row?.view, !view.isHidden, view.frame.contains(local), let hit = view.hitTest(local), hit !== view { return hit }
        return nil
    }

    private func rebuild() {
        chips.forEach { $0.removeFromSuperview() }
        let hints = EaselEmptyStateHint.all.filter { showsFindAnything || $0.action != .findAnything }
        chips = hints.map { hint in
            let chip = EaselEmptyStateChip(hint: hint)
            chip.onPress = { [weak self] in self?.onAction?(hint.action) }
            addSubview(chip)
            return chip
        }
        laidOutWidth = 0
        needsLayout = true
    }

    func fittedHeight(width: CGFloat) -> CGFloat {
        arrange(width: width)
        return contentHeight
    }

    static func frameWidth(content width: CGFloat) -> CGFloat { width + leading * 2 }

    private func textWidth(_ width: CGFloat) -> CGFloat { min(Self.textWidth, width) }

    private func arrange(width: CGFloat) {
        guard width != laidOutWidth else { return }
        laidOutWidth = width
        let text = textWidth(width), lead = Self.leading
        var x: CGFloat = 0, y = Self.bodyTop + bodyHeight(width: text) + 14
        for chip in chips {
            let size = chip.fittingWidth
            if x > 0, x + size > text { x = 0; y += Self.chipHeight + Self.chipGap }
            chip.frame = NSRect(x: lead + x, y: y, width: size, height: Self.chipHeight)
            x += size + Self.chipGap
        }
        var bottom = (chips.map(\.frame.maxY).max() ?? Self.bodyTop + bodyHeight(width: text))
        headingTop = nil
        if let row {
            let top = bottom + Self.sectionGap
            let rowTop = top + Self.headingHeight + 4 - row.inset
            let size = row.fit(width + row.inset * 2, availableHeight - rowTop)
            if size.height > 0 {
                headingTop = top
                let next = NSRect(x: lead - row.inset, y: rowTop, width: size.width, height: size.height)
                if row.view.frame != next { row.view.frame = next }
                row.view.isHidden = false
                bottom = next.maxY
            } else {
                row.view.isHidden = true
            }
        }
        contentHeight = bottom + 4
        needsDisplay = true
    }

    private func bodyHeight(width: CGFloat) -> CGFloat {
        let bounds = (Self.body as NSString).boundingRect(with: NSSize(width: width, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: Self.bodyFont])
        return ceil(bounds.height)
    }

    override func layout() {
        super.layout()
        arrange(width: bounds.width - Self.leading * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let text = textWidth(bounds.width - Self.leading * 2), lead = Self.leading
        (Self.title as NSString).draw(at: NSPoint(x: lead, y: 0), withAttributes: [.font: Self.titleFont, .foregroundColor: NoteTheme.titlePlaceholderInk])
        (Self.body as NSString).draw(with: NSRect(x: lead, y: Self.bodyTop, width: text, height: bodyHeight(width: text) + 4),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.bodyFont, .foregroundColor: NoteTheme.placeholderInk])
        if let row, let top = headingTop {
            (row.title as NSString).draw(at: NSPoint(x: lead, y: top), withAttributes: [.font: Self.headingFont, .foregroundColor: NoteTheme.secondaryInk])
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        chips.forEach { $0.needsDisplay = true }
    }

    func setPresented(_ presented: Bool, animated: Bool) {
        guard presented != isPresented else { return }
        isPresented = presented
        setAccessibilityElement(presented)
        if presented { isHidden = false }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration: TimeInterval = animated ? (reduced ? 0.15 : (presented ? 0.2 : 0.15)) : 0
        if presented, animated, !reduced, let layer {
            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: NSPoint(x: 0, y: 4)); rise.toValue = NSValue(point: .zero)
            rise.isAdditive = true; rise.duration = duration
            rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(rise, forKey: "parc.easel.empty.rise")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = duration > 0
            animator().alphaValue = presented ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPresented else { return }
                self.isHidden = true
            }
        }
        NSAccessibility.post(element: superview ?? self, notification: .layoutChanged)
    }
}

@MainActor
final class EaselEmptyStateChip: NSView {
    private static let font = NoteTheme.chromeFont(13)
    private static let keyFont = NoteTheme.nunitoBold(11)
    private static let padding: CGFloat = 8
    private static let keySide = NoteTheme.keycapSide
    let hint: EaselEmptyStateHint
    var onPress: (() -> Void)?
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }

    init(hint: EaselEmptyStateHint) {
        self.hint = hint
        super.init(frame: .zero)
        setEaselTooltip(hint.name, shortcut: hint.shortcut)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(hint.title)
        setAccessibilityHelp(hint.help)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var keysWidth: CGFloat {
        hint.keys.isEmpty ? 0 : hint.keys.map { keyWidth($0) }.reduce(0, +) + CGFloat(hint.keys.count - 1) * 3 + 7
    }

    private func keyWidth(_ key: String) -> CGFloat {
        max(Self.keySide, ceil((key as NSString).size(withAttributes: [.font: Self.keyFont]).width) + 10)
    }

    var fittingWidth: CGFloat {
        let label = ceil((hint.title as NSString).size(withAttributes: [.font: Self.font]).width)
        return Self.padding * 2 + label + keysWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        if pressed { NoteTheme.pressedFill.setFill(); shape.fill() } else if hovered { NoteTheme.hoverFill.setFill(); shape.fill() }
        var x = Self.padding
        for key in hint.keys {
            let width = keyWidth(key)
            let base = NSRect(x: x, y: (bounds.height - Self.keySide) / 2, width: width, height: Self.keySide)
            NoteTheme.keycapBase.setFill(); NSBezierPath(roundedRect: base, xRadius: 5, yRadius: 5).fill()
            let face = NSRect(x: base.minX + 1, y: base.minY + 1, width: base.width - 2, height: base.height - 3)
            NoteTheme.keycapFace.setFill(); NSBezierPath(roundedRect: face, xRadius: 4, yRadius: 4).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.keyFont, .foregroundColor: NoteTheme.keycapInk]
            let size = (key as NSString).size(withAttributes: attributes)
            (key as NSString).draw(at: NSPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2), withAttributes: attributes)
            x += width + 3
        }
        if !hint.keys.isEmpty { x += 4 }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NoteTheme.secondaryInk]
        let size = (hint.title as NSString).size(withAttributes: attributes)
        (hint.title as NSString).draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseDragged(with event: NSEvent) {
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
