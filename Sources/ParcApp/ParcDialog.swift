import AppKit
import SwiftUI

@MainActor
final class ParcDialog: NSObject, NSTextFieldDelegate {
    enum Response: Equatable { case confirm, alwaysConfirm, secondary, auxiliary, cancel }

    struct Field {
        var value: String
        var placeholder: String
        var required = true
    }

    struct Content {
        var title: [(String, Bool)]
        var message: [(String, Bool)]?
        var icon: NSImage?
        var confirm: String
        var cancel: String?
        var suppression: String?
        var auxiliary: String?
        var secondary: String?
        var field: Field?
        var details: String?
        var width: CGFloat = 450
        var destructive = false
    }

    let panel: NSPanel
    let confirmButton: ParcDialogButton
    let cancelButton: ParcDialogButton?
    let auxiliaryButton: ParcDialogButton?
    let secondaryButton: ParcDialogButton?
    let suppression: ParcSelectionCheckbox?
    let textField: NSTextField?
    private let requiresText: Bool
    private weak var parent: NSWindow?
    private var completion: ((Response) -> Void)?
    private var response = Response.cancel

    init(_ content: Content) {
        panel = ParcDialogPanel(contentRect: NSRect(x: 0, y: 0, width: content.width, height: 160),
                               styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true; panel.titleVisibility = .hidden
        panel.isOpaque = false; panel.backgroundColor = ParcDialogStyle.popoverBackground
        panel.isReleasedWhenClosed = false
        confirmButton = ParcDialogButton(title: content.confirm, primary: true, destructive: content.destructive)
        cancelButton = content.cancel.map { ParcDialogButton(title: $0, primary: false) }
        auxiliaryButton = content.auxiliary.map { ParcDialogButton(title: $0, primary: false, hint: false) }
        secondaryButton = content.secondary.map { ParcDialogButton(title: $0, primary: false, hint: false) }
        suppression = content.suppression.map { ParcSelectionCheckbox(title: $0, labelAttributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: ParcDialogStyle.popoverMessage]) }
        textField = content.field.map { field in
            let text = NSTextField(string: field.value)
            text.placeholderString = field.placeholder
            text.isBordered = false; text.isBezeled = false; text.drawsBackground = false
            text.focusRingType = .none; text.font = .systemFont(ofSize: 14)
            text.textColor = ParcDialogStyle.popoverTitle
            text.usesSingleLineMode = true; text.lineBreakMode = .byTruncatingTail
            text.cell?.isScrollable = true; text.isEditable = true; text.isSelectable = true
            return text
        }
        requiresText = content.field?.required ?? false
        super.init()
        textField?.delegate = self
        (panel as? ParcDialogPanel)?.onCancel = { [weak self] in self?.escape() }
        (panel as? ParcDialogPanel)?.onConfirm = { [weak self] in self?.confirmButton.performClick(nil) }
        confirmButton.target = self; confirmButton.action = #selector(confirm(_:)); confirmButton.keyEquivalent = "\r"
        cancelButton?.target = self; cancelButton?.action = #selector(cancel(_:)); cancelButton?.keyEquivalent = "\u{1b}"
        auxiliaryButton?.target = self; auxiliaryButton?.action = #selector(auxiliary(_:))
        secondaryButton?.target = self; secondaryButton?.action = #selector(secondary(_:))

        let inset: CGFloat = 38, width = content.width - 2 * inset
        let root = ParcDialogBaseView(frame: .zero)
        var y = inset
        if let icon = content.icon {
            let picture = ParcDialogPictureIcon(image: icon)
            picture.setFrameOrigin(NSPoint(x: inset, y: y)); root.addSubview(picture)
            y += 62
        }
        let title = ParcDialogStyle.label(content.title, size: 18, weight: .medium, color: ParcDialogStyle.popoverTitle, lineSpacing: 4)
        root.addSubview(title)
        y += 17 + ParcDialogStyle.place(title, x: inset, y: y + 17, width: width) + 8
        if let message = content.message {
            let label = ParcDialogStyle.label(message, size: 14, weight: .regular, color: ParcDialogStyle.popoverMessage, lineSpacing: 1)
            root.addSubview(label)
            y += ParcDialogStyle.place(label, x: inset, y: y, width: width)
        }
        let accessoryGap: CGFloat = content.message != nil ? 16 : 8
        if let details = content.details {
            y += accessoryGap
            let card = ParcDialogFieldCard(frame: NSRect(x: inset, y: y, width: width, height: ParcDialogStyle.detailsHeight))
            let scroll = ParcDialogStyle.detailsView(details, size: card.bounds.insetBy(dx: 4, dy: 4).size)
            scroll.frame = card.bounds.insetBy(dx: 4, dy: 4); card.addSubview(scroll)
            root.addSubview(card)
            y += card.frame.height
        }
        if let textField {
            y += accessoryGap
            let card = ParcDialogFieldCard(frame: NSRect(x: inset, y: y, width: width, height: ParcDialogStyle.fieldHeight))
            let height = ceil(textField.intrinsicContentSize.height)
            textField.frame = NSRect(x: ParcDialogStyle.fieldPadding - 2, y: (card.frame.height - height) / 2,
                                     width: width - 2 * ParcDialogStyle.fieldPadding + 4, height: height)
            card.addSubview(textField); card.field = textField
            root.addSubview(card)
            y += card.frame.height
        }
        y += 22

        let buttons = [confirmButton] + [secondaryButton, cancelButton, auxiliaryButton].compactMap { $0 }
        var footerHeight: CGFloat = 36
        if let suppression {
            let buttonsX = content.width - 28 - buttons.map(\.bodyWidth).reduce(0, +) - CGFloat(buttons.count - 1) * 8
            let fitted = suppression.fittedSize(maxWidth: buttonsX - 8 - inset)
            footerHeight = max(footerHeight, fitted.height)
            suppression.frame = NSRect(x: inset, y: y + (footerHeight - fitted.height) / 2, width: fitted.width, height: fitted.height)
            root.addSubview(suppression)
        }
        var right = content.width - 28
        for button in buttons {
            button.frame = NSRect(x: right - button.bodyWidth - 0.5, y: y + (footerHeight - 36) / 2 - 0.5,
                                  width: button.bodyWidth + 1, height: 38.5)
            root.addSubview(button)
            right -= button.bodyWidth + 8
        }
        y += footerHeight + 28
        root.frame = NSRect(x: 0, y: 0, width: content.width, height: y)
        panel.contentView = root
        panel.setContentSize(NSSize(width: content.width, height: y))
        panel.initialFirstResponder = textField ?? confirmButton
        panel.setAccessibilityDefaultButton(confirmButton)
        panel.setAccessibilityLabel(content.title.map(\.0).joined())
        updateValidity()
    }

