import AppKit

@MainActor
final class SpaceCreationView: NSView, NSTextFieldDelegate {
    static let profileHelp = "Profiles keep website accounts, cookies and browsing data separate."
    var onNameChange: ((String) -> Void)?
    var onProfileChange: ((UUID) -> Void)?
    var onCreateProfile: (() -> Void)?
    var onChooseIcon: ((NSView) -> Void)?
    var onChooseTheme: ((NSView) -> Void)?
    var onCreate: (() -> Void)?
    var onCancel: (() -> Void)?

    private let cards = SpaceCreationCards()
    private let titleLabel = NSTextField(labelWithString: "Create a Space")
    private let detailLabel = NSTextField(wrappingLabelWithString: "Separate your tabs for life,\nwork, projects, and more.")
    private let nameCard = SpaceCreationCard()
    private let profileCard = SpaceCreationCard()
    private let themeCard = SpaceCreationCard()
    private let nameField = NSTextField()
    private let iconButton = PointingHandButton()
    private let profileGlyph = NSImageView()
    private let profileLabel = NSTextField(labelWithString: "Profile")
    private let profilePicker = PointingHandPopUpButton(frame: .zero, pullsDown: false)
    private let profileInfo = PointingHandButton()
    private let themeButton = PointingHandButton()
    private let createButton = SpaceCreationCreateButton()
    var palette: ThemeChromePalette? { didSet { createButton.palette = palette } }
    private let cancelButton = PointingHandButton()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var availableProfiles: [BrowserProfile] = []
    private var selectedProfileID: UUID
    private var creationAvailable = true
    private var committing = false
    private var canChangeProfile = true

    override var isFlipped: Bool { true }
    var name: String { nameField.stringValue }
    var iconAnchor: NSView { iconButton }
    var themeAnchor: NSView { themeButton }
    var hasMarkedText: Bool { (nameField.currentEditor() as? NSTextView)?.hasMarkedText() == true }

