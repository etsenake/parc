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
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let backdrop = PresentationBackdrop(frame: NSRect(x: 0, y: 0, width: 680, height: 400))
        let window = NSWindow(contentRect: backdrop.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = backdrop
        let group = SettingsGroupView(frame: NSRect(x: 64, y: 24, width: 552, height: 190))
        backdrop.addSubview(group)
        let rows = [("Privacy and Security", "lock.fill", NSColor.systemBlue),
                    ("Passwords", "key.fill", NSColor.systemGreen),
                    ("Credit Cards", "creditcard.and.123", NSColor.systemYellow),
                    ("Notifications", "bell.fill", NSColor.systemOrange),
                    ("Clear Browsing Data", "trash.fill", NSColor.systemRed)]
        for (index, value) in rows.enumerated() {
            let button = SettingsCommandButton(title: value.0, symbol: value.1, color: value.2)
            button.frame = NSRect(x: 10, y: 10 + CGFloat(index) * 34, width: 532, height: 34)
            group.addSubview(button); button.layoutSubtreeIfNeeded()
            expect(button.accessibilityRole() == .button && button.accessibilityLabel() == value.0, "One named native command")
            expect((button.accessibilityChildren()?.isEmpty ?? true), "Passive artwork and label are not duplicate AX controls")
            expect(button.subviews.allSatisfy { button.bounds.contains($0.frame) }, "Every actual command element is contained")
            expect(button.subviews.compactMap { $0 as? SettingsSymbolBadge }.first?.frame.size == NSSize(width: 24, height: 24), "Actual badge fits native 34-point command")
            for point in [NSPoint(x: 10, y: 17), NSPoint(x: 70, y: 17), NSPoint(x: 520, y: 17)] {
                expect(button.hitTest(button.convert(point, to: group)) === button, "Native command retains icon, text and arrow hit ownership")
            }
        }
        var activations = 0
        let action = SettingsCommandButton(title: "Native action", symbol: "lock.fill", color: .systemBlue) { activations += 1 }
        backdrop.addSubview(action)
        action.performClick(nil)
        expect(activations == 1, "Native accepted click reaches the existing closure once")
        action.isEnabled = false; action.performClick(nil)
        expect(activations == 1, "Disabled native command does not dispatch")
        action.removeFromSuperview()
        let disabled = SettingsCommandButton(title: "An unavailable command", symbol: "lock.fill", color: .systemBlue)
        disabled.frame = NSRect(x: 64, y: 234, width: 552, height: 34); disabled.isEnabled = false
        backdrop.addSubview(disabled)
        let cell = SettingsProfileCell(frame: NSRect(x: 64, y: 290, width: 190, height: 38))
        cell.name.stringValue = "A very long profile name"; cell.count.stringValue = "12 Spaces"
        backdrop.addSubview(cell); cell.layoutSubtreeIfNeeded()
        expect(cell.name.frame.maxX <= cell.count.frame.minX, "Long profile labels cannot obscure the Space count")
        expect(cell.bounds.contains(cell.name.frame) && cell.bounds.contains(cell.count.frame), "Profile cell text stays in row bounds")
        var fills: [CGColor] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            group.viewDidChangeEffectiveAppearance()
            backdrop.layoutSubtreeIfNeeded()
            fills.append(group.layer!.backgroundColor!)
            expect(group.layer?.cornerCurve == .continuous && group.layer?.borderWidth == 1, "Clipped reference border remains continuous and one point inside")
            let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds)!
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            expect(disabled.subviews.allSatisfy { $0.alphaValue == 0.25 }, "Unavailable content uses recovered opacity")
        }
        expect(fills[0] != fills[1], "Shared group palette follows actual effective appearance")
        print("Settings presentation: \(count) assertions passed; actual light/dark component renders saved")
    }
}