    private func updateValidity() {
        guard requiresText, let textField else { return }
        confirmButton.isEnabled = !textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === textField else { return }
        updateValidity()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === textField, !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if confirmButton.isEnabled { confirmButton.performClick(nil) }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { escape(); return true }
        return false
    }

    func begin(for window: NSWindow, queued: Bool = false, completion: @escaping (Response) -> Void) -> Bool {
        guard queued || window.attachedSheet == nil, parent == nil else { return false }
        parent = window; self.completion = completion
        window.beginSheet(panel) { [self] _ in
            let finished = self.completion; self.completion = nil
            finished?(self.response)
        }
        if let textField { panel.makeFirstResponder(textField); textField.currentEditor()?.selectAll(nil) }
        return true
    }

    func runModal() -> Response {
        guard parent == nil else { return .cancel }
        panel.center()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return response
    }

    @discardableResult
    static func inform(in window: NSWindow, _ content: Content, queued: Bool = false) -> Bool {
        ParcDialog(content).begin(for: window, queued: queued) { _ in }
    }

    static func present(_ error: Error) { _ = ParcDialog(.init(error: error)).runModal() }

    @discardableResult
    static func confirm(in window: NSWindow, title: String, message: String?, confirm: String,
                        cancel: String = "Cancel", destructive: Bool = false,
                        decided: @escaping (Bool) -> Void) -> Bool {
        var content = Content(title: [(title, false)], message: message.map { [($0, false)] }, icon: nil,
                              confirm: confirm, cancel: cancel)
        content.destructive = destructive
        let dialog = ParcDialog(content)
        guard dialog.begin(for: window, completion: { decided($0 == .confirm) }) else { decided(false); return false }
        return true
    }

