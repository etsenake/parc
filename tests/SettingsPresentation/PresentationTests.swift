import AppKit

@MainActor
private final class PresentationBackdrop: LayoutView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

@main @MainActor
struct PresentationTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let width = SettingsLayout.contentWidth
        let backdrop = PresentationBackdrop(frame: NSRect(x: 0, y: 0, width: width, height: 420))
        let window = NSWindow(contentRect: backdrop.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = backdrop
        let rowHeight = SettingsLayout.rowHeight, groupWidth = SettingsLayout.groupWidth
        let heading = SettingsSectionHeading(title: "Your Data and Settings")
        heading.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset, y: 20, width: 300, height: SettingsLayout.headingHeight)
        backdrop.addSubview(heading)
        expect(heading.font == .systemFont(ofSize: 13, weight: .semibold), "Section headings use the semibold heading face")
        let rows = [("Privacy and Security", "lock.fill", NSColor.systemBlue),
                    ("Passwords", "key.fill", NSColor.systemGreen),
                    ("Credit Cards", "creditcard.and.123", NSColor.systemYellow),
                    ("Notifications", "bell.fill", NSColor.systemOrange)]
        let group = SettingsGroupView(frame: NSRect(x: SettingsLayout.margin, y: heading.frame.maxY + SettingsLayout.headingGap,
                                                    width: groupWidth, height: rowHeight * CGFloat(rows.count)))
        backdrop.addSubview(group)
        for (index, value) in rows.enumerated() {
            if index > 0 { group.separator(at: CGFloat(index) * rowHeight) }
            let button = SettingsCommandButton(title: value.0, symbol: value.1, color: value.2)
            button.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: groupWidth, height: rowHeight)
            group.addSubview(button); button.layoutSubtreeIfNeeded()
            expect(button.accessibilityRole() == .button && button.accessibilityLabel() == value.0, "One named native command")
            expect((button.accessibilityChildren()?.isEmpty ?? true), "Passive artwork and label are not duplicate AX controls")
            expect(button.subviews.allSatisfy { button.bounds.contains($0.frame) }, "Every actual command element is contained")
            expect(button.subviews.compactMap { $0 as? SettingsSymbolBadge }.first?.frame.size == NSSize(width: 20, height: 20), "Badge fits the grouped row")
            for point in [NSPoint(x: 14, y: 21), NSPoint(x: 80, y: 21), NSPoint(x: groupWidth - 16, y: 21)] {
                expect(button.hitTest(button.convert(point, to: group)) === button, "Native command retains icon, text and arrow hit ownership")
            }
        }
        expect(group.layer?.cornerRadius == SettingsLayout.groupRadius && group.layer?.cornerCurve == .continuous, "Groups use continuous rounded corners")
        expect(group.layer?.borderWidth == 0, "Groups sit on the page without an outline")
        var activations = 0
        let action = SettingsCommandButton(title: "Native action", symbol: "lock.fill", color: .systemBlue) { activations += 1 }
        backdrop.addSubview(action)
        action.performClick(nil)
        expect(activations == 1, "Native accepted click reaches the existing closure once")
        action.isEnabled = false; action.performClick(nil)
        expect(activations == 1, "Disabled native command does not dispatch")
        action.removeFromSuperview()
        let profiles = SettingsGroupView(frame: NSRect(x: SettingsLayout.margin, y: group.frame.maxY + 30, width: groupWidth, height: rowHeight))
        backdrop.addSubview(profiles)
        var opened = 0
        let profile = SettingsSpaceButton { opened += 1 }
        profile.update(name: String(repeating: "A very long Space name ", count: 6), detail: "Work", image: NSImage(systemSymbolName: "star", accessibilityDescription: nil))
        profile.frame = NSRect(x: 0, y: 0, width: groupWidth, height: rowHeight)
        profiles.addSubview(profile); profile.layoutSubtreeIfNeeded()
        expect(profile.name.frame.maxX <= profile.detail.frame.minX, "Long Space names cannot obscure the detail")
        expect(profile.bounds.contains(profile.name.frame) && profile.bounds.contains(profile.detail.frame), "Space row text stays in row bounds")
        expect(profile.detail.frame.width >= ceil(profile.detail.intrinsicContentSize.width), "The detail is never clipped")
        expect(profile.accessibilityLabel()?.hasSuffix(", Work") == true, "The Space row names its detail")
        expect(!profile.iconImage.isHidden && profile.iconEmoji.isHidden && profile.name.frame.minX > profile.iconImage.frame.maxX, "The Space row leads with its icon")
        profile.update(name: "Plain", detail: "", emoji: "🌱")
        expect(profile.accessibilityLabel() == "Plain" && profile.iconImage.isHidden && !profile.iconEmoji.isHidden, "An emoji icon replaces the symbol and an empty detail is not spoken")
        profile.performClick(nil)
        expect(opened == 1, "Choosing a Space row opens it once")
        let delete = SettingsPillButton(title: "Delete Space…")
        delete.destructive = true
        delete.frame = NSRect(x: SettingsLayout.margin, y: profiles.frame.maxY + 16, width: delete.fittingWidth, height: SettingsLayout.buttonHeight)
        backdrop.addSubview(delete)
        delete.setLabel("Deleting…")
        expect(delete.title == "Deleting…" && delete.fittingWidth > 0, "Deletion states relabel the same button")
        let disabled = SettingsCommandButton(title: "An unavailable command", symbol: "lock.fill", color: .systemBlue)
        disabled.frame = NSRect(x: SettingsLayout.margin, y: delete.frame.maxY + 16, width: groupWidth, height: rowHeight); disabled.isEnabled = false
        backdrop.addSubview(disabled)
        var fills: [CGColor] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            group.viewDidChangeEffectiveAppearance()
            backdrop.layoutSubtreeIfNeeded()
            fills.append(group.layer!.backgroundColor!)
            let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds)!
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            disabled.display()
            expect(disabled.subviews.allSatisfy { $0.alphaValue == 0.25 }, "Unavailable content uses recovered opacity")
        }
        expect(fills[0] != fills[1], "Shared group palette follows actual effective appearance")
        print("Settings presentation: \(count) assertions passed; actual light/dark component renders saved")
    }
}
