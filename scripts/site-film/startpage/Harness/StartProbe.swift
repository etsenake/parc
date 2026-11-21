import AppKit
@testable import Parc

@MainActor enum StartProbe {
    static func snapshot(_ view: NSView, scale: CGFloat = 2) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = view.bounds.size
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
        return bitmap
    }

    static func run(out: String) {
        let scenario = StartScenario.make()
        let page = StartPageView(frame: NSRect(x: 0, y: 0, width: 1042, height: 820))
        page.appearance = NSAppearance(named: .aqua)
        page.theme = scenario.work.theme
        page.layoutSubtreeIfNeeded()
        print("mark", page.mark.frame, "slot", page.commandBarSlot.frame, "intrinsic", page.mark.intrinsicContentSize)
        print("theme colors", scenario.work.theme.colors)
        Render.writePNG(snapshot(page), out + "/probe-rest.png")
        if let body = page.mark.subviews.first, let layer = body.layer {
            print("body layer anchor", layer.anchorPoint, "flipped super", layer.superlayer?.contentsAreFlipped() ?? false, "bounds", layer.bounds)
            layer.transform = CATransform3DMakeScale(1.3, 0.7, 1)
            layer.shadowColor = NSColor.systemPink.cgColor
            layer.shadowOpacity = 0.9
            layer.shadowRadius = 12
            layer.shadowOffset = .zero
        }
        page.commandBarSlot.alphaValue = 0.5
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 64))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.red.cgColor
        page.commandBarSlot.addSubview(box)
        let effect = CALayer()
        effect.frame = CGRect(x: 100, y: 100, width: 40, height: 20)
        effect.backgroundColor = NSColor.blue.cgColor
        effect.transform = CATransform3DMakeRotation(0.5, 0, 0, 1)
        page.markEffects.wantsLayer = true
        page.markEffects.layer?.addSublayer(effect)
        Render.writePNG(snapshot(page), out + "/probe-transform.png")
        Render.requireNoWindows("after the probe")
    }
}