    @objc private func confirm(_ sender: Any?) {
        guard confirmButton.isEnabled, (textField?.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        end(suppression?.state == .on ? .alwaysConfirm : .confirm)
    }
    @objc private func secondary(_ sender: Any?) { end(.secondary) }
    @objc private func auxiliary(_ sender: Any?) { end(.auxiliary) }
    @objc private func cancel(_ sender: Any?) { end(.cancel) }

    private func escape() {
        guard cancelButton != nil || (secondaryButton == nil && auxiliaryButton == nil) else { return }
        cancel(nil)
    }

    private func end(_ response: Response) {
        self.response = response
        if let parent { parent.endSheet(panel) } else if NSApp.modalWindow === panel { NSApp.stopModal() }
    }
}

extension ParcDialog.Content {
    init(title: String, message: String? = nil, confirm: String = "OK", cancel: String? = nil) {
        self.init(title: [(title, false)], message: message.map { [($0, false)] }, confirm: confirm, cancel: cancel)
    }

    init(error: Error, title: String? = nil) {
        self.init(title: title ?? error.localizedDescription, message: (error as NSError).localizedRecoverySuggestion)
    }
}

@MainActor
private final class ParcDialogPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if (firstResponder as? NSTextView)?.hasMarkedText() == true,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 76, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty { onConfirm?(); return }
        super.keyDown(with: event)
    }
}

@MainActor
enum ParcDialogStyle {
    static func color(_ light: UInt32, _ lightAlpha: CGFloat, _ dark: UInt32, _ darkAlpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
                           blue: CGFloat(rgb & 0xff) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }
    static let popoverBackground = color(0xFAFBFF, 1, 0x151C30, 1)
    static let popoverTitle = color(0x181B1F, 1, 0xFFFFFF, 1)
    static let popoverMessage = color(0x060E2B, 0.75, 0xEEEEF6, 0.75)
    static let popoverLogoShadow = color(0x000000, 0.15, 0xFFFFFF, 0)
    static let popoverArrowIcon = color(0x1E2E69, 0.3, 0xEEEEF6, 0.3)
    static let neutralFace = color(0xFFFFFF, 1, 0x302F63, 1)
    static let neutralHovered = color(0xF2F2F2, 1, 0x454473, 1)
    static let neutralPressed = color(0xE5E5E5, 1, 0x2B2A59, 1)
    static let neutralForeground = color(0x171717, 1, 0xFFFFFF, 0.9)
    static let neutralBorder = color(0xDBDBDB, 1, 0x6362AE, 1)
    static let neutralShadow = color(0xE2E2E2, 1, 0xFFFFFF, 0)
    static let neutralIconForeground = color(0x727272, 1, 0xD7D7FF, 0.77)
    static let neutralIconBackground = color(0x000000, 0.1, 0xC7C0D7, 0.2)
    static let primaryFace = color(0x3139FB, 1, 0x3139FB, 1)
    static let primaryHovered = color(0x2C33E2, 1, 0x2C33E2, 1)
    static let primaryPressed = color(0x2A30D5, 1, 0x2A30D5, 1)
    static let primaryForeground = color(0xFFFFFF, 1, 0xFFFFFF, 1)
    static let primaryBorder = color(0xFFFFFF, 0, 0xFFFFFF, 0.2)
    static let primaryShadow = color(0x3438B2, 1, 0x5A61FC, 0.5)
    static let primaryIconForeground = color(0xFFFFFF, 0.9, 0xFFFFFF, 0.9)
    static let primaryIconBackground = color(0xFFFFFF, 0.1, 0xFFFFFF, 0.1)
    static let primaryIconBorder = color(0xFFFFFF, 0.2, 0xFFFFFF, 0.2)
    static let destructiveFace = color(0xF53714, 1, 0xF53714, 1)
    static let destructiveHovered = color(0xDD3112, 1, 0xDD3112, 1)
    static let destructivePressed = color(0xD02F11, 1, 0xD02F11, 1)
    static let destructiveShadow = color(0xB4250A, 0.3, 0xB4250A, 0.3)
    static let indigo4 = color(0xE8E9FF, 1, 0x1C1D4F, 1)
    static let indigo6 = color(0xC8CAFA, 1, 0x22246E, 1)
    static let fieldFill = color(0x060E2B, 0.07, 0xEEEEF6, 0.10)
    static let fieldHeight: CGFloat = 36
    static let fieldPadding: CGFloat = 12
    static let detailsHeight: CGFloat = 128

