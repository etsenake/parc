import AppKit

@main @MainActor
struct AutoArchiveEducationViewTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw Failure(message: message) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        var actions = 0
        view.onDismiss = { actions += 1 }; view.onSettings = { actions += 1 }
        let message = view.keyViewControls.compactMap { $0 as? NSTextView }.first!
        let button = view.keyViewControls.compactMap { $0 as? NSButton }.first!
        try expect(view.keyViewControls.count == 2, "Only Settings and Got it join the key loop")
        try expect(message.string.contains("12 hours") && button.title == "Got it", "Recovered content is retained")
        button.performClick(nil)
        try expect(actions == 0, "Detached native actions cannot reach the original owner")
        view.setInteractionEnabled(false)
        try expect(!message.acceptsFirstResponder && !button.isEnabled, "Exiting controls cannot accept focus or action")
        view.setInteractionEnabled(true)
        let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
        for dark in [false, true] {
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            view.applyPalette(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "B9B5D4")!), isDark: dark))
            for width: CGFloat in [144, 228, 500] {
                view.frame = NSRect(x: 0, y: 0, width: width, height: view.preferredHeight(for: width))
                view.layoutSubtreeIfNeeded()
                if let container = message.textContainer, let layout = message.layoutManager {
                    layout.ensureLayout(for: container)
                    try expect(layout.usedRect(for: container).height <= message.bounds.height + 1,
                               "Wrapped information must fit at width \(width)")
                }
                try expect(button.frame.minY >= message.frame.maxY && button.frame.maxY <= view.bounds.maxY,
                           "Body and Got it remain separate and inside the card")
                if let output, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let data = bitmap.representation(using: .png, properties: [:])!
                    try data.write(to: output.appendingPathComponent("education-\(dark ? "dark" : "light")-\(Int(width)).png"))
                }
            }
        }
        print("Automatic archive education view: \(assertions) assertions passed")
    }
}
