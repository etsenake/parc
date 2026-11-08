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
    private let openSettings = PArcDialogButton(title: "Open System Settings…", primary: false, hint: false)
    private let revealApplication = PArcDialogButton(title: "Show Parc in Finder", primary: false, hint: false)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let continueButton = PArcDialogButton(title: "Continue without restarting", primary: false, hint: false)
    private let restartButton = PArcDialogButton(title: "Restart Parc", primary: true, hint: false)

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
        heading.font = .systemFont(ofSize: 18, weight: .bold); heading.textColor = PArcDialogStyle.popoverTitle
        explanation.font = .systemFont(ofSize: 16); explanation.textColor = PArcDialogStyle.popoverMessage
        card.wantsLayer = true; card.layer?.cornerRadius = 16
        cardTitle.font = .systemFont(ofSize: 19, weight: .semibold); cardTitle.textColor = PArcDialogStyle.popoverTitle
        instructions.font = .systemFont(ofSize: 14); instructions.textColor = PArcDialogStyle.popoverTitle
        appPath.font = .systemFont(ofSize: 11); appPath.textColor = PArcDialogStyle.popoverMessage
        appPath.isSelectable = true; appPath.setAccessibilityLabel("Parc application path")
        status.font = .systemFont(ofSize: 12)
        [logo, heading, explanation, card, status, continueButton, restartButton].forEach(addSubview)
        [settingsIcon, cardTitle, instructions, appPath, openSettings, revealApplication].forEach(card.addSubview)
        for (button, action) in [(openSettings, #selector(openSettingsPressed)), (revealApplication, #selector(revealPressed)),
                                 (continueButton, #selector(continuePressed)), (restartButton, #selector(restartPressed))] {
            button.target = self; button.action = action
        }
        updateCardColor()
        setAccessibilityLabel("Full Disk Access guidance")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func openSettingsPressed() { onOpenSettings?() }
    @objc private func revealPressed() { onRevealApplication?() }
    @objc private func continuePressed() { onContinue?() }
    @objc private func restartPressed() { onRestart?() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCardColor()
    }
    private func updateCardColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            card.layer?.backgroundColor = PArcDialogStyle.color(0x000000, 0.04, 0xFFFFFF, 0.07).cgColor
        }
    }

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
        status.textColor = error == nil ? PArcDialogStyle.popoverMessage : .systemOrange
        needsLayout = true
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
        openSettings.frame = NSRect(x: 20, y: 315, width: openSettings.bodyWidth + 1, height: 38.5)
        revealApplication.frame = NSRect(x: 20, y: 357, width: revealApplication.bodyWidth + 1, height: 38.5)
        status.frame = NSRect(x: 28, y: bounds.height - 110, width: bounds.width - 56, height: 35)
        restartButton.frame = NSRect(x: bounds.width - 28 - restartButton.bodyWidth - 0.5, y: bounds.height - 64.5,
                                     width: restartButton.bodyWidth + 1, height: 38.5)
        continueButton.frame = NSRect(x: restartButton.frame.minX - 8 - continueButton.bodyWidth, y: bounds.height - 64.5,
                                      width: continueButton.bodyWidth + 1, height: 38.5)
    }
}
