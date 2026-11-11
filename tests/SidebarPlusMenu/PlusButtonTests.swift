import AppKit

final class PointerWindow: NSWindow {
    var pointer = NSPoint(x: -1, y: -1)
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

@main @MainActor struct PlusButtonTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard condition() else { fatalError("SidebarPlusButton: \(message)") }
    }

    static func near(_ value: CGFloat, _ expected: CGFloat, _ tolerance: CGFloat = 0.002) -> Bool {
        abs(value - expected) <= tolerance
    }

    static func gray(_ color: NSColor) -> (white: CGFloat, alpha: CGFloat) {
        let srgb = color.usingColorSpace(.sRGB)!
        return (srgb.redComponent, srgb.alphaComponent)
    }

    static func ink(_ view: NSView, threshold: CGFloat = 0.3)
        -> (maxAlpha: CGFloat, width: Int, height: Int, plate: CGFloat, corner: CGFloat) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        var maxAlpha: CGFloat = 0, minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                maxAlpha = max(maxAlpha, alpha)
                if alpha > threshold { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        let plate = rep.colorAt(x: 6, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0
        let corner = rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0
        return (maxAlpha, maxX - minX + 1, maxY - minY + 1, plate, corner)
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for (dark, white, a4, a5, a11, a12) in [(false, CGFloat(0), CGFloat(0.071), CGFloat(0.090), CGFloat(0.565), CGFloat(0.910)),
                                                (true, CGFloat(1), CGFloat(0.077), CGFloat(0.103), CGFloat(0.592), CGFloat(0.923))] {
            let colors = TranslucentButtonColors.standard(dark: dark)
            let scheme = dark ? "dark" : "light"
            check(gray(colors.background(hovered: false, pressed: false, enabled: true)).alpha == 0, "\(scheme) rest plate is clear")
            let hovered = gray(colors.background(hovered: true, pressed: false, enabled: true))
            check(near(hovered.alpha, a4) && hovered.white == white, "\(scheme) hovered plate is GrayA4")
            check(near(gray(colors.background(hovered: true, pressed: true, enabled: true)).alpha, a5), "\(scheme) pressed plate is GrayA5")
            check(near(gray(colors.foreground(pressed: false, enabled: true)).alpha, a11)
                  && gray(colors.foreground(pressed: false, enabled: true)).white == white, "\(scheme) glyph is GrayA11")
            check(near(gray(colors.foreground(pressed: true, enabled: true)).alpha, a12), "\(scheme) pressed glyph is GrayA12")
        }

        let window = PointerWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 64, height: 64),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let button = ActionButton("New Tab, Folder, or Space")
        button.title = ""
        button.toolTip = "New Tab, Folder, or Space"
        button.frame = NSRect(x: 16, y: 16, width: 32, height: 32)
        window.contentView?.addSubview(button)
        let state = SidebarPlusButtonState()
        check(!state.hovered && !state.pressed && !state.open, "the face starts at rest")
        check(state.colors == .standard(dark: false), "the face starts with the light GrayA colours")
        state.install(in: button)
        check(button.subviews.count == 1 && button.subviews[0].frame == button.bounds
              && button.subviews[0].autoresizingMask == [.width, .height], "the face fills the button")
        check(!button.subviews[0].isAccessibilityElement(), "the face is not an accessibility element")
        check(window.contentView?.hitTest(NSPoint(x: 32, y: 32)) === button, "clicks on the face reach the button")
        check(button.accessibilityLabel() == "New Tab, Folder, or Space", "the button keeps its label")

        button.onHighlight = { state.pressed = $0 }
        button.highlight(true)
        check(state.pressed, "NSButton's press highlight presses the face")
        button.highlight(false)
        check(!state.pressed, "releasing the highlight releases the face")

        button.onHover = { state.hovered = $0 }
        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let exited = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        button.mouseEntered(with: entered)
        check(state.hovered, "entering the button hovers the face")
        check(!NSApp.isActive, "the checks run in an app that never activates")
        window.pointer = NSPoint(x: 32, y: 32)
        button.refreshHover()
        check(!state.hovered && !button.hovered, "an inactive app's button drops its hover though the pointer is over it")

        let rest = ink(button)
        check(rest.width == 28 && rest.height == 28, "the + is round(14.4) = 14 points wide at rest (\(rest.width)×\(rest.height) px)")
        check(near(rest.maxAlpha, 0.565, 0.02), "the crossing is one GrayA11 coverage, not two (\(rest.maxAlpha))")
        check(rest.plate == 0, "the rest plate is clear (\(rest.plate))")

        button.mouseEntered(with: entered)
        let hovered = ink(button)
        check(near(hovered.plate, 0.071, 0.01) && hovered.corner < 0.01, "hovering shows the radius-6 GrayA4 plate (\(hovered.plate), corner \(hovered.corner))")
        check(hovered.width == 28 && near(hovered.maxAlpha, 0.596, 0.02), "the hovered glyph stays GrayA11 (\(hovered.width) px, \(hovered.maxAlpha))")

        button.highlight(true)
        let pressed = ink(button)
        check(near(pressed.plate, 0.090, 0.01), "pressing shows the GrayA5 plate (\(pressed.plate))")
        check(near(pressed.maxAlpha, 0.918, 0.02), "the pressed glyph is GrayA12 (\(pressed.maxAlpha))")
        check((26...27).contains(pressed.width) && pressed.height == pressed.width,
              "the press scales the 28-pixel glyph by 0.95 (\(pressed.width)×\(pressed.height) px)")
        button.highlight(false)
        button.mouseExited(with: exited)

        button.mouseEntered(with: entered)
        check(button.hovered && state.hovered, "entering hovers the + before the press")
        window.pointer = NSPoint(x: 32, y: 32)
        button.highlight(true)
        check(!button.hovered && !state.hovered && state.pressed, "pressing (or dragging back on) re-reads the hover")
        button.mouseEntered(with: entered)
        window.pointer = NSPoint(x: -40, y: -40)
        button.highlight(false)
        check(!button.hovered && !state.hovered && !state.pressed, "dragging the press off the + clears the hover and press plates")
        let draggedOff = ink(button)
        check(draggedOff.plate == 0, "the dragged-off + shows no plate (\(draggedOff.plate))")
        window.pointer = NSPoint(x: -1, y: -1)

        state.open = true
        let open = ink(button)
        check(open.width == 20 && open.height == 20, "the open × settles at π/4, 12/√2 + 2 ≈ 10.5 points (\(open.width)×\(open.height) px)")
        let openEdge = ink(button, threshold: 0.05)
        check(openEdge.width == 22 && openEdge.height == 22, "the open ×'s visible edge spans the 22 × 22 pixels (\(openEdge.width)×\(openEdge.height) px)")
        check(near(open.maxAlpha, 0.565, 0.02) && open.plate == 0, "the open × stays GrayA11 on a clear plate (\(open.maxAlpha), \(open.plate))")
        state.open = false
        let closed = ink(button)
        check(closed.width == 28 && closed.height == 28, "closing turns the × back into the + (\(closed.width)×\(closed.height) px)")
        window.close()
        print("Sidebar plus button checks passed (\(count))")
    }
}
