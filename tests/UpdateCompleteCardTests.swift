import AppKit

/// Inert native layout; no browser, displayed window or input automation.
@main @MainActor
struct UpdateCompleteCardTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw Failure(message: message) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let card = UpdateCompleteCard(frame: .zero)
        var actions = 0
        card.onSeeWhatsNew = { actions += 1 }; card.onShare = { actions += 1 }; card.onDismiss = { actions += 1 }
        try expect(card.keyViewControls.count == 1, "The hosted banner joins the key loop as one region")
        for dark in [false, true] {
            card.applyPalette(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "B9B5D4")!), isDark: dark))
            let heights = [CGFloat(148), 212, 484].map { card.preferredHeight(for: $0) }
            try expect(heights.allSatisfy { $0 == heights[0] } && (70...90).contains(heights[0]),
                       "One header and two single-line rows at every sidebar width: \(heights)")
        }
        try expect(actions == 0, "Laying out never reaches the original owner")
        print("UpdateCompleteCard: \(assertions) assertions passed")
    }
}
