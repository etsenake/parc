import AppKit

/// Guidance only: the user grants access in macOS. This view never reads TCC,
/// changes a grant, or treats opening System Settings as successful permission.
@MainActor
final class BrowserImportAccessView: LayoutView {
    var onOpenSettings: (() -> Void)?
    var onRevealApplication: (() -> Void)?
    var onContinue: (() -> Void)?
    var onRestart: (() -> Void)?
    private let logo = NSImageView()
    private let heading = NSTextField(labelWithString: "Import from your browser")
    private let explanation = NSTextField(wrappingLabelWithString:
        "To import from this browser, Parc will need Full Disk Access. Feel free to remove access when this step is finished.\n\nAfter you have given access, you can choose to restart Parc now, or continue and restart later.")
    private let card = LayoutView()
    private let settingsIcon = NSImageView()
    private let cardTitle = NSTextField(labelWithString: "Full Disk Access")
    private let instructions = NSTextField(wrappingLabelWithString:
        "1. Open System Settings → Privacy & Security → Full Disk Access.\n\n2. Click + and add this copy of Parc.\n\n3. Turn on access for Parc, then return here.")
    private let appPath = NSTextField(wrappingLabelWithString: Bundle.main.bundleURL.path)
    private let openSettings = ActionButton("Open System Settings…")
    private let revealApplication = ActionButton("Show Parc in Finder")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let continueButton = ActionButton("Continue without restarting")
    private let restartButton = ActionButton("Restart Parc")

    override init(frame: NSRect) {
        super.init(frame: frame)
        if let url = Bundle.main.url(forResource: "Original", withExtension: "png", subdirectory: "AppIcons") {
            logo.image = NSImage(contentsOf: url)
        } else { logo.image = NSApp.applicationIconImage }
        logo.imageScaling = .scaleProportionallyUpOrDown; logo.setAccessibilityElement(false)
        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            settingsIcon.image = NSWorkspace.shared.icon(forFile: settings.path)
        } else { settingsIcon.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) }
        settingsIcon.imageScaling = .scaleProportionallyUpOrDown; settingsIcon.setAccessibilityElement(false)
        heading.font = .systemFont(ofSize: 18, weight: .bold); heading.textColor = .white
        explanation.font = .systemFont(ofSize: 16); explanation.textColor = NSColor.white.withAlphaComponent(0.82)
        card.wantsLayer = true; card.layer?.cornerRadius = 16
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        cardTitle.font = .systemFont(ofSize: 19, weight: .semibold); cardTitle.textColor = .white
        instructions.font = .systemFont(ofSize: 14); instructions.textColor = NSColor.white.withAlphaComponent(0.86)
        appPath.font = .systemFont(ofSize: 11); appPath.textColor = NSColor.white.withAlphaComponent(0.7)
        appPath.isSelectable = true; appPath.setAccessibilityLabel("Parc application path")
        status.font = .systemFont(ofSize: 12)
        [logo, heading, explanation, card, status, continueButton, restartButton].forEach(addSubview)
        [settingsIcon, cardTitle, instructions, appPath, openSettings, revealApplication].forEach(card.addSubview)
        for button in [openSettings, revealApplication, continueButton, restartButton] {
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.isBordered = true; button.bezelStyle = .rounded
            button.contentTintColor = .white; button.focusRingType = .default
        }
        continueButton.bezelColor = NSColor(parcHex: "584C92")
        restartButton.bezelColor = NSColor(parcHex: "8370E9")
        continueButton.actionBlock = { [weak self] in self?.onContinue?() }
        restartButton.actionBlock = { [weak self] in self?.onRestart?() }
        openSettings.actionBlock = { [weak self] in self?.onOpenSettings?() }
        revealApplication.actionBlock = { [weak self] in self?.onRevealApplication?() }
        setAccessibilityLabel("Full Disk Access guidance")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(ready: Bool, checking: Bool, continuing: Bool, restarting: Bool,
                restartAvailable: Bool, error: String?, sourceName: String = "this browser") {
        heading.stringValue = "Import from \(sourceName)"
        explanation.stringValue = "To import from \(sourceName), Parc will need Full Disk Access. Feel free to remove access when this step is finished.\n\nAfter you have given access, you can choose to restart Parc now, or continue and restart later."
        openSettings.isEnabled = !restarting; revealApplication.isEnabled = !restarting
        continueButton.isEnabled = !restarting && !continuing
        restartButton.isEnabled = ready && !checking && !continuing && !restarting && restartAvailable
        restartButton.title = restarting ? "Restarting…" : "Restart Parc"
        continueButton.title = continuing ? "Checking access…" : "Continue without restarting"
        status.stringValue = error ?? (restarting ? "Preparing to restart Parc…" : ready ?
            "\(sourceName) can now be read." : "You can continue with the data \(sourceName) currently makes available.")
        status.textColor = error == nil ? NSColor.white.withAlphaComponent(0.7) : .systemOrange
    }

    override func layout() {
        super.layout()
        logo.frame = NSRect(x: 30, y: 34, width: 54, height: 47)
        heading.frame = NSRect(x: 28, y: 108, width: 300, height: 27)
        explanation.frame = NSRect(x: 28, y: 145, width: 288, height: 280)
        card.frame = NSRect(x: 362, y: 100, width: bounds.width - 390, height: 406)
        settingsIcon.frame = NSRect(x: 22, y: 22, width: 48, height: 48)
        cardTitle.frame = NSRect(x: 83, y: 34, width: card.bounds.width - 100, height: 27)
        instructions.frame = NSRect(x: 24, y: 90, width: card.bounds.width - 48, height: 169)
        appPath.frame = NSRect(x: 24, y: 255, width: card.bounds.width - 48, height: 57)
        openSettings.frame = NSRect(x: 20, y: 319, width: card.bounds.width - 40, height: 32)
        revealApplication.frame = NSRect(x: 20, y: 357, width: card.bounds.width - 40, height: 30)
        status.frame = NSRect(x: 28, y: bounds.height - 110, width: bounds.width - 56, height: 35)
        continueButton.frame = NSRect(x: bounds.width - 319, y: bounds.height - 64, width: 191, height: 38)
        restartButton.frame = NSRect(x: bounds.width - 120, y: bounds.height - 64, width: 92, height: 38)
    }
}