    static func detailsView(_ text: String, size: NSSize) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let view = NSTextView(frame: scroll.bounds)
        view.string = text; view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.font = .systemFont(ofSize: 13); view.textColor = popoverTitle
        view.textContainerInset = NSSize(width: 8, height: 6)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.setAccessibilityLabel("Details")
        scroll.documentView = view
        return scroll
    }

    static let buttonFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static var hintFont: NSFont {
        let bold = NSFont.systemFont(ofSize: 11, weight: .bold)
        return bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11) } ?? bold
    }

    static func label(_ segments: [(String, Bool)], size: CGFloat, weight: NSFont.Weight, color: NSColor, lineSpacing: CGFloat) -> NSTextField {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = lineSpacing
        let text = NSMutableAttributedString()
        for (value, bold) in segments {
            text.append(NSAttributedString(string: value, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : weight),
                .foregroundColor: color, .paragraphStyle: paragraph]))
        }
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text; label.isSelectable = false
        return label
    }
    static func place(_ label: NSTextField, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let inset: CGFloat = 2
        label.preferredMaxLayoutWidth = width + 2 * inset
        let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width + 2 * inset, height: .greatestFiniteMagnitude)).height ?? 0)
        label.frame = NSRect(x: x - inset, y: y, width: width + 2 * inset, height: height)
        return height
    }

    static func continuousRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let r = min(radius, min(rect.width, rect.height) / 2 / 1.52866483)
        let x = rect.minX, y = rect.minY, X = rect.maxX, Y = rect.maxY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x + 1.52866483 * r, y: y))
        path.line(to: NSPoint(x: X - 1.52866483 * r, y: y))
        path.curve(to: NSPoint(x: X - 0.63149399 * r, y: y + 0.07491100 * r),
                   controlPoint1: NSPoint(x: X - 1.08849323 * r, y: y), controlPoint2: NSPoint(x: X - 0.86840689 * r, y: y))
        path.curve(to: NSPoint(x: X - 0.07491100 * r, y: y + 0.63149399 * r),
                   controlPoint1: NSPoint(x: X - 0.37282392 * r, y: y + 0.16905899 * r), controlPoint2: NSPoint(x: X - 0.16905899 * r, y: y + 0.37282392 * r))
        path.curve(to: NSPoint(x: X, y: y + 1.52866483 * r),
                   controlPoint1: NSPoint(x: X, y: y + 0.86840689 * r), controlPoint2: NSPoint(x: X, y: y + 1.08849323 * r))
        path.line(to: NSPoint(x: X, y: Y - 1.52866483 * r))
        path.curve(to: NSPoint(x: X - 0.07491100 * r, y: Y - 0.63149399 * r),
                   controlPoint1: NSPoint(x: X, y: Y - 1.08849323 * r), controlPoint2: NSPoint(x: X, y: Y - 0.86840689 * r))
        path.curve(to: NSPoint(x: X - 0.63149399 * r, y: Y - 0.07491100 * r),
                   controlPoint1: NSPoint(x: X - 0.16905899 * r, y: Y - 0.37282392 * r), controlPoint2: NSPoint(x: X - 0.37282392 * r, y: Y - 0.16905899 * r))
        path.curve(to: NSPoint(x: X - 1.52866483 * r, y: Y),
                   controlPoint1: NSPoint(x: X - 0.86840689 * r, y: Y), controlPoint2: NSPoint(x: X - 1.08849323 * r, y: Y))
        path.line(to: NSPoint(x: x + 1.52866483 * r, y: Y))
        path.curve(to: NSPoint(x: x + 0.63149399 * r, y: Y - 0.07491100 * r),
                   controlPoint1: NSPoint(x: x + 1.08849323 * r, y: Y), controlPoint2: NSPoint(x: x + 0.86840689 * r, y: Y))
        path.curve(to: NSPoint(x: x + 0.07491100 * r, y: Y - 0.63149399 * r),
                   controlPoint1: NSPoint(x: x + 0.37282392 * r, y: Y - 0.16905899 * r), controlPoint2: NSPoint(x: x + 0.16905899 * r, y: Y - 0.37282392 * r))
        path.curve(to: NSPoint(x: x, y: Y - 1.52866483 * r),
                   controlPoint1: NSPoint(x: x, y: Y - 0.86840689 * r), controlPoint2: NSPoint(x: x, y: Y - 1.08849323 * r))
        path.line(to: NSPoint(x: x, y: y + 1.52866483 * r))
        path.curve(to: NSPoint(x: x + 0.07491100 * r, y: y + 0.63149399 * r),
                   controlPoint1: NSPoint(x: x, y: y + 1.08849323 * r), controlPoint2: NSPoint(x: x, y: y + 0.86840689 * r))
        path.curve(to: NSPoint(x: x + 0.63149399 * r, y: y + 0.07491100 * r),
                   controlPoint1: NSPoint(x: x + 0.16905899 * r, y: y + 0.37282392 * r), controlPoint2: NSPoint(x: x + 0.37282392 * r, y: y + 0.16905899 * r))
        path.curve(to: NSPoint(x: x + 1.52866483 * r, y: y),
                   controlPoint1: NSPoint(x: x + 0.86840689 * r, y: y), controlPoint2: NSPoint(x: x + 1.08849323 * r, y: y))
        path.close()
        return path
    }
}

