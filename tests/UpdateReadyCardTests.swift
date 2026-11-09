import AppKit
import SwiftUI

/// Inert native layout; no browser, displayed window or input automation.
@main @MainActor
struct UpdateReadyCardTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw Failure(message: message) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let card = UpdateReadyCard(frame: .zero)
        var actions = 0
        card.onRestart = { actions += 1 }; card.onToggleAutomaticUpdates = { actions += 1 }
        try expect(card.keyViewControls.count == 1 && !card.keyViewControls[0].acceptsFirstResponder,
                   "Collapsed, only the title is a stop, and none before the banner takes input")
        for dark in [false, true] {
            card.applyPalette(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "B9B5D4")!), isDark: dark))
            for automatic in [true, false] {
                card.setAutomaticUpdates(automatic)
                let heights = [CGFloat(148), 212, 484].map { card.preferredHeight(for: $0) }
                try expect(heights.allSatisfy { $0 == heights[0] } && (20...32).contains(heights[0]),
                           "It starts collapsed title at every sidebar width: \(heights)")
            }
        }
        try expect(actions == 0, "Laying out never reaches the original owner")
        try focus()
        print("UpdateReadyCard: \(assertions) assertions passed")
    }

    /// As the sidebar does after a height change: lay the slot out again.
    static func settle(_ card: UpdateReadyCard) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        card.frame.size.height = card.preferredHeight(for: card.frame.width)
        card.layoutSubtreeIfNeeded()
    }
    static func label(_ view: NSView?) -> String { (view as? UpdateBannerKeyStop)?.accessibilityLabel() ?? "\(view as Any)" }

    /// Opening from the title moves focus to Automatic Updates.
    static func focus() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 228, height: 200), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let card = UpdateReadyCard(frame: NSRect(x: 0, y: 0, width: 228, height: 1))
        var heightChanges = 0
        card.onHeightChange = { heightChanges += 1 }
        card.frame.size.height = card.preferredHeight(for: 228)
        window.contentView!.addSubview(card)
        card.setInteractionEnabled(true)
        settle(card)
        let title = card.keyViewControls[0]
        try expect(label(title) == "New Parc Version Available" && title.window === window && window.makeFirstResponder(title),
                   "The collapsed title takes focus")
        (title as? NSButton)?.performClick(nil)
        settle(card)
        let controls = card.keyViewControls
        try expect(heightChanges == 1 && controls.map(label) == ["Automatic Updates", "Restart and Update"],
                   "Open, the stops are the revealed controls: \(controls.map(label))")
        try expect(window.firstResponder === controls[0], "Space on the title moves focus to Automatic Updates, not \(label(window.firstResponder as? NSView))")
        let frames = controls.map { $0.convert($0.bounds, to: card) }
        try expect(controls.allSatisfy { $0.window === window } && frames[0].maxY <= frames[1].minY && card.bounds.contains(frames[1]),
                   "Automatic Updates sits above Restart and Update inside the card: \(frames)")
        try expect(!title.acceptsFirstResponder && title.isAccessibilityElement() == false,
                   "Open, the title is plain again for Tab and VoiceOver")
        try expect(window.makeFirstResponder(controls[1]) && controls[1].focusRingMaskBounds == controls[1].bounds,
                   "Restart and Update takes focus with a ring")
        let center = controls[1].convert(NSPoint(x: controls[1].bounds.midX, y: controls[1].bounds.midY), to: window.contentView)
        try expect(window.contentView!.hitTest(center) is NSHostingView<UpdateReadyBanner>, "The pointer reaches SwiftUI's button")
        // As the host hides it, then shows it anew.
        card.setInteractionEnabled(false)
        card.collapse()
        card.setInteractionEnabled(true)
        settle(card)
        try expect(card.keyViewControls.map(label) == ["New Parc Version Available"] && title.acceptsFirstResponder
                   && !controls.contains { $0 === window.firstResponder }, "Shown anew, the title is the stop again")
    }
}
