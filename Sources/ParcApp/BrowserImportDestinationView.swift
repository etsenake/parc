import AppKit

/// The chooser's native editor is retained across model publications so IME,
/// selection and focus stay with the original new-Profile field.
@MainActor
final class BrowserImportDestinationView: NSView, NSTextFieldDelegate {
    struct Profile: Equatable {
        let target: BrowserImportProfileTarget
        let title: String
    }
    var onSelect: ((BrowserImportDestinationChoice.Option) -> Void)?
    var onNameChange: ((String) -> Void)?
    var onToggleCookies: (() -> Void)?
    private var profiles: [Profile] = []
    private var buttons: [ImportProfileButton] = []
    private let newButton = ImportProfileButton("Create a New Profile")
    private let name = NSTextField()
    private let help = NSTextField(wrappingLabelWithString: "A new Profile will keep your existing data separate from what you’re importing.")
    private let cookies = NSButton(checkboxWithTitle: "Replace existing cookies with imported cookies", target: nil, action: nil)
    private let cookieHelp = NSTextField(labelWithString: "Recommended if you haven’t visited many websites in Parc yet")
    private let error = NSTextField(wrappingLabelWithString: "")
    private var selectedNew = false
    private var showsCookieReplacement = true
    override var isFlipped: Bool { true }
    var desiredHeight: CGFloat { CGFloat(profiles.count) * 62 + (error.isHidden ? 162 : 194) - (showsCookieReplacement ? 0 : 62) }
    var hasMarkedText: Bool { (name.currentEditor() as? NSTextView)?.hasMarkedText() == true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        name.placeholderString = "Personal"; name.font = .systemFont(ofSize: 14)
        name.textColor = PArcDialogStyle.popoverTitle; name.drawsBackground = false
        name.isBezeled = false; name.focusRingType = .default; name.delegate = self
        name.setAccessibilityLabel("New Profile name")
        help.font = .systemFont(ofSize: 13); help.textColor = PArcDialogStyle.popoverMessage
        cookieHelp.font = .systemFont(ofSize: 12); cookieHelp.textColor = PArcDialogStyle.popoverMessage
        cookies.font = .systemFont(ofSize: 13, weight: .medium)
        cookies.target = self; cookies.action = #selector(toggleCookies)
        error.font = .systemFont(ofSize: 12); error.textColor = .systemRed
        newButton.activate = { [weak self] in
            guard let self else { return }
            self.onSelect?(.new)
            self.window?.makeFirstResponder(self.name)
        }
        [newButton, help, name, cookies, cookieHelp, error].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(profiles: [Profile], choice: BrowserImportDestinationChoice, error: String?, showsCookieReplacement: Bool = true) {
        self.showsCookieReplacement = showsCookieReplacement
        cookies.isHidden = !showsCookieReplacement; cookieHelp.isHidden = !showsCookieReplacement
        if profiles != self.profiles {
            self.profiles = profiles
            buttons.forEach { $0.removeFromSuperview() }
            buttons = profiles.map { profile in
                let button = ImportProfileButton(profile.title)
                button.activate = { [weak self] in self?.onSelect?(.existing(profile.target)) }
                addSubview(button); return button
            }
        }
        func select(_ button: ImportProfileButton, _ on: Bool) {
            let state: NSControl.StateValue = on ? .on : .off
            guard button.state != state else { return }
            button.state = state; button.needsDisplay = true
            NSAccessibility.post(element: button, notification: .valueChanged)
        }
        for (button, profile) in zip(buttons, profiles) { select(button, choice.option == .existing(profile.target)) }
        selectedNew = choice.isNew
        select(newButton, selectedNew)
        newButton.title = selectedNew ? "New Profile:" : "Create a New Profile"
        newButton.needsDisplay = true
        name.isHidden = !selectedNew; help.isHidden = selectedNew
        if !hasMarkedText && name.stringValue != choice.newProfileName { name.stringValue = choice.newProfileName }
        cookies.state = choice.replaceExistingCookies ? .on : .off
        cookies.isEnabled = showsCookieReplacement && !selectedNew
        cookieHelp.alphaValue = selectedNew ? 0.5 : 1
        self.error.stringValue = error ?? ""; self.error.isHidden = error == nil
        needsLayout = true; needsDisplay = true
    }

    override func layout() {
        super.layout()
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 0, y: CGFloat(index) * 62, width: bounds.width, height: 54)
        }
        let y = CGFloat(buttons.count) * 62
        newButton.frame = NSRect(x: 0, y: y, width: bounds.width, height: 78)
        name.frame = NSRect(x: 178, y: y + 28, width: max(0, bounds.width - 221), height: 23)
        help.frame = NSRect(x: 59, y: y + 35, width: max(0, bounds.width - 77), height: 36)
        newButton.multiline = !selectedNew
        cookies.frame = NSRect(x: 0, y: y + 100, width: max(0, bounds.width - 80), height: 20)
        cookieHelp.frame = NSRect(x: 24, y: y + 123, width: max(0, bounds.width - 104), height: 18)
        error.frame = NSRect(x: 0, y: y + (showsCookieReplacement ? 147 : 85), width: bounds.width, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selectedNew {
            Self.fieldFill.setFill()
            NSBezierPath(roundedRect: NSRect(x: 166, y: CGFloat(buttons.count) * 62 + 15,
                width: max(0, bounds.width - 197), height: 48), xRadius: 12, yRadius: 12).fill()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard selectedNew, notification.object as? NSTextField === name else { return }
        onNameChange?(name.stringValue)
    }
    @objc private func toggleCookies() { onToggleCookies?() }
    private static let fieldFill = PArcDialogStyle.color(0x000000, 0.06, 0x000000, 1)
}

@MainActor
private final class ImportProfileButton: NSButton {
    override var isFlipped: Bool { true }
    var activate: (() -> Void)?
    var multiline = false
    init(_ title: String) {
        super.init(frame: .zero)
        // A radio-type button only tracks clicks on its dot and title text;
        // the whole drawn row must select, so state is set by the owner.
        self.title = title; setButtonType(.momentaryChange); isBordered = false
        focusRingType = .default; target = self; action = #selector(choose)
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityValue() -> Any? { state == .on ? 1 : 0 }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { activate?() }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        if isHighlighted { Self.pressedFill.setFill(); shape.fill() }
        Self.stroke.setStroke(); shape.lineWidth = 1; shape.stroke()
        let centerY: CGFloat = multiline ? 26 : bounds.height / 2
        let circle = NSRect(x: 18, y: centerY - 8, width: 16, height: 16)
        NSColor.white.setFill(); NSBezierPath(ovalIn: circle).fill()
        if state != .on { Self.stroke.setStroke(); NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5)).stroke() }
        if state == .on {
            NSColor(parcHex: "684AF5").setFill(); NSBezierPath(ovalIn: circle.insetBy(dx: 2, dy: 2)).fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: circle.insetBy(dx: 5, dy: 5)).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: PArcDialogStyle.popoverTitle]
        let text = title as NSString, height = text.size(withAttributes: attributes).height
        text.draw(in: NSRect(x: 59, y: centerY - height / 2, width: bounds.width - 77, height: height), withAttributes: attributes)
    }
    private static let stroke = PArcDialogStyle.color(0x000000, 0.2, 0xFFFFFF, 0.7)
    private static let pressedFill = PArcDialogStyle.color(0x000000, 0.04, 0xFFFFFF, 0.08)
}
