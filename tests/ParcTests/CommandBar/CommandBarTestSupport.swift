import AppKit

@MainActor
enum CommandBarTestSupport {
    static func prepareAppKit() {
        _ = NSApplication.shared
    }

    static func borderlessWindow(width: CGFloat = 400, height: CGFloat = 300) -> NSWindow {
        prepareAppKit()
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [], backing: .buffered, defer: false)
    }

    static func keyEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], characters: String = "\r",
                         type: NSEvent.EventType = .keyDown, window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    static var dark: NSAppearance { NSAppearance(named: .darkAqua)! }
    static var light: NSAppearance { NSAppearance(named: .aqua)! }

    static func rgba(_ color: NSColor, in appearance: NSAppearance) -> SIMD4<Double> {
        var out = SIMD4<Double>()
        appearance.performAsCurrentDrawingAppearance {
            let c = NSColor(cgColor: color.cgColor)!.usingColorSpace(.extendedSRGB)!
            out = SIMD4(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        }
        return out
    }

    static func rgba(_ cg: CGColor?) -> SIMD4<Double> {
        guard let cg, let c = NSColor(cgColor: cg)?.usingColorSpace(.extendedSRGB) else { return SIMD4(-1, -1, -1, -1) }
        return SIMD4(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    static func near(_ a: SIMD4<Double>, _ b: SIMD4<Double>, _ tolerance: Double = 0.003) -> Bool {
        let d = a - b
        return max(abs(d.x), abs(d.y), abs(d.z), abs(d.w)) <= tolerance
    }

    static func labels(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? labels(in: $0) }
    }
}