enum ParcSelectionMark {
    static let tint = NSColor(srgbRed: 49 / 255, green: 57 / 255, blue: 251 / 255, alpha: 1)
    static func symbolName(selected: Bool) -> String { selected ? "checkmark.circle.fill" : "circle" }
    static func accessibilityValue(selected: Bool) -> String { selected ? "Selected" : "Not selected" }
}

struct ParcSelectionMarkImage: View {
    let selected: Bool
    let color: NSColor
    var body: some View {
        Image(systemName: ParcSelectionMark.symbolName(selected: selected))
            .imageScale(.large).foregroundColor(Color(nsColor: color))
    }
}

@MainActor
final class ParcSelectionCheckbox: PointingHandButton {
    init(title: String, tint: NSColor = ParcSelectionMark.tint, labelAttributes: [NSAttributedString.Key: Any]) {
        super.init(frame: .zero)
        setButtonType(.switch); isBordered = false; imagePosition = .imageLeading
        image = Self.symbol(selected: false); alternateImage = Self.symbol(selected: true)
        contentTintColor = tint
        attributedTitle = NSAttributedString(string: title, attributes: labelAttributes)
        cell?.wraps = true; cell?.lineBreakMode = .byWordWrapping
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func symbol(selected: Bool) -> NSImage? {
        NSImage(systemSymbolName: ParcSelectionMark.symbolName(selected: selected), accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(scale: .large))
    }
    func fittedSize(maxWidth: CGFloat) -> NSSize {
        let size = cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude)) ?? .zero
        return NSSize(width: min(ceil(size.width), maxWidth), height: ceil(size.height))
    }
    override func accessibilityValue() -> Any? { ParcSelectionMark.accessibilityValue(selected: state == .on) }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        NSAccessibility.post(element: self, notification: .valueChanged)
        return super.sendAction(action, to: target)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            if !event.isARepeat { performClick(nil) }
        } else {
            nextResponder?.keyDown(with: event)
        }
    }
}

