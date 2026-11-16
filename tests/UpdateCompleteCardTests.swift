import AppKit
import SwiftUI

@main @MainActor
struct UpdateCompleteCardTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw Failure(message: message) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        let card = UpdateCompleteCard(frame: .zero)
        var actions = 0
        card.onSeeWhatsNew = { actions += 1 }; card.onDismiss = { actions += 1 }
        try expect(card.keyViewControls.allSatisfy { !$0.acceptsFirstResponder }, "A banner not yet taking input takes no focus")
        let labels = card.keyViewControls.map { $0.accessibilityLabel() ?? "" }
        try expect(labels == ["Dismiss", "See What’s New"], "Close and See What’s New are the only controls: \(labels)")
        let properties = Mirror(reflecting: card).children.compactMap(\.label)
        try expect(!properties.contains { $0.localizedCaseInsensitiveContains("share") }, "No Share row is left behind: \(properties)")
        let lilac = ThemeColor(hex: "B9B5D4")!, green = ThemeColor(hex: "2E7D32")!
        for dark in [false, true] {
            let palette = ThemeChromePalette(theme: .singleColor(lilac), isDark: dark)
            let other = ThemeChromePalette(theme: .singleColor(green), isDark: dark)
            card.applyPalette(other)
            let otherPlate = card.model.hover
            card.applyPalette(palette)
            try expect(card.model.hover == Color(nsColor: palette.hover) && card.model.hover != otherPlate,
                       "The row's hover plate takes the Space's own hover colour, like Parc's menu rows")
            let heights = [CGFloat(148), 212, 484].map { card.preferredHeight(for: $0) }
            try expect(heights.allSatisfy { $0 == heights[0] }
                       && heights[0] == 24 + 8 + UpdateBannerRow.plateHeight + 8,
                       "One header and one plated row at every sidebar width: \(heights)")
        }
        try expect(UpdateBannerRow.plateHeight == 32 && UpdateBannerRow.plateInset == 10 && UpdateBannerRow.plateRadius == 8,
                   "The plate keeps the spacing of Parc's menu rows")
        let stop = UpdateBannerKeyStop(label: "Probe", cornerRadius: 4)
        let wired = String(reflecting: type(of: Color.clear.updateBannerKeyStop(stop)))
        let bare = String(reflecting: type(of: Color.clear.accessibilityHidden(true).overlay { UpdateBannerKeyStop.Slot(stop: stop) }))
        try expect(wired.contains("UpdateBannerPointingHand") && !bare.contains("UpdateBannerPointingHand"),
                   "Every banner control asks SwiftUI for the pointing hand")
        card.setInteractionEnabled(true)
        try expect(card.model.interactive && card.keyViewControls.allSatisfy { ($0 as? NSControl)?.isEnabled == true },
                   "A banner taking input turns on every control's stop and the row's hover")
        card.setInteractionEnabled(false)
        try expect(!card.model.interactive && card.keyViewControls.allSatisfy { ($0 as? NSControl)?.isEnabled == false },
                   "A banner not taking input turns on neither")
        try expect(actions == 0, "Laying out never reaches the original owner")
        let grey = ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "808080")!), isDark: false)
        let greyBase = UpdateCompleteModel.gradientBase(grey)
        try expect(greyBase == .controlAccentColor || (greyBase.usingColorSpace(.sRGB)?.saturationComponent ?? 0) > 0.1,
                   "The gradient never paints a grey base")
        let blue = UpdateCompleteModel.gradientBase(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "0000FF")!), isDark: false))
        try expect(blue != .controlAccentColor, "A saturated theme keeps its own colour")
        if !CommandLine.arguments.contains("--windowless") { try keyLoop() }
        print("UpdateCompleteCard: \(assertions) assertions passed")
    }

    static func keyLoop() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 228, height: 200), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let card = UpdateCompleteCard(frame: NSRect(x: 0, y: 0, width: 228, height: 1))
        card.frame.size.height = card.preferredHeight(for: 228)
        window.contentView!.addSubview(card)
        card.setInteractionEnabled(true)
        card.layoutSubtreeIfNeeded()
        let stops = card.keyViewControls.compactMap { $0 as? UpdateBannerKeyStop }
        try expect(stops.map { $0.accessibilityLabel() ?? "" } == ["Dismiss", "See What’s New"],
                   "Every control is a stop: close, then See What’s New")
        let frames = stops.map { $0.convert($0.bounds, to: card) }
        try expect(stops.allSatisfy { $0.window === window } && frames.allSatisfy { !$0.isEmpty && card.bounds.contains($0) },
                   "SwiftUI places each stop over its control: \(frames)")
        try expect(frames[0].maxX == card.bounds.maxX && frames[0].maxY <= frames[1].minY
                   && frames[1].height == UpdateBannerRow.plateHeight && frames[1].minX == 8 && frames[1].maxX == card.bounds.maxX - 8,
                   "The loop runs in visual order, the trailing close button and then the row, whose stop covers its plate: \(frames)")
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
        try expect(window.firstResponder !== stops[1] && stops.allSatisfy { !$0.acceptsFirstResponder },
                   "An exiting banner gives focus up and takes no more")
    }
}
