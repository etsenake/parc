import AppKit

///
///
///
@main
struct PagePlaceholderCheck {
    @MainActor
    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        var count = 0
        func expect(_ ok: Bool, _ message: String) { count += 1; precondition(ok, message) }

        let view = PagePlaceholderView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        expect(view.subviews.isEmpty && (view.layer?.sublayers ?? []).isEmpty, "an empty placeholder draws nothing of its own")
        view.show(solid(.systemTeal, size: CGSize(width: 120, height: 80)))
        expect(view.subviews.isEmpty && view.layer?.sublayers?.count == 1
               && view.layer?.sublayers?.first?.animationKeys() == nil,
               "only the snapshot, shown as it is: no title, card, text or animation")
        view.show(nil)
        expect((view.layer?.sublayers ?? []).isEmpty, "a placeholder without its snapshot draws nothing of its own")
        expect(view.accessibilityHelp() == "Shown in another window. Press to move it here.",
               "VoiceOver says where the page is and what pressing does")

        let large = solid(.systemTeal, size: CGSize(width: 2400, height: 1600))
        let small = PagePlaceholderView.downsampled(large, toFill: CGSize(width: 600, height: 300))
        expect(small.width == 600 && small.height == 400, "a snapshot keeps only the pixels that fill its pane, at its own aspect ratio")
        expect(PagePlaceholderView.downsampled(small, toFill: CGSize(width: 1200, height: 800)) === small,
               "a snapshot smaller than its pane is never enlarged")
        checkDecode(expect)
        expect(view.acceptsFirstResponder, "the frozen pane takes first responder overlay does")
        var clicked = false
        view.onClick = { clicked = true }
        expect(view.accessibilityPerformPress() && clicked, "pressing it brings the page back")

