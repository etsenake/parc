import AppKit

///
/// to pink and red on the right, fading into the window background below,
/// with the theme grain over it. Colours are sampled from that dialog.
@MainActor
final class BrowserImportSunsetHeader: NSView {
    static let height: CGFloat = 190
    /// The Import window's heading sits higher than setup's; the wash ends above it.
    static let windowHeight: CGFloat = 130
    private static let colors: [(CGFloat, UInt32)] = [
        (0, 0x4336BC), (0.2, 0x6B64D6), (0.37, 0x907CD9), (0.52, 0xC887C7),
        (0.66, 0xF082A2), (0.82, 0xFE7077), (1, 0xFE767E),
    ]
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Fades with the timing of the setup step's own transition.
    func reveal(_ shown: Bool) {
        let alpha: CGFloat = shown ? 1 : 0
        guard alphaValue != alpha else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window?.isVisible == true else {
            alphaValue = alpha; return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = alpha
        }
    }

    /// The colour stays full strength for the top half, then eases out.
    private static let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: [
        CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 0.72, alpha: 1),
        CGColor(gray: 0.25, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray, locations: [0, 0.5, 0.66, 0.82, 1])!
    private static let wash = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors.map { stop in
        CGColor(srgbRed: CGFloat(stop.1 >> 16 & 0xff) / 255, green: CGFloat(stop.1 >> 8 & 0xff) / 255,
                blue: CGFloat(stop.1 & 0xff) / 255, alpha: 1)
    } as CFArray, locations: colors.map(\.0))!

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.height > 0 else { return }
        let mask = CGContext(data: nil, width: 1, height: Int(bounds.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        // Bitmap rows run bottom-up; the opaque end belongs at the view's top.
        mask.drawLinearGradient(Self.fade, start: CGPoint(x: 0, y: CGFloat(mask.height)), end: .zero, options: [])
        context.saveGState()
        context.clip(to: bounds, mask: mask.makeImage()!)
        context.drawLinearGradient(Self.wash, start: CGPoint(x: bounds.minX, y: 0), end: CGPoint(x: bounds.maxX, y: 0), options: [])
        if let grain = OnboardingSetupCard.grainTile(.grain) {
            context.setBlendMode(.overlay); context.setAlpha(0.35)
            let tile = OnboardingSetupLayout.grainTileSize
            context.draw(grain, in: CGRect(origin: .zero, size: tile), byTiling: true)
        }
        context.restoreGState()
    }
}

///
/// only its data remains.
@MainActor
enum BrowserImportArcMark {
    static func icon(appURL: URL) -> NSImage {
        if Bundle(url: appURL)?.bundleIdentifier == BrowserImportCoordinator.arcBundleIdentifier { return NSWorkspace.shared.icon(forFile: appURL.path) }
        return image
    }

    static let image = NSImage(size: NSSize(width: 64, height: 64), flipped: true) { _ in
        func stroke(_ path: NSBezierPath, _ rgb: UInt32, _ alpha: CGFloat = 1) {
            NSColor(srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
                    blue: CGFloat(rgb & 0xff) / 255, alpha: alpha).setStroke()
            path.lineWidth = 11; path.lineCapStyle = .round; path.stroke()
        }
        let left = NSBezierPath(); left.move(to: NSPoint(x: 21, y: 53)); left.line(to: NSPoint(x: 33, y: 13))
        let right = NSBezierPath(); right.move(to: NSPoint(x: 33, y: 13)); right.line(to: NSPoint(x: 47, y: 51))
        let swoosh = NSBezierPath(); swoosh.move(to: NSPoint(x: 9, y: 33))
        swoosh.curve(to: NSPoint(x: 43, y: 37), controlPoint1: NSPoint(x: 15, y: 48), controlPoint2: NSPoint(x: 34, y: 49))
        stroke(right, 0xF09A9E)
        stroke(swoosh, 0x2F4BF2)
        stroke(left, 0xE8616D, 0.92)
        return true
    }
}
