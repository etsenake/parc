import AppKit

/// The first-launch Safari step belongs to NewSetupView's existing card. Its
/// right column is a passive System Settings illustration, not a permission UI.
@MainActor
final class OnboardingSafariAccessView: NSView {
    let actions = LayoutView()
    var onOpenSettings: (() -> Void)?
    var onRevealApplication: (() -> Void)?
    var onRestart: (() -> Void)?
    private let openSettings = ActionButton("Open System Settings…")
    private let revealApplication = ActionButton("Show Parc in Finder")
    private let restart = ActionButton("Restart Parc")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let illustration = OnboardingSafariAccessIllustration()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(illustration)
        for button in [openSettings, revealApplication, restart] {
            button.isBordered = false; button.alignment = .left
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.contentTintColor = OnboardingSetupPalette.title
            button.focusRingType = .default
            actions.addSubview(button)
        }
        status.font = .systemFont(ofSize: 12)
        actions.addSubview(status)
        openSettings.actionBlock = { [weak self] in self?.onOpenSettings?() }
        revealApplication.actionBlock = { [weak self] in self?.onRevealApplication?() }
        restart.actionBlock = { [weak self] in self?.onRestart?() }
        actions.onLayout = { [weak self] in
            guard let self else { return }
            let width = self.actions.bounds.width
            self.openSettings.frame = NSRect(x: -2, y: 0, width: width + 2, height: 26)
            self.revealApplication.frame = NSRect(x: -2, y: 28, width: width + 2, height: 26)
            self.restart.frame = NSRect(x: -2, y: 56, width: width + 2, height: 26)
            self.status.frame = NSRect(x: 0, y: 92, width: width, height: 56)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(ready: Bool, checking: Bool, continuing: Bool, restarting: Bool,
                restartAvailable: Bool, error: String?) {
        openSettings.isEnabled = !restarting
        revealApplication.isEnabled = !restarting
        restart.isEnabled = ready && !checking && !continuing && !restarting && restartAvailable
        restart.title = restarting ? "Restarting…" : "Restart Parc"
        // The buttons and Next's spinner show progress; only a problem needs words.
        status.stringValue = error ?? ""
        status.textColor = OnboardingSetupPalette.title
    }

    override func layout() {
        super.layout()
        // Original importFromSafari branch: resizable illustration, top48,
        // top-aligned in the entire right column. It is not the 384×430 list.
        illustration.frame = NSRect(x: 0, y: 48, width: bounds.width, height: max(0, bounds.height - 48))
    }
}

/// Source-owned reconstruction of the reference SystemPreferencesVentura
///
///
@MainActor
private final class OnboardingSafariAccessIllustration: NSView {
    private let parcIcon: NSImage? = Bundle.main.url(forResource: "Original", withExtension: "png", subdirectory: "AppIcons")
        .flatMap(NSImage.init(contentsOf:))
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("In System Settings, choose Privacy & Security, Full Disk Access, then the plus button to add Parc. Turn on access and return here.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0, bounds.height > 0 else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.scaleBy(x: bounds.width / 1015, y: bounds.height / 1091)
        func box(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
            color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func text(_ value: String, _ rect: NSRect, size: CGFloat = 18, weight: NSFont.Weight = .regular,
                  color: NSColor = NSColor(white: 0.27, alpha: 1)) {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color, .paragraphStyle: paragraph])
        }
        func symbol(_ name: String, _ rect: NSRect, color: NSColor = .white) {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [color])) else { return }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let screen = NSRect(x: 34, y: 24, width: 948, height: 848)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 9), blur: 22, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        box(screen, NSColor(white: 0.96, alpha: 1), radius: 11)
        context.restoreGState()
        NSBezierPath(roundedRect: screen, xRadius: 11, yRadius: 11).addClip()
        box(NSRect(x: 34, y: 24, width: 285, height: 848), NSColor(white: 0.91, alpha: 1))
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            box(NSRect(x: 59 + CGFloat(index) * 27, y: 49, width: 16, height: 16), color, radius: 8)
        }
        box(NSRect(x: 44, y: 93, width: 263, height: 38), NSColor(white: 0.86, alpha: 1), radius: 8)
        symbol("magnifyingglass", NSRect(x: 54, y: 103, width: 17, height: 17), color: .darkGray)
        text("Search", NSRect(x: 80, y: 100, width: 210, height: 30), color: .gray)
        box(NSRect(x: 51, y: 147, width: 55, height: 55), NSColor(white: 0.86, alpha: 1), radius: 28)
        parcIcon?.draw(in: NSRect(x: 62, y: 158, width: 33, height: 33), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        text("This Mac", NSRect(x: 116, y: 151, width: 180, height: 25))
        text("System Settings", NSRect(x: 116, y: 177, width: 180, height: 24), size: 15, color: .gray)
        let sidebar: [(String, String, NSColor, CGFloat)] = [
            ("Wi-Fi", "wifi", .systemBlue, 226), ("Bluetooth", "wave.3.right", .systemBlue, 264),
            ("Network", "network", .systemBlue, 302), ("VPN", "shield.lefthalf.filled", .systemBlue, 340),
            ("Notifications", "bell.badge.fill", .systemRed, 392), ("Sound", "speaker.wave.2.fill", .systemPink, 430),
            ("Focus", "moon.fill", .systemPurple, 468), ("Screen Time", "hourglass", .systemPurple, 506),
            ("General", "gearshape", .systemGray, 559), ("Appearance", "circle.lefthalf.filled", .black, 597),
            ("Accessibility", "accessibility", .systemBlue, 635), ("Control Center", "switch.2", .systemGray, 673),
            ("Siri & Spotlight", "sparkle.magnifyingglass", .systemPurple, 711),
            ("Privacy & Security", "hand.raised.fill", .systemBlue, 749),
            ("Desktop & Dock", "dock.rectangle", .black, 801), ("Displays", "sun.max.fill", .systemBlue, 839)
        ]
        for (title, icon, color, y) in sidebar {
            let selected = title == "Privacy & Security"
            if selected { box(NSRect(x: 46, y: y - 10, width: 260, height: 38), NSColor(srgbRed: 0.87, green: 0.46, blue: 0.67, alpha: 1), radius: 7) }
            box(NSRect(x: 54, y: y - 1, width: 27, height: 27), color, radius: 5)
            symbol(icon, NSRect(x: 58, y: y + 3, width: 19, height: 19))
            text(title, NSRect(x: 87, y: y + 2, width: 222, height: 30), color: selected ? .white : NSColor(white: 0.27, alpha: 1))
        }
        symbol("chevron.left", NSRect(x: 347, y: 48, width: 14, height: 18), color: .gray)
        text("Full Disk Access", NSRect(x: 385, y: 46, width: 450, height: 35), size: 20, weight: .semibold)
        box(NSRect(x: 346, y: 92, width: 610, height: 442), NSColor(white: 0.92, alpha: 1), radius: 8)
        text("Allow the applications below to access data like Mail, Messages, Safari, Home, Time Machine backups, and certain administrative settings for all users on this Mac.", NSRect(x: 360, y: 106, width: 574, height: 76), color: .gray)
        let apps = [("iTerm", "terminal", NSColor.black), ("Screen Time", "hourglass", .systemPurple),
                    ("sshd-keygen-wrapper", "terminal", .black), ("us.zoom", "doc", .systemGray),
                    ("XProtect", "shield", .systemGray), ("zoom", "video.fill", .systemBlue)]
        for (index, app) in apps.enumerated() {
            let y = 195 + CGFloat(index) * 54
            box(NSRect(x: 360, y: y - 12, width: 582, height: 1), NSColor(white: 0.86, alpha: 1))
            box(NSRect(x: 360, y: y, width: 27, height: 27), app.2, radius: 5)
            symbol(app.1, NSRect(x: 364, y: y + 4, width: 19, height: 19))
            text(app.0, NSRect(x: 398, y: y + 1, width: 440, height: 29))
            box(NSRect(x: 909, y: y + 2, width: 34, height: 21), NSColor(white: 0.82, alpha: 1), radius: 11)
            box(NSRect(x: 910, y: y + 3, width: 19, height: 19), .white, radius: 10)
        }
        text("+  −", NSRect(x: 356, y: 503, width: 80, height: 28), size: 24, color: .gray)
        // The asset's dashed guide and callout are outside the Settings window.
        context.resetClip()
        let line = NSBezierPath(); line.move(to: NSPoint(x: 364, y: 546)); line.line(to: NSPoint(x: 364, y: 914))
        line.lineWidth = 4; line.lineCapStyle = .round; line.setLineDash([8, 12], count: 2, phase: 0)
        NSColor(srgbRed: 0.02, green: 0.28, blue: 1, alpha: 1).setStroke(); line.stroke()
        let callout = NSRect(x: 327, y: 925, width: 594, height: 94)
        box(callout, NSColor(white: 0.04, alpha: 0.88), radius: 24)
        let outline = NSBezierPath(roundedRect: callout, xRadius: 24, yRadius: 24); outline.lineWidth = 2; outline.stroke()
        text("Click [+] and choose this copy of Parc", NSRect(x: 352, y: 957, width: 550, height: 40), size: 24, weight: .semibold, color: .white)
    }
}
