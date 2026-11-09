import AppKit

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
        try expect(card.keyViewControls.count == 1, "The hosted banner joins the key loop as one region")
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
        print("UpdateReadyCard: \(assertions) assertions passed")
    }
}