@MainActor
private final class ParcDialogFieldCard: NSView {
    weak var field: NSTextField?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        ParcDialogStyle.fieldFill.setFill()
        ParcDialogStyle.continuousRect(bounds, radius: 8).fill()
    }
    override func mouseDown(with event: NSEvent) {
        if let field { window?.makeFirstResponder(field) } else { super.mouseDown(with: event) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
private final class ParcDialogBaseView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { ParcDialogStyle.popoverBackground.setFill(); dirtyRect.fill() }
}

@MainActor
private final class ParcDialogPictureIcon: NSView {
    private let image: NSImage
    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(x: 0, y: 0, width: 62, height: 62))
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(52.5 / image.size.width, 45.5 / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = ParcDialogStyle.popoverLogoShadow; shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        image.draw(in: NSRect(x: 31.5 - size.width / 2, y: 31.5 - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
final class ParcDialogButton: PointingHandButton {
    let primary: Bool
    let destructive: Bool
    let hint: Bool
    var isLoading = false {
        didSet {
            guard isLoading != oldValue else { return }
            if isLoading, spinner == nil {
                let host = NSHostingView(rootView: ParcButtonSpinner()); host.setAccessibilityElement(false)
                if primary { host.appearance = NSAppearance(named: .darkAqua) }
                host.frame = body; host.autoresizingMask = [.width, .height]
                addSubview(host); spinner = host
            }
            spinner?.isHidden = !isLoading
            setAccessibilityValue(isLoading ? "Loading" : nil)
            needsLayout = true; needsDisplay = true
        }
    }
    private var spinner: NSHostingView<ParcButtonSpinner>?
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(title: String, primary: Bool, destructive: Bool = false, hint: Bool = true) {
        self.primary = primary; self.destructive = primary && destructive; self.hint = hint
        super.init(frame: .zero)
        self.title = title; isBordered = false; setButtonType(.momentaryPushIn); font = ParcDialogStyle.buttonFont
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }

    private var hintSymbol: NSImage? { primary ? NSImage(systemSymbolName: "return", accessibilityDescription: nil) : nil }
    private func hintImage(_ color: NSColor?) -> NSImage? {
        var configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        if let color { configuration = configuration.applying(.init(paletteColors: [color])) }
        return hintSymbol?.withSymbolConfiguration(configuration)
    }
    private var hintContentSize: NSSize {
        hintImage(nil)?.size ?? ("ESC" as NSString).size(withAttributes: [.font: ParcDialogStyle.hintFont])
    }
    private var hintSize: NSSize { NSSize(width: hintContentSize.width + 12, height: hintContentSize.height + 6) }
    var bodyWidth: CGFloat {
        12 + (title as NSString).size(withAttributes: [.font: ParcDialogStyle.buttonFont]).width + (hint ? 8 + hintSize.width : 0) + 12
    }
    private var body: NSRect { NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: 36) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var focusRingMaskBounds: NSRect { body }
    override func drawFocusRingMask() { ParcDialogStyle.continuousRect(body, radius: 6).fill() }
    override func layout() {
        super.layout()
        spinner?.frame = body
    }
    override func isAccessibilityEnabled() -> Bool { super.isAccessibilityEnabled() && !isLoading }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        isLoading ? false : super.sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true && !isLoading
        let hovered = self.hovered && !isLoading, isEnabled = self.isEnabled || isLoading
        let face: NSColor, foreground: NSColor, border: NSColor?, lip: NSColor
        let hintForeground: NSColor, hintBackground: NSColor, hintBorder: NSColor?
        if !primary {
            face = pressed ? ParcDialogStyle.neutralPressed : hovered ? ParcDialogStyle.neutralHovered : ParcDialogStyle.neutralFace
            foreground = isEnabled ? ParcDialogStyle.neutralForeground : ParcDialogStyle.popoverArrowIcon
            border = ParcDialogStyle.neutralBorder; lip = ParcDialogStyle.neutralShadow
            hintForeground = ParcDialogStyle.neutralIconForeground; hintBackground = ParcDialogStyle.neutralIconBackground; hintBorder = nil
        } else if isEnabled && destructive {
            face = pressed ? ParcDialogStyle.destructivePressed : hovered ? ParcDialogStyle.destructiveHovered : ParcDialogStyle.destructiveFace
            foreground = ParcDialogStyle.primaryForeground; border = nil; lip = ParcDialogStyle.destructiveShadow
            hintForeground = ParcDialogStyle.primaryIconForeground; hintBackground = ParcDialogStyle.primaryIconBackground
            hintBorder = ParcDialogStyle.primaryIconBorder
        } else if isEnabled {
            face = pressed ? ParcDialogStyle.primaryPressed : hovered ? ParcDialogStyle.primaryHovered : ParcDialogStyle.primaryFace
            foreground = ParcDialogStyle.primaryForeground; border = ParcDialogStyle.primaryBorder; lip = ParcDialogStyle.primaryShadow
            hintForeground = ParcDialogStyle.primaryIconForeground; hintBackground = ParcDialogStyle.primaryIconBackground
            hintBorder = ParcDialogStyle.primaryIconBorder
        } else {
            face = ParcDialogStyle.indigo4; foreground = ParcDialogStyle.popoverArrowIcon; border = nil; lip = ParcDialogStyle.indigo6
            hintForeground = ParcDialogStyle.popoverArrowIcon; hintBackground = ParcDialogStyle.indigo6; hintBorder = nil
        }
        lip.setFill(); ParcDialogStyle.continuousRect(body.offsetBy(dx: 0, dy: 2), radius: 6).fill()
        let shape = ParcDialogStyle.continuousRect(body, radius: 6)
        face.setFill(); shape.fill()
        if let border { border.setStroke(); shape.lineWidth = 1; shape.stroke() }
        guard !isLoading else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: ParcDialogStyle.buttonFont, .foregroundColor: foreground]
        let label = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: body.minX + 12, y: body.midY - label.height / 2), withAttributes: attributes)
        guard self.hint else { return }
        let hint = hintSize
        let badge = NSRect(x: body.maxX - 12 - hint.width, y: body.midY - hint.height / 2, width: hint.width, height: hint.height)
        let badgeShape = ParcDialogStyle.continuousRect(badge, radius: 4)
        hintBackground.setFill(); badgeShape.fill()
        if let hintBorder { hintBorder.setStroke(); badgeShape.lineWidth = 2; badgeShape.stroke() }
        let content = hintContentSize
        let contentRect = NSRect(x: badge.midX - content.width / 2, y: badge.midY - content.height / 2, width: content.width, height: content.height)
        if let symbol = hintImage(hintForeground) {
            symbol.draw(in: contentRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            ("ESC" as NSString).draw(at: contentRect.origin, withAttributes: [.font: ParcDialogStyle.hintFont, .foregroundColor: hintForeground])
        }
    }
}