        expect(PagePlaceholderDim.opacity == 0.6, "the placeholder dim is 0.6")
        let still = CALayer()
        PagePlaceholderDim.apply(true, to: still, animated: false)
        expect(still.opacity == 0.6 && still.animation(forKey: "placeholderDim") == nil, "dims to 0.6")
        PagePlaceholderDim.apply(false, to: still, animated: false)
        expect(still.opacity == 1, "undims to full opacity")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let moving = CALayer()
            PagePlaceholderDim.apply(true, to: moving, animated: true)
            let spring = moving.animation(forKey: "placeholderDim") as? CASpringAnimation
            expect(spring.map { abs($0.stiffness - pow(2 * .pi / 0.225, 2)) < 0.001
                && abs($0.damping - 4 * .pi * 0.895 / 0.225) < 0.001 } == true, "dimming uses the 0.225 s / 0.895 spring")
            PagePlaceholderDim.apply(false, to: moving, animated: true)
            let back = moving.animation(forKey: "placeholderDim") as? CASpringAnimation
            expect(back.map { abs($0.stiffness - pow(2 * .pi / 0.245, 2)) < 0.001
                && abs($0.damping - 4 * .pi * 0.865 / 0.245) < 0.001 } == true, "undimming uses the 0.245 s / 0.865 spring")
        }

        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            print("PagePlaceholderCheck: \(count) assertions passed (screenshot comparison skipped)"); return
        }
        guard let screenshot = NSImage(contentsOf: URL(fileURLWithPath: arguments[1]))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("unreadable screenshot") }
        // Josh's screenshot (1024×584): the live pane at x 160, the frozen one
        // 512 points to the right; below y 270 both show the same content.
        let paneSize = CGSize(width: 345, height: 568)
        let live = pixels(screenshot.cropping(to: CGRect(origin: CGPoint(x: 160, y: 12), size: paneSize))!)
        let frozen = pixels(screenshot.cropping(to: CGRect(origin: CGPoint(x: 672, y: 12), size: paneSize))!)
        let rows = 258..<563, columns = 15..<330
        // The theme behind the pane: frozen = a·live + (1 − a)·theme, per channel.
        var theme = [Double](repeating: 0, count: 3), fitted = [Double](repeating: 0, count: 3)
        for channel in 0..<3 {
            var xs: [Double] = [], ys: [Double] = []
            for y in rows { for x in columns { xs.append(live.value(x, y, channel)); ys.append(frozen.value(x, y, channel)) } }
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let a = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            fitted[channel] = a
            theme[channel] = (my - a * mx) / (1 - a)
        }
        print(String(format: "Parc frozen pane fit: opacity %.3f %.3f %.3f over theme (%.0f, %.0f, %.0f)",
                     fitted[0], fitted[1], fitted[2], theme[0], theme[1], theme[2]))
        expect(fitted.allSatisfy { abs($0 - Double(PagePlaceholderDim.opacity)) < 0.05 }, "the frozen pane is drawn near 0.6 opacity")

        // Parc: the pane, dimmed, over the window surface in the theme colour.
        // The same layers BrowserPane composes, without AppKit's window.
        let frame = CGRect(origin: .zero, size: paneSize)
        let surface = CALayer(); surface.frame = frame
        surface.backgroundColor = CGColor(srgbRed: theme[0] / 255, green: theme[1] / 255, blue: theme[2] / 255, alpha: 1)
        let pane = CALayer(); pane.frame = frame; pane.backgroundColor = NSColor.white.cgColor
        let placeholder = PagePlaceholderView(frame: frame)
        placeholder.show(live.image)
        let frozenLayer = placeholder.layer!; frozenLayer.frame = frame
        pane.addSublayer(frozenLayer); surface.addSublayer(pane)
        PagePlaceholderDim.apply(true, to: pane, animated: false)
        let rendered = render(surface, size: paneSize)
        var error = 0.0, samples = 0.0
        for y in rows { for x in columns { for channel in 0..<3 {
            error += abs(rendered.value(x, y, channel) - frozen.value(x, y, channel)); samples += 1
        } } }
        let meanError = error / samples
        print(String(format: "Parc frozen pane against Parc's: mean absolute error %.2f of 255", meanError))
        if arguments.count > 2 {
            let side = sideBySide([frozen.image, rendered.image], size: paneSize)
            let data = NSBitmapImageRep(cgImage: side).representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: arguments[2]))
        }
        expect(meanError < 8, "Parc's frozen pane matches the within JPEG noise")
        print("PagePlaceholderCheck: \(count) assertions passed")
    }

    /// The engine's PNG of a 1440×900-point viewport at 2×, for a
    /// 600×400-point pane: decoded off the main thread straight to the
    /// pane's pixels.
    @MainActor static func checkDecode(_ expect: (Bool, String) -> Void) {
        let capture = CGSize(width: 2880, height: 1800), pane = CGSize(width: 1200, height: 800)
        let longest = PagePlaceholderSnapshot.maxPixelSize(source: capture, filling: pane)
        expect(longest == 1280, "the decoded frame is just large enough to fill its pane")
        expect(PagePlaceholderSnapshot.maxPixelSize(source: capture, filling: CGSize(width: 6000, height: 4000)) == 2880
               && PagePlaceholderSnapshot.maxPixelSize(source: .zero, filling: pane) == 0,
               "a frame is never decoded larger than the capture")
        let png = NSBitmapImageRep(cgImage: solid(.systemTeal, size: capture)).representation(using: .png, properties: [:])!
        var delivered: CGImage?, onMain = false
        PagePlaceholderSnapshot.thumbnail(fromPNG: png, maxPixelSize: longest) { delivered = $0; onMain = Thread.isMainThread }
        let deadline = Date().addingTimeInterval(5)
        while delivered == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        expect(delivered?.width == 1280 && delivered?.height == 800 && onMain,
               "the PNG decodes off the main thread straight to the pane's pixels, delivered on main")
    }

    struct Pixels {
        let image: CGImage
        let bytes: [UInt8]
        let width: Int
        func value(_ x: Int, _ y: Int, _ channel: Int) -> Double { Double(bytes[(y * width + x) * 4 + channel]) }
    }

    @MainActor static func pixels(_ image: CGImage) -> Pixels {
        let context = rgba(CGSize(width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return read(context)
    }

    @MainActor static func render(_ layer: CALayer, size: CGSize) -> Pixels {
        let context = rgba(size)
        layer.render(in: context)
        return read(context)
    }

    static func rgba(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                  bytesPerRow: Int(size.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func read(_ context: CGContext) -> Pixels {
        let image = context.makeImage()!
        let buffer = UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                         count: context.bytesPerRow * context.height)
        return Pixels(image: image, bytes: Array(buffer), width: context.width)
    }

    static func solid(_ color: NSColor, size: CGSize) -> CGImage {
        let context = rgba(size)
        context.setFillColor(color.cgColor); context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }

    static func sideBySide(_ images: [CGImage], size: CGSize) -> CGImage {
        let gap: CGFloat = 8
        let context = rgba(CGSize(width: size.width * CGFloat(images.count) + gap * CGFloat(images.count - 1), height: size.height))
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: CGFloat(index) * (size.width + gap), y: 0, width: size.width, height: size.height))
        }
        return context.makeImage()!
    }
}