    init(profileID: UUID, profiles: [BrowserProfile]) {
        selectedProfileID = profileID
        super.init(frame: NSRect(x: 0, y: 0, width: 228, height: 740))
        setAccessibilityLabel("Create a Space")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.alignment = .center
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.alignment = .center
        detailLabel.textColor = .secondaryLabelColor
        addSubview(cards); addSubview(titleLabel); addSubview(detailLabel)
        addSubview(nameCard); addSubview(profileCard); addSubview(themeCard)

        nameField.isBordered = false; nameField.drawsBackground = false
        nameField.font = .systemFont(ofSize: 14)
        nameField.placeholderString = "Space name…"
        nameField.delegate = self; nameField.focusRingType = .none
        nameField.setAccessibilityLabel("Space name")
        nameCard.addSubview(nameField)
        configure(iconButton, title: "", action: #selector(chooseIcon(_:)))
        iconButton.setAccessibilityLabel("Choose Space icon")
        LiveShortcutToolTip.set(iconButton, "Choose an icon")
        nameCard.addSubview(iconButton)
        setIcon(nil)

        profileGlyph.image = NSImage(systemSymbolName: "person.crop.square", accessibilityDescription: nil)
        profileGlyph.contentTintColor = .secondaryLabelColor
        profileCard.addSubview(profileGlyph)
        profileLabel.font = .systemFont(ofSize: 13, weight: .medium)
        profileCard.addSubview(profileLabel)
        profilePicker.font = .systemFont(ofSize: 12, weight: .semibold)
        profilePicker.bezelStyle = .rounded
        profilePicker.target = self; profilePicker.action = #selector(profileChanged(_:))
        profilePicker.setAccessibilityLabel("Profile for new Space")
        profileCard.addSubview(profilePicker)
        configure(profileInfo, title: "", action: #selector(showProfileInfo(_:)))
        profileInfo.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About profiles")
        LiveShortcutToolTip.set(profileInfo, Self.profileHelp, behavior: .onMouseIdle(delay: 0))
        profileInfo.setAccessibilityLabel("About profiles")
        profileCard.addSubview(profileInfo)

        configure(themeButton, title: "Choose a Theme", action: #selector(chooseTheme(_:)))
        themeButton.image = NSImage(systemSymbolName: "paintbrush.pointed.fill", accessibilityDescription: nil)
        themeButton.imagePosition = .imageLeading; themeButton.alignment = .left
        themeButton.font = .systemFont(ofSize: 13, weight: .medium)
        themeCard.addSubview(themeButton)
        configure(createButton, title: "Create Space", action: #selector(createSpace(_:)))
        createButton.font = .systemFont(ofSize: 13, weight: .semibold)
        createButton.keyEquivalent = "\r"
        configure(cancelButton, title: "Cancel", action: #selector(cancelCreation(_:)))
        cancelButton.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .systemRed
        addSubview(errorLabel); addSubview(createButton); addSubview(cancelButton)
        replaceProfiles(profiles, selected: profileID, canChange: true)
        refreshAvailability()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title; button.target = self; button.action = action
        button.isBordered = false; button.setButtonType(.momentaryPushIn)
    }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 28)
        cards.frame = NSRect(x: (bounds.width - 76) / 2, y: 38, width: 76, height: 52)
        titleLabel.frame = NSRect(x: 10, y: 100, width: bounds.width - 20, height: 24)
        detailLabel.frame = NSRect(x: 14, y: 132, width: width, height: 42)
        nameCard.frame = NSRect(x: 14, y: 198, width: width, height: 36)
        iconButton.frame = NSRect(x: 5, y: 5, width: 26, height: 26)
        nameField.frame = NSRect(x: 33, y: 8, width: max(0, width - 40), height: 21)
        profileCard.frame = NSRect(x: 14, y: 240, width: width, height: 36)
        profileGlyph.frame = NSRect(x: 10, y: 10, width: 15, height: 16)
        profileLabel.frame = NSRect(x: 33, y: 10, width: 48, height: 20)
        profilePicker.frame = NSRect(x: 81, y: 6, width: max(40, width - 110), height: 26)
        profileInfo.frame = NSRect(x: width - 25, y: 8, width: 18, height: 20)
        themeCard.frame = NSRect(x: 14, y: 284, width: width, height: 36)
        themeButton.frame = NSRect(x: 10, y: 2, width: width - 20, height: 32)
        let bottom = max(368, bounds.height - 82)
        errorLabel.frame = NSRect(x: 14, y: bottom - 48, width: width, height: 42)
        createButton.frame = NSRect(x: 14, y: bottom, width: width, height: 36)
        cancelButton.frame = NSRect(x: 14, y: bottom + 42, width: width, height: 26)
    }
    func focusName() { guard !committing else { return }; window?.makeFirstResponder(nameField) }
    func setName(_ name: String) { nameField.stringValue = name; refreshAvailability() }
    func setIcon(_ icon: SidebarGroupIcon?) {
        iconButton.image = icon?.image
        iconButton.title = icon?.emoji ?? ""
        iconButton.font = .systemFont(ofSize: 17)
        if icon == nil { iconButton.image = NSImage(systemSymbolName: "plus.square.dashed", accessibilityDescription: nil) }
    }
    func replaceProfiles(_ profiles: [BrowserProfile], selected: UUID, canChange: Bool) {
        availableProfiles = profiles; selectedProfileID = selected; canChangeProfile = canChange
        profilePicker.removeAllItems()
        for profile in profiles {
            profilePicker.addItem(withTitle: profile.name)
            profilePicker.lastItem?.representedObject = profile.id
        }
        profilePicker.menu?.addItem(.separator())
        profilePicker.addItem(withTitle: "New Profile…")
        profilePicker.lastItem?.representedObject = "new-profile"
        selectOriginalProfile()
        profilePicker.isEnabled = canChange && !committing
        refreshAvailability()
    }
    func setCreationAvailable(_ available: Bool, committing: Bool = false) {
        creationAvailable = available; self.committing = committing
        nameField.isEnabled = !committing; iconButton.isEnabled = !committing
        themeButton.isEnabled = !committing; cancelButton.isEnabled = !committing
        profilePicker.isEnabled = canChangeProfile && !committing
        refreshAvailability()
    }
    func showError(_ error: String?) { errorLabel.stringValue = error ?? "" }
    private func refreshAvailability() {
        createButton.isEnabled = creationAvailable && !committing && !hasMarkedText &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            availableProfiles.contains { $0.id == selectedProfileID }
    }
    func controlTextDidChange(_ notification: Notification) {
        showError(nil); onNameChange?(name); refreshAvailability()
    }
    func controlTextDidEndEditing(_ notification: Notification) { refreshAvailability() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) { createSpace(nil); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelCreation(nil); return true }
        return false
    }
    override func cancelOperation(_ sender: Any?) { cancelCreation(sender) }
    @objc private func createSpace(_ sender: Any?) {
        refreshAvailability()
        guard createButton.isEnabled, !hasMarkedText else { return }
        onCreate?()
    }
    @objc private func cancelCreation(_ sender: Any?) { if !committing { onCancel?() } }
    @objc private func chooseIcon(_ sender: Any?) { if !committing { onChooseIcon?(iconButton) } }
    @objc private func chooseTheme(_ sender: Any?) { if !committing { onChooseTheme?(themeButton) } }
    @objc private func profileChanged(_ sender: Any?) {
        guard !committing else { selectOriginalProfile(); return }
        guard let id = profilePicker.selectedItem?.representedObject as? UUID else {
            selectOriginalProfile(); onCreateProfile?(); return
        }
        selectedProfileID = id; onProfileChange?(id); refreshAvailability()
    }
    private func selectOriginalProfile() {
        if let item = profilePicker.itemArray.first(where: { ($0.representedObject as? UUID) == selectedProfileID }) {
            profilePicker.select(item)
        } else { profilePicker.select(nil) }
    }
    @objc private func showProfileInfo(_ sender: Any?) {
        NSHelpManager.shared.setContextHelp(NSAttributedString(string: Self.profileHelp), for: profileInfo)
        NSHelpManager.shared.showContextHelp(for: profileInfo, locationHint: NSEvent.mouseLocation)
    }
}

private final class SpaceCreationCard: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
}

private final class SpaceCreationCards: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for (emoji, x, y, angle) in [("🌴", 11.0, 10.0, -15.0), ("📚", 41.0, 10.0, 15.0), ("💻", 26.0, 5.0, 0.0)] {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: x + 14, yBy: y + 20)
            transform.rotate(byDegrees: angle)
            transform.concat()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: -14, y: -20, width: 28, height: 40), xRadius: 3, yRadius: 3).fill()
            (emoji as NSString).draw(in: NSRect(x: -13, y: -12, width: 26, height: 28), withAttributes: [.font: NSFont.systemFont(ofSize: 22)])
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

@MainActor
final class SpaceCreationCreateButton: PointingHandButton {
    var palette: ThemeChromePalette? { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; isBordered = false; setButtonType(.momentaryPushIn)
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.1
        layer?.shadowRadius = 2; layer?.shadowOffset = .zero
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { false }
    private var isDark: Bool { palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) }
    var fill: NSColor {
        if isDark { return NSColor.black.withAlphaComponent(0.1) }
        let base = (palette?.maxContrastColor ?? .black).usingColorSpace(.sRGB) ?? .black
        return CommandBarSiteColor.lightnessAdjusted(red: base.redComponent, green: base.greenComponent,
                                                     blue: base.blueComponent, by: -0.1, alpha: 0.9)
    }
    var ink: NSColor { isDark ? (palette?.foregroundPrimary ?? .labelColor) : .white }
    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        let rect = pressed ? bounds.insetBy(dx: bounds.width * 0.01, dy: bounds.height * 0.01) : bounds
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        fill.setFill(); path.fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let text = NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink, .paragraphStyle: style])
        let size = text.size()
        text.draw(in: NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height))
    }
}
