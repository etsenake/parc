import AppKit
import SwiftUI

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
        try expect(card.keyViewControls.allSatisfy { !$0.acceptsFirstResponder }, "A banner not yet taking input takes no focus")
        for dark in [false, true] {
            card.applyPalette(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "B9B5D4")!), isDark: dark))
            let heights = [CGFloat(148), 212, 484].map { card.preferredHeight(for: $0) }
            try expect(heights.allSatisfy { $0 == heights[0] } && (70...90).contains(heights[0]),
                       "One header and two single-line rows at every sidebar width: \(heights)")
        }
        try expect(actions == 0, "Laying out never reaches the original owner")
        let grey = ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "808080")!), isDark: false)
        let greyBase = UpdateCompleteModel.gradientBase(grey)
        try expect(greyBase == .controlAccentColor || (greyBase.usingColorSpace(.sRGB)?.saturationComponent ?? 0) > 0.1,
                   "The gradient never paints a grey base")
        let blue = UpdateCompleteModel.gradientBase(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "0000FF")!), isDark: false))
        try expect(blue != .controlAccentColor, "A saturated theme keeps its own colour")
        try keyLoop()
        print("UpdateCompleteCard: \(assertions) assertions passed")
    }

    /// The stops SwiftUI places over the controls, linked as the sidebar links them.
    static func keyLoop() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 228, height: 200), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let card = UpdateCompleteCard(frame: NSRect(x: 0, y: 0, width: 228, height: 1))
        card.frame.size.height = card.preferredHeight(for: 228)
        window.contentView!.addSubview(card)
        card.setInteractionEnabled(true)
        card.layoutSubtreeIfNeeded()
        let stops = card.keyViewControls.compactMap { $0 as? UpdateBannerKeyStop }
        try expect(stops.map { $0.accessibilityLabel() ?? "" } == ["Dismiss", "See What’s New", "Share Parc"],
                   "Every control is a stop: close, then the rows")
        let frames = stops.map { $0.convert($0.bounds, to: card) }
        try expect(stops.allSatisfy { $0.window === window } && frames.allSatisfy { !$0.isEmpty && card.bounds.contains($0) },
                   "SwiftUI places each stop over its control: \(frames)")
        try expect(frames[0].maxX == card.bounds.maxX && frames[0].minY < frames[1].minY && frames[1].maxY <= frames[2].minY,
                   "The loop runs in visual order: the trailing close button, then the rows")
        let before = NSButton(), after = NSButton()
        let chain = [before] + stops + [after]
        chain.forEach { if $0.window == nil { window.contentView!.addSubview($0) } }
        for (view, next) in zip(chain, chain.dropFirst()) { view.nextKeyView = next }
        var forward: [NSView] = [], backward: [NSView] = []
        var view = before.nextKeyView
        while let current = view, current !== after { forward.append(current); view = current.nextKeyView }
        view = after.previousKeyView
        while let current = view, current !== before { backward.append(current); view = current.previousKeyView }
        try expect(forward.elementsEqual(stops, by: ===) && backward.elementsEqual(stops.reversed(), by: ===),
                   "Tab and Shift-Tab visit every control in order")
        for stop in stops {
            try expect(window.makeFirstResponder(stop) && window.firstResponder === stop
                       && stop.focusRingType != .none && stop.focusRingMaskBounds == stop.bounds,
                       "\(stop.accessibilityLabel() ?? "") takes focus with a ring around its control")
            let center = stop.convert(NSPoint(x: stop.bounds.midX, y: stop.bounds.midY), to: window.contentView)
            let hit = window.contentView!.hitTest(center)
            try expect(hit is NSHostingView<UpdateCompleteBanner>, "The pointer reaches SwiftUI's control under the stop, not \(hit as Any)")
        }
        card.setInteractionEnabled(false)
        try expect(window.firstResponder !== stops[2] && stops.allSatisfy { !$0.acceptsFirstResponder },
                   "An exiting banner gives focus up and takes no more")
    }
}
