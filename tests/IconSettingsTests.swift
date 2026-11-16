import AppKit

@MainActor
private final class IconSettingsTestApplication: NSApplication {
    var simulatedActive = true
    override var isActive: Bool { simulatedActive }
}

@MainActor
private final class IconSettingsTestWindow: NSWindow {
    var simulatedKey = true
    override var isKeyWindow: Bool { simulatedKey }
}

@MainActor
private final class IconSettingsTestBackdrop: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

@main
@MainActor
struct IconSettingsTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(value(), message)
    }
    static func mouse(_ type: NSEvent.EventType, row: NSView, inside: Bool = true) -> NSEvent {
        let point = inside ? NSPoint(x: 160, y: 40) : NSPoint(x: -10, y: -10)
        return NSEvent.mouseEvent(with: type, location: row.convert(point, to: nil), modifierFlags: [],
                                  timestamp: 0, windowNumber: row.window!.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    static func key(_ type: NSEvent.EventType, _ code: UInt16, repeat repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                        isARepeat: repeated, keyCode: code)!
    }
    static func rows(in view: NSView) -> [IconChoiceRow] {
        view.subviews.flatMap { ($0 as? IconChoiceRow).map { [$0] } ?? rows(in: $0) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let application = IconSettingsTestApplication.shared as! IconSettingsTestApplication
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let icons = AppIconController(resources: root.appendingPathComponent("Resources"))
        var applications = 0
        icons.configure(preferenceURL: temporary.appendingPathComponent("choice.json")) { _ in applications += 1; return nil }
        let view = IconSettingsView(icons: icons)
        let window = IconSettingsTestWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 920),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let backdrop = IconSettingsTestBackdrop(frame: view.frame)
        window.contentView = backdrop
        backdrop.addSubview(view)
        view.layoutSubtreeIfNeeded()
        let choices = rows(in: view)
        expect(choices.count == 10, "Every approved variant gets one control")
        let original = choices[0], sorbet = choices[1], afterHours = choices[2]
        let originalTitle = original.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "The Original Parc" }!
        let titleFrame = originalTitle.frame
        expect(original.subviews.compactMap { $0 as? NSImageView }.first?.frame.size == NSSize(width: 64, height: 64),
               "Preview uses the recovered 64-point frame without cropping")
        expect(original.state == .on && choices.dropFirst().allSatisfy { $0.state == .off }, "Only saved choice is selected")
        _ = window.makeFirstResponder(original)
        expect(original.showsIconFocusRing && !sorbet.showsIconFocusRing, "Only the current responder draws the active focus ring")
        original.needsDisplay = false
        window.simulatedKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        expect(!original.showsIconFocusRing && original.needsDisplay, "Key loss removes the retained responder's ring and invalidates display")
        original.needsDisplay = false
        window.simulatedKey = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        expect(original.showsIconFocusRing && original.needsDisplay, "Key return redraws the unchanged responder ring")
        original.needsDisplay = false
        application.simulatedActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: application)
        expect(!original.showsIconFocusRing && original.needsDisplay, "Inactive application never shows an active ring")
        original.needsDisplay = false
        application.simulatedActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: application)
        expect(original.showsIconFocusRing && original.needsDisplay, "Application return redraws the eligible ring")
        expect(sorbet.accessibilityRole() == .radioButton, "Native radio role")
        expect(sorbet.accessibilityLabel() == "Sorbet", "Variant is the single AX name")
        expect(sorbet.accessibilityChildren()?.isEmpty == true, "Artwork and labels do not duplicate AX controls")
        expect(sorbet.superview?.accessibilityRole() == .radioGroup, "Choices are one named radio group")
        for point in [NSPoint(x: 26, y: 39), NSPoint(x: 90, y: 39), NSPoint(x: 170, y: 39), NSPoint(x: 450, y: 39)] {
            expect(sorbet.hitTest(sorbet.convert(point, to: sorbet.superview)) === sorbet, "Entire row shares one hit target")
        }
        expect(sorbet.hitTest(sorbet.convert(NSPoint(x: -2, y: 40), to: sorbet.superview)) == nil, "Unclipped children cannot enlarge the row hit target")

        sorbet.mouseDown(with: mouse(.leftMouseDown, row: sorbet))
        expect(sorbet.isHighlighted && applications == 0 && original.state == .on, "Press feedback precedes selection")
        sorbet.mouseDragged(with: mouse(.leftMouseDragged, row: sorbet, inside: false))
        expect(!sorbet.isHighlighted, "Leaving the row disarms its appearance")
        sorbet.mouseUp(with: mouse(.leftMouseUp, row: sorbet, inside: false))
        expect(applications == 0 && sorbet.state == .off, "Release outside cancels")
        sorbet.mouseDown(with: mouse(.leftMouseDown, row: sorbet))
        sorbet.mouseDragged(with: mouse(.leftMouseDragged, row: sorbet, inside: false))
        sorbet.mouseDragged(with: mouse(.leftMouseDragged, row: sorbet))
        expect(sorbet.isHighlighted, "Returning before release re-arms the press")
        sorbet.mouseUp(with: mouse(.leftMouseUp, row: sorbet))
        expect(applications == 1 && icons.selectedID == "Sorbet" && sorbet.state == .on && original.state == .off,
               "One completed gesture changes the saved choice and all radio states synchronously")
        view.layoutSubtreeIfNeeded()
        expect(originalTitle.frame == titleFrame, "Selection marker does not shift the title")
        sorbet.mouseUp(with: mouse(.leftMouseUp, row: sorbet))
        expect(applications == 1, "A stray release does not replay the action")

        for notification in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            afterHours.mouseDown(with: mouse(.leftMouseDown, row: afterHours))
            NotificationCenter.default.post(name: notification, object: window)
            afterHours.mouseUp(with: mouse(.leftMouseUp, row: afterHours))
            expect(!afterHours.isHighlighted && applications == 1, "Window interruption cancels an outstanding press")
            if notification == NSWindow.willCloseNotification {
                expect(!afterHours.accessibilityPerformPress(), "A stale AX reference cannot activate a closed Settings window")
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            }
        }
        afterHours.mouseDown(with: mouse(.leftMouseDown, row: afterHours))
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        afterHours.mouseUp(with: mouse(.leftMouseUp, row: afterHours))
        expect(applications == 1, "App deactivation cancels")
        afterHours.mouseDown(with: mouse(.leftMouseDown, row: afterHours))
        afterHours.isEnabled = false
        afterHours.mouseUp(with: mouse(.leftMouseUp, row: afterHours))
        expect(applications == 1 && !afterHours.accessibilityPerformPress(), "Disabled controls cannot activate through mouse or AX")
        afterHours.isEnabled = true

        _ = window.makeFirstResponder(afterHours)
        afterHours.keyDown(with: key(.keyDown, 49))
        afterHours.keyDown(with: key(.keyDown, 49, repeat: true))
        expect(afterHours.isHighlighted && applications == 1, "Held Space provides feedback without repeating saves")
        afterHours.keyUp(with: key(.keyUp, 49))
        expect(applications == 2 && afterHours.state == .on && !afterHours.isHighlighted, "Space release selects exactly once")
        afterHours.keyUp(with: key(.keyUp, 49))
        expect(applications == 2, "Repeated keyboard release is inert")
        sorbet.keyDown(with: key(.keyDown, 36))
        sorbet.keyDown(with: key(.keyDown, 53))
        sorbet.keyUp(with: key(.keyUp, 36))
        expect(applications == 2 && !sorbet.isHighlighted, "Escape cancels keyboard activation")
        _ = window.makeFirstResponder(sorbet)
        sorbet.keyDown(with: key(.keyDown, 49))
        _ = window.makeFirstResponder(afterHours)
        sorbet.keyUp(with: key(.keyUp, 49))
        expect(applications == 2, "Moving focus cancels held input")
        afterHours.keyDown(with: key(.keyDown, 126))
        expect(window.firstResponder === sorbet && icons.selectedID == "Sorbet" && applications == 3,
               "Arrow navigation focuses and selects the neighbor through the controller")
        sorbet.keyDown(with: key(.keyDown, 126))
        original.keyDown(with: key(.keyDown, 126))
        expect(icons.selectedID == "Original" && applications == 4, "Navigation stops at list edge without writing again")
        expect(afterHours.accessibilityPerformPress() && icons.selectedID == "AfterHours" && applications == 5,
               "AX press uses the same persisted selection")
        expect((afterHours.accessibilityValue() as? NSNumber)?.intValue == 1 && (original.accessibilityValue() as? NSNumber)?.intValue == 0,
               "AX values follow authoritative selection")

        sorbet.mouseDown(with: mouse(.leftMouseDown, row: sorbet))
        view.isHidden = true
        view.isHidden = false
        sorbet.mouseUp(with: mouse(.leftMouseUp, row: sorbet))
        expect(applications == 5, "Pane hide/show never inherits a press")
        sorbet.mouseDown(with: mouse(.leftMouseDown, row: sorbet))
        icons.select("Original")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        sorbet.mouseUp(with: mouse(.leftMouseUp, row: sorbet))
        expect(applications == 6 && icons.selectedID == "Original", "External selection retires pending input")

        let blocker = temporary.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocker)
        icons.configure(preferenceURL: blocker.appendingPathComponent("choice.json")) { _ in applications += 1; return nil }
        sorbet.performClick(nil)
        expect(applications == 6 && icons.selectedID == "Original" && original.state == .on && sorbet.state == .off,
               "Failed persistence keeps previous model and visual selection")
        expect(icons.message != nil && !icons.canRetry, "Save failure keeps truthful feedback")

        if CommandLine.arguments.count > 2 {
            let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                backdrop.appearance = NSAppearance(named: appearance)
                view.layoutSubtreeIfNeeded()
                backdrop.setFrameSize(view.frame.size)
                let image = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds)!
                backdrop.cacheDisplay(in: backdrop.bounds, to: image)
                try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            }
        }
        let retainedParent = sorbet.superview!
        sorbet.mouseDown(with: mouse(.leftMouseDown, row: sorbet))
        sorbet.removeFromSuperview()
        expect(!sorbet.accessibilityPerformPress() && !sorbet.isHighlighted, "Detached row cancels and refuses AX activation")
        retainedParent.addSubview(sorbet)
        sorbet.mouseUp(with: mouse(.leftMouseUp, row: sorbet))
        expect(applications == 6, "Reattachment does not revive old input")

        weak var releasedView: IconSettingsView?
        autoreleasepool {
            let ephemeral = IconSettingsView(icons: icons)
            releasedView = ephemeral
        }
        expect(releasedView == nil, "Subscription and row callbacks do not retain the pane")
        window.contentView = nil
        window.close()
        print("IconSettingsTests: \(assertions) assertions passed")
    }
}
