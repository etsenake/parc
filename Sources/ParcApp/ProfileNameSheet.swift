import AppKit

@MainActor
final class ProfileNameSheet: NSWindowController, NSTextFieldDelegate {
    let profileID: UUID
    private let saveName: (String) throws -> Void
    private let name = NSTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton = ActionButton("Save")
    private let cancelButton = ActionButton("Cancel")
    private var saving = false

    init(profile: BrowserProfile, save: @escaping (String) throws -> Void) {
        profileID = profile.id
        saveName = save
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 496, height: 276),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Rename your Profile"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = LayoutView(frame: NSRect(x: 0, y: 0, width: 496, height: 276))
        window.contentView = content
        let title = NSTextField(labelWithString: "Rename your Profile")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.frame = NSRect(x: 38, y: 28, width: 420, height: 25)
        content.addSubview(title)
        let explanation = NSTextField(wrappingLabelWithString:
            "This won’t affect the names of any of the Spaces associated with this Profile.")
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor
        explanation.frame = NSRect(x: 38, y: 65, width: 420, height: 38)
        content.addSubview(explanation)
        name.stringValue = profile.name
        name.placeholderString = "Profile name"
        name.font = .systemFont(ofSize: 13)
        name.bezelStyle = .roundedBezel
        name.frame = NSRect(x: 38, y: 118, width: 420, height: 30)
        name.delegate = self
        name.setAccessibilityLabel("Profile name")
        content.addSubview(name)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 38, y: 157, width: 420, height: 43)
        content.addSubview(errorLabel)
        cancelButton.frame = NSRect(x: 250, y: 218, width: 110, height: 32)
        cancelButton.isBordered = true
        cancelButton.contentTintColor = .labelColor
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.actionBlock = { [weak self] in self?.cancel() }
        content.addSubview(cancelButton)
        saveButton.frame = NSRect(x: 369, y: 218, width: 89, height: 32)
        saveButton.isBordered = true
        saveButton.contentTintColor = .labelColor
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.actionBlock = { [weak self] in self?.save() }
        content.addSubview(saveButton)
        name.nextKeyView = cancelButton
        cancelButton.nextKeyView = saveButton
        saveButton.nextKeyView = name
        window.initialFirstResponder = name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func focusName() { window?.makeFirstResponder(name); name.selectText(nil) }

    func controlTextDidChange(_ obj: Notification) {
        saveButton.isEnabled = !saving && !name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        errorLabel.stringValue = ""
    }

    private func save() {
        guard !saving, saveButton.isEnabled, let window, window.sheetParent != nil else { return }
        saving = true
        saveButton.isEnabled = false
        do {
            try saveName(name.stringValue)
            window.sheetParent?.endSheet(window, returnCode: .OK)
        } catch {
            saving = false
            saveButton.isEnabled = !name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            errorLabel.stringValue = error.localizedDescription
            NSAccessibility.post(element: errorLabel, notification: .valueChanged)
        }
    }

    private func cancel() {
        guard !saving, let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }
}
