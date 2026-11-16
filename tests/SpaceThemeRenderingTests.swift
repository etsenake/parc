import AppKit
import MetalKit

@MainActor
private final class ActivityWindow: NSWindow {
    var reportsKey = false
    var reportsMain = false
    override var isKeyWindow: Bool { reportsKey }
    override var isMainWindow: Bool { reportsMain }
}

@main
struct SpaceThemeRenderingTests {
    static func image(_ name: String) -> CGImage {
        let url = Bundle.main.resourceURL!.appendingPathComponent("ThemeTextures/\(name).png")
        return NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    @MainActor static func checkPagingMaterial(_ check: (Bool, String) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        let surface = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = surface
        defer { window.contentView = nil }
        let light = SpaceTheme(primaryColor: ThemeColor(red: 0.66, green: 0.8, blue: 0.96)!, colorCount: 2, appearance: .light)
        let alsoLight = SpaceTheme(primaryColor: ThemeColor(red: 0.95, green: 0.8, blue: 0.6)!, colorCount: 1, appearance: .light)
        let dark = SpaceTheme(primaryColor: ThemeColor(red: 0.4, green: 0.27, blue: 0.8)!, colorCount: 2, appearance: .dark)
        func materials() -> [NSVisualEffectView] { surface.subviews.compactMap { $0 as? NSVisualEffectView } }
        func isDark(_ view: NSVisualEffectView) -> Bool { view.appearance?.name == .darkAqua }
        surface.theme = light
        surface.pagingTransition = ThemePagingTransition(from: light, theme: alsoLight, progress: 0.3)
        check(materials().count == 1, "a swipe between same-style Spaces adds no material")
        surface.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.3)
        guard materials().count == 2 else { check(false, "a light ↔ dark swipe adds the foreground material"); return }
        let base = materials()[0], foreground = materials()[1]
        let canvas = surface.subviews.firstIndex { $0 is MTKView }
        check(surface.subviews.firstIndex(of: foreground) == surface.subviews.firstIndex(of: base).map { $0 + 1 }
              && canvas.map { $0 > surface.subviews.firstIndex(of: foreground)! } != false,
              "the foreground material lies just above the base and under the theme")
        check(base.material.rawValue == 1 && !isDark(base) && foreground.material.rawValue == 2 && isDark(foreground)
              && !foreground.isHidden && abs(foreground.alphaValue - 0.3) < 0.001,
              "the from style's material under the to style's at alpha = progress")
        check(foreground.blendingMode == .behindWindow && foreground.state == .followsWindowActiveState && foreground.isEmphasized,
              "the foreground material is built as the window's own")
        surface.layout()
        check(foreground.frame == surface.bounds, "it covers the surface")
        surface.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.8)
        check(materials().count == 2 && abs(foreground.alphaValue - 0.8) < 0.001, "the same view follows the swipe")
        surface.theme = dark
        check(base.material.rawValue == 1 && !isDark(base) && foreground.material.rawValue == 2 && isDark(foreground)
              && abs(foreground.alphaValue - 0.8) < 0.001 && materials().count == 2, "the commit leaves both materials")
        surface.pagingTransition = ThemePagingTransition(from: dark, theme: light, progress: 0.2)
        check(base.material.rawValue == 2 && isDark(base) && foreground.material.rawValue == 1 && !isDark(foreground)
              && abs(foreground.alphaValue - 0.2) < 0.001 && materials().count == 2, "the left page's style is the base")
        surface.pagingTransition = nil
        check(foreground.isHidden && !base.isHidden && base.material.rawValue == 2 && isDark(base), "at rest only the theme's own material shows")
        surface.pagingTransition = ThemePagingTransition(from: dark, theme: light, progress: 0.5)
        surface.floatingCornerRadius = 8
        check(foreground.isHidden, "a floating surface never shows the window's behind-window crossfade")
        surface.floatingCornerRadius = nil
        check(!foreground.isHidden, "the window's surface shows it again")
        surface.drawsBackground = false
        check(foreground.isHidden, "a locked sidebar's surface draws no material")
        surface.drawsBackground = true; surface.drawsMaterial = false
        check(foreground.isHidden, "a Library card draws no material")
        surface.drawsMaterial = true
        check(!foreground.isHidden, "restored with the material")
        surface.theme = dark
        surface.pagingTransition = ThemePagingTransition(from: dark, theme: SpaceTheme(), progress: 0.5)
        check(!foreground.isHidden && foreground.material.rawValue == 1 && !isDark(foreground), "towards an uncoloured Space in a light window")
        window.appearance = NSAppearance(named: .darkAqua)
        check(foreground.isHidden, "an uncoloured Space in a dark window has the dark style already")

        window.appearance = NSAppearance(named: .aqua)
        surface.theme = alsoLight
        surface.pagingTransition = ThemePagingTransition(from: dark, theme: light, progress: 0.3)
        check(base.material.rawValue == 2 && isDark(base) && foreground.material.rawValue == 1 && !isDark(foreground)
              && !foreground.isHidden && abs(foreground.alphaValue - 0.3) < 0.001, "past one page the left page's style is the base")
        surface.theme = light
        check(base.material.rawValue == 2 && isDark(base) && !foreground.isHidden, "a commit to either page leaves both materials")
        surface.pagingTransition = ThemePagingTransition(from: dark, theme: dark, progress: 0.3)
        check(foreground.isHidden && base.material.rawValue == 2, "pages of one style need no foreground")
        surface.pagingTransition = nil
        check(base.material.rawValue == 1 && !isDark(base) && foreground.isHidden, "at rest the base returns to the surface's own style")

        let container = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 120, height: 200))
        surface.addSubview(container)
        container.coordinateSpace = surface
        container.drawsBackground = false
        container.theme = light
        container.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.4)
        func containerMaterials() -> [NSVisualEffectView] {
            container.subviews.compactMap { $0 as? NSVisualEffectView }.filter { !$0.isHidden }
        }
        container.drawsBackground = true
        check(containerMaterials().count == 1, "a docked sidebar surface drawing again mid-swipe adds no behind-window crossfade")
        container.floatingCornerRadius = 8
        container.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.6)
        let floating = containerMaterials()
        check(floating.count == 2 && floating.allSatisfy { $0.blendingMode == .withinWindow && $0.material == .popover }
              && floating.map(isDark) == [false, true] && abs(floating[1].alphaValue - 0.6 / 0.9) < 0.001,
              "floating mid-swipe it blends into the dark page's blur through a within-window crossfade")
        container.floatingCornerRadius = nil
        check(containerMaterials().count == 1, "and docked again, only its own material")
        container.removeFromSuperview()
    }

    @MainActor static func checkGrainComposite(_ check: (Bool, String) -> Void) {
        let grain = image("grain"), tweed = image("tweed")
        check(grain.alphaInfo == .last && grain.width == 200 && grain.height == 200,
              "bundled grain decodes as a 200-pixel straight-alpha image")
        check(tweed.alphaInfo != .last && tweed.alphaInfo != .first && tweed.width == 100, "bundled tweed is opaque")
        let window = ActivityWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 200),
                                    styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        let surface = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView = surface; window.orderFront(nil); surface.layout()
        let canvas = surface.subviews.compactMap { $0 as? MTKView }.first!
        check(canvas.colorspace?.name == CGColorSpace.sRGB, "theme canvas outputs sRGB")
        canvas.framebufferOnly = false; canvas.autoResizeDrawable = false
        canvas.drawableSize = CGSize(width: 400, height: 400)
        let queue = canvas.device!.makeCommandQueue()!
        func render(noise: Double, active: Bool, texture: SpaceTheme.Texture = .grain)
            -> (mean: Double, alpha: Double, deviation: Double, width: Int) {
            window.reportsKey = active
            var theme = SpaceTheme.singleColor(ThemeColor(red: 0.5, green: 0.5, blue: 0.5)!)
            theme.intensity = 1; theme.noise = noise; theme.texture = texture
            surface.theme = theme
            canvas.releaseDrawables()
            guard let drawable = canvas.currentDrawable else { return (0, 0, 0, 0) }
            canvas.draw(canvas.bounds)
            canvas.needsDisplay = false
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let texture = drawable.texture, length = texture.width * texture.height * 4
            let buffer = canvas.device!.makeBuffer(length: length, options: .storageModeShared)!
            let command = queue.makeCommandBuffer()!, blit = command.makeBlitCommandEncoder()!
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                      to: buffer, destinationOffset: 0, destinationBytesPerRow: texture.width * 4,
                      destinationBytesPerImage: length)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
            var sum = 0.0, squares = 0.0, alpha = 0.0
            let count = texture.width * texture.height
            for pixel in 0..<count {
                let green = Double(bytes[pixel * 4 + 1]); sum += green; squares += green * green
                alpha += Double(bytes[pixel * 4 + 3])
            }
            let mean = sum / Double(count)
            return (mean, alpha / Double(count), (squares / Double(count) - mean * mean).squareRoot(), texture.width)
        }
        _ = render(noise: 0, active: true)
        let plain = render(noise: 0, active: true)
        let active = render(noise: 1, active: true)
        let inactive = render(noise: 1, active: false)
        let woven = render(noise: 1, active: true, texture: .tweed)
        window.orderOut(nil); window.contentView = nil
        check(plain.mean > 100 && active.mean > 0, "offscreen renderer produced the themed surface")
        check([plain, active, inactive, woven].allSatisfy { $0.width == 400 }, "readback uses the pinned 2× drawable")
        check(active.mean / plain.mean > 0.95 && active.mean / plain.mean < 1.03,
              "full grain darkens the surface slightly and must not brighten it beyond 1.03×")
        check(active.deviation > 3 && active.deviation < 13, "full grain stays within the premultiplied amplitude")
        check(inactive.deviation < active.deviation / 2.5, "inactive ownership quarters the grain amplitude")
        let context = CGContext(data: nil, width: tweed.width, height: tweed.height, bitsPerComponent: 8,
                                bytesPerRow: tweed.width * 4, space: tweed.colorSpace!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(tweed, in: CGRect(x: 0, y: 0, width: tweed.width, height: tweed.height))
        let texels = context.data!.bindMemory(to: UInt8.self, capacity: tweed.width * tweed.height * 4)
        let texel = (0..<(tweed.width * tweed.height)).reduce(0.0) { $0 + Double(texels[$1 * 4 + 1]) }
            / Double(tweed.width * tweed.height) / 255
        let strength = 0.4, base = plain.mean / 255, baseAlpha = plain.alpha / 255
        let predicted = 255 * (strength * texel * (1 - baseAlpha + base) + base * (1 - strength))
        check(abs(woven.mean - predicted) < 2, "opaque tweed composites unchanged at its measured maximum")
    }

    @MainActor static func checkEditorPresentation(_ check: (Bool, String) -> Void) {
        let dark = NSAppearance(named: .darkAqua)!
        var theme = SpaceTheme.singleColor(ThemeColor(red: 0.69, green: 1, blue: 0.85)!)
        theme.noise = 0.25; theme.intensity = 0.5
        let editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 356, height: 508),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.appearance = dark; window.contentView = editor
        editor.frame = NSRect(x: 0, y: 0, width: 356, height: 508); editor.layoutSubtreeIfNeeded()
        func snapshot(_ view: NSView, _ appearance: NSAppearance = dark) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                       pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = view.bounds.size
            window.appearance = appearance
            appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
            window.appearance = dark
            return rep
        }
        func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor {
            rep.colorAt(x: Int((x * 2).rounded(.down)), y: Int((y * 2).rounded(.down)))!
        }
        func control(_ label: String) -> NSView { editor.subviews.first { $0.accessibilityLabel() == label }! }

        let dial = control("Theme texture and noise"), dialImage = snapshot(dial)
        let center = NSPoint(x: dial.bounds.midX, y: dial.bounds.midY)
        func slot(_ index: Int) -> NSColor {
            let angle = (90 + Double(index) * 18) * .pi / 180
            return pixel(dialImage, center.x + cos(angle) * 32, center.y + sin(angle) * 32)
        }
        check(slot(0).alphaComponent < 0.02, "dial leaves its bottom dot slot empty")
        check((1..<20).allSatisfy { slot($0).alphaComponent > 0.1 }, "dial draws the other 19 dots")
        check((10...14).allSatisfy { slot($0).alphaComponent > 0.52 && slot($0).alphaComponent < 0.55 },
              "lit dots draw the foreground over the separator dot")
        check((Array(1...9) + Array(16...19)).allSatisfy { slot($0).alphaComponent > 0.1 && slot($0).alphaComponent < 0.2 },
              "remaining dots use the separator color")
        let indicator = pixel(dialImage, center.x + 38, center.y)
        check(indicator.alphaComponent > 0.95 && indicator.redComponent > 0.95, "white indicator capsule extends radially")
        check(pixel(dialImage, center.x + 32, center.y + 6).alphaComponent < 0.3, "indicator capsule is eight points wide")
        let disc = pixel(dialImage, center.x + 12, center.y).alphaComponent
        check(disc > 0.15 && disc < 0.45, "knob texture draws at the reduced opacity")
        check(pixel(dialImage, center.x, center.y - 24).alphaComponent < 0.02, "knob disc is 40 points across")
        let lightImage = snapshot(dial, NSAppearance(named: .aqua)!)
        let angle = (90 + 18.0) * .pi / 180
        let lightDot = pixel(lightImage, center.x + cos(angle) * 32, center.y + sin(angle) * 32).usingColorSpace(.deviceRGB)!
        check(lightDot.alphaComponent > 0.1 && lightDot.alphaComponent < 0.2 && lightDot.redComponent < 0.1,
              "Aqua separator dots are black at 0.15")
        let lightLit = pixel(lightImage, center.x, center.y - 32).usingColorSpace(.deviceRGB)!
        check(lightLit.alphaComponent > 0.39 && lightLit.alphaComponent < 0.42 && lightLit.redComponent < 0.1,
              "Aqua lit dots compose black 0.30 over 0.15")
        let lightIndicator = pixel(lightImage, center.x + 38, center.y).usingColorSpace(.deviceRGB)!
        check(lightIndicator.alphaComponent > 0.95 && lightIndicator.redComponent > 0.95, "Aqua keeps the white indicator")

        var still = ThemeButtonMotion()
        still.setHovered(true, animated: false); still.setPressed(true, animated: false)
        check(abs(still.scale - 0.945) < 1e-9 && still.isSettled, "a hovered press scales the knob 0.9 × 1.05")
        var press = ThemeButtonMotion(), deepest: CGFloat = 1
        press.setPressed(true, animated: true)
        check(press.scale == 1 && !press.isSettled, "a press springs from rest")
        for _ in 0..<60 { press.advance(1.0 / 60); deepest = min(deepest, press.scale) }
        check(deepest < 0.89 && deepest > 0.87, "the 0.5-damped press spring overshoots 0.9 by about 16%")
        check(press.isSettled && press.scale == 0.9, "the press settles at 0.9 within a second")
        var hover = ThemeButtonMotion()
        hover.setHovered(true, animated: true); hover.advance(0.05)
        check(hover.scale > 1.03 && hover.scale < 1.045 && hover.hover > 0.6 && hover.hover < 0.9,
              "hover scale and fill ease out together")
        hover.advance(0.05)
        check(hover.scale == 1.05 && hover.hover == 1 && hover.isSettled, "hover reaches 1.05 and the full fill after 0.1 seconds")
        let knobCenter = dial.convert(center, to: nil)
        dial.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: knobCenter, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 0, pressure: 0)!)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let hoveredImage = snapshot(dial)
        check((0..<8).contains { pixel(hoveredImage, center.x + 2 + CGFloat($0) * 2, center.y) != pixel(dialImage, center.x + 2 + CGFloat($0) * 2, center.y) },
              "hover zooms the knob texture")
        check(pixel(hoveredImage, center.x, center.y - 24).alphaComponent < 0.02, "hover keeps the 40-point knob circle")
        dial.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                      trackingNumber: 0, userData: nil)!)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        func peakAlpha(_ view: NSView) -> CGFloat {
            let image = snapshot(view)
            var peak: CGFloat = 0
            for y in 0..<image.pixelsHigh { for x in 0..<image.pixelsWide { peak = max(peak, image.colorAt(x: x, y: y)!.alphaComponent) } }
            return peak
        }
        let previous = control("Previous color presets") as! NSButton, next = control("Next color presets") as! NSButton
        check(!previous.isEnabled && next.isEnabled, "the first preset page disables only <")
        let dimming = peakAlpha(previous) / peakAlpha(next)
        check(dimming > 0.3 && dimming < 0.37, "disabled < draws the enabled chevron at 0.33 opacity")
        check(previous.frame.size == NSSize(width: 32, height: 32), "the chevron keeps a 32-point label frame")
        func ink(_ view: NSView, _ appearance: NSAppearance) -> NSColor {
            let image = snapshot(view, appearance)
            var best = NSColor.clear
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    let color = image.colorAt(x: x, y: y)!
                    if color.alphaComponent > best.alphaComponent { best = color }
                }
            }
            return best.usingColorSpace(.deviceRGB)!
        }
        let darkInk = ink(next, dark), lightInk = ink(next, NSAppearance(named: .aqua)!)
        check(darkInk.alphaComponent > 0.46 && darkInk.alphaComponent < 0.53 && darkInk.redComponent > 0.9,
              "> draws white at primary × 0.6 in Dark")
        check(lightInk.alphaComponent > 0.46 && lightInk.alphaComponent < 0.53 && lightInk.redComponent < 0.1,
              "> draws black at primary × 0.6 in Aqua")
        func enterExit(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        next.mouseEntered(with: enterExit(.mouseEntered)); previous.mouseEntered(with: enterExit(.mouseEntered))
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let hoveredNext = snapshot(next), edgeFill = pixel(hoveredNext, 1, 16).alphaComponent
        check(edgeFill > 0.05 && edgeFill < 0.16, "hovered > fills its frame with Color.secondary × 0.2")
        check(pixel(hoveredNext, 0.5, 0.5).alphaComponent < 0.02, "the hover fill keeps the 8-point corner")
        check(pixel(snapshot(previous), 1, 16).alphaComponent < 0.01, "disabled < shows no hover fill")
        next.mouseExited(with: enterExit(.mouseExited)); previous.mouseExited(with: enterExit(.mouseExited))
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        check(pixel(snapshot(next), 1, 16).alphaComponent < 0.01, "the hover fill fades out on exit")

        let slider = control("Theme intensity"), sliderImage = snapshot(slider)
        check(slider.frame == NSRect(x: 10, y: 422, width: 240, height: 60), "intensity slider shares the dial's center line")
        let midY = slider.bounds.midY, thumb = pixel(sliderImage, 16 + 208 * 0.5, midY)
        check(thumb.alphaComponent > 0.95 && thumb.redComponent > 0.95, "slider thumb is white")
        let leading = 16 + 6.0332 * 1.5 * .pi, trailing = 16 + 6.0332 * 9.5 * .pi
        let track = pixel(sliderImage, leading, midY).alphaComponent
        check(track > 0.04 && track < 0.12, "leading side draws the half-opacity separator track")
        check(pixel(sliderImage, trailing, midY).alphaComponent < 0.02, "trailing side has no track")
        let lit = pixel(sliderImage, leading, midY + 7.5).alphaComponent
        let unlit = pixel(sliderImage, trailing, midY + 7.5).alphaComponent
        check(lit > 0.52 && lit < 0.62 && unlit > 0.1 && unlit < 0.2, "wave uses foreground before the thumb and separator after")

        let swatch = control("Brand color 1"), swatchImage = snapshot(swatch)
        check(swatch.frame.size == NSSize(width: 24, height: 24), "preset swatch keeps its 24-point frame")
        check(pixel(swatchImage, 0.75, 12).alphaComponent > 0.8, "preset color reaches the frame edge")
        let fill = pixel(swatchImage, 12, 12).usingColorSpace(.deviceRGB)!
        let border = pixel(swatchImage, 1.25, 12).usingColorSpace(.deviceRGB)!
        check(border.greenComponent < fill.greenComponent * 0.95 && border.greenComponent > fill.greenComponent * 0.8,
              "two-point inner border darkens the edge by the black 0.1 overlay")

        let empty = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        window.contentView = empty; empty.frame = editor.frame; empty.layoutSubtreeIfNeeded()
        let padImage = snapshot(empty.subviews.first { $0.accessibilityLabel() == "Theme color pad" }!)
        var lowest = CGFloat(1), highest = CGFloat(0)
        for y in stride(from: CGFloat(100), to: 116, by: 0.5) {
            for x in stride(from: CGFloat(4), to: 20, by: 0.5) {
                let alpha = pixel(padImage, x, y).alphaComponent
                lowest = min(lowest, alpha); highest = max(highest, alpha)
            }
        }
        check(lowest > 0.03 && lowest < 0.06, "pad fill is primary at 0.05")
        check(highest > 0.2, "pad grid draws at 0.4 opacity")
        let pad = empty.subviews.first { $0.accessibilityLabel() == "Theme color pad" }!
        check(pad.layer?.cornerRadius == 8 && pad.layer?.cornerCurve == .continuous, "pad clips to an 8-point continuous corner")
        window.contentView = nil
    }

    @MainActor static func checkTooltipTheme(_ check: (Bool, String) -> Void) {
        let theme = SpaceTheme.singleColor(ThemeColor(hex: "5E3FA0")!)
        let editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
        var reported: [SpaceTheme] = []
        editor.onTooltipThemeChange = { reported.append($0) }
        var restored = theme; restored.noise = 0.4
        editor.synchronizeTheme(restored)
        check(reported.isEmpty, "a windowless editor reports no tooltip theme")
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 356, height: 508),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = editor
        check(reported == [restored], "arriving in a window reports the shown theme once")
        editor.finishEditing()
        check(reported.count == 1, "a refresh without a theme change reports nothing")
        var replaced = restored; replaced.primaryColor = ThemeColor(hex: "F25E6B")!
        editor.synchronizeTheme(replaced)
        check(reported.last == replaced, "a parent replacement reports the new theme")
        let intensity = editor.subviews.first { $0.accessibilityLabel() == "Theme intensity" }!
        _ = intensity.accessibilityPerformIncrement()
        check(reported.last?.intensity == editor.theme.intensity && editor.theme.intensity != replaced.intensity,
              "an edit reports the edited theme")
        let edited = editor.theme
        window.contentView = nil
        window.contentView = editor
        check(reported.suffix(2) == [edited, edited], "arriving in a window again reports even an unchanged theme")
        window.contentView = nil
        let count = reported.count
        editor.synchronizeTheme(theme)
        check(reported.count == count, "a detached editor reports nothing")
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); assertions += 1
        }
        func near(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.00001 }
        let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
        let black = ThemeColor(red: 0.04, green: 0.03, blue: 0.08)!
        let white = ThemeColor(red: 0.98, green: 0.97, blue: 0.99)!
        let darkTheme = SpaceTheme.singleColor(black), lightTheme = SpaceTheme.singleColor(white)
        check(ThemeChromePalette(theme: darkTheme, appearance: light).isDark, "dark color selects light text even in Light app appearance")
        check(!ThemeChromePalette(theme: lightTheme, appearance: dark).isDark, "light color selects dark text even in Dark app appearance")
        let darkSurface = ThemeSurfaceStyle(theme: lightTheme, appearance: dark)
        let lightSurface = ThemeSurfaceStyle(theme: darkTheme, appearance: light)
        check(darkSurface.backgroundIsDark && !lightSurface.backgroundIsDark, "Metal backdrop follows native appearance independently of text contrast")
        check(darkSurface.material.rawValue == 1 && lightSurface.material.rawValue == 1, "editor themes use original light material")
        check(ThemeSurfaceStyle(theme: SpaceTheme(), appearance: dark).material.rawValue == 2, "empty theme follows native dark material")
        check(ThemeSurfaceStyle(theme: SpaceTheme(), appearance: light).material.rawValue == 1, "empty theme follows native light material")
        check(ThemeChromePalette(theme: SpaceTheme(), appearance: dark).contentAppearance === dark,
              "empty theme preserves the full inherited native appearance")
        var invalidPaletteTheme = darkTheme; invalidPaletteTheme.noise = .nan
        check(ThemeChromePalette(theme: invalidPaletteTheme, appearance: light).contentAppearance === light,
              "invalid theme preserves the native fallback appearance")
        let darkFallback = ThemeSurfaceStyle(theme: darkTheme, appearance: light, colorRenderingAvailable: false)
        check(darkFallback.backgroundIsDark && darkFallback.material.rawValue == 2,
              "unavailable color renderer places light theme text over dark native material")
        let lightFallback = ThemeSurfaceStyle(theme: lightTheme, appearance: dark, colorRenderingAvailable: false)
        check(!lightFallback.backgroundIsDark && lightFallback.material.rawValue == 1,
              "unavailable color renderer places dark theme text over light native material")
        var forced = darkTheme; forced.appearance = .light
        check(!ThemeSurfaceStyle(theme: forced, appearance: dark).backgroundIsDark, "legacy forced Light remains compatible")
        check(!ThemeChromePalette(theme: forced, appearance: dark).isDark, "legacy forced Light text remains compatible")
        forced.appearance = .dark
        check(ThemeSurfaceStyle(theme: forced, appearance: light).backgroundIsDark, "legacy forced Dark remains compatible")
        check(ThemeSurfaceStyle(theme: forced, appearance: light).material.rawValue == 2, "legacy forced Dark material remains compatible")

        let root = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = ActivityWindow(contentRect: NSRect(x: -10000, y: -10000, width: root.frame.width, height: root.frame.height),
                                    styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.appearance = light; window.contentView = root
        root.theme = darkTheme
        let material = root.subviews.compactMap { $0 as? NSVisualEffectView }.first!
        check(material.material.rawValue == 1 && material.isEmphasized, "production native material uses recovered style and emphasis")
        check(material.blendingMode == .behindWindow && material.state == .followsWindowActiveState, "native backdrop preserves actual window compositing")
        root.layout()
        check(material.frame == root.bounds, "layout syncs material to bounds")
        var layoutCallbacks = 0
        root.onLayout = { layoutCallbacks += 1 }
        root.layout()
        check(layoutCallbacks == 0 && material.frame == root.bounds, "no-op layout skips onLayout when surfaces already match bounds")
        root.setFrameSize(NSSize(width: 640, height: 480))
        root.layout()
        check(layoutCallbacks == 1 && material.frame == root.bounds, "a real bounds change still fires onLayout and syncs surfaces")
        root.layout()
        check(layoutCallbacks == 1, "a follow-up layout at the new size remains a no-op")
        let content = NSView(frame: root.bounds)
        content.appearance = root.palette.contentAppearance; root.addSubview(content)
        check(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "native text subtree gets contrasting appearance")
        let nested = ThemeRendererView(frame: content.bounds)
        content.addSubview(nested); nested.theme = darkTheme
        check(!nested.surfaceStyle.backgroundIsDark, "nested theme does not inherit sibling text appearance for its underlay")
        let neighborContent = NSView(frame: content.bounds)
        nested.addSubview(neighborContent)
        nested.onPaletteChange = { neighborContent.appearance = $0.contentAppearance }
        nested.theme = SpaceTheme()
        check(neighborContent.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
              "unthemed neighbor content resolves from native window instead of current Space contrast")
        var publications = 0
        root.onPaletteChange = { _ in publications += 1 }
        root.theme = lightTheme
        check(publications == 1 && !root.palette.isDark, "theme change publishes complete text palette immediately")
        check(root.layer?.animationKeys()?.isEmpty != false, "theme editor backing has no invented timed crossfade")
        root.theme = lightTheme
        check(publications == 1, "unchanged theme does not republish")
        window.appearance = dark
        check(root.surfaceStyle.backgroundIsDark && nested.surfaceStyle.backgroundIsDark, "native appearance update reaches original and nested surfaces")
        check(neighborContent.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
              "appearance update republishes an unthemed neighbor's content scheme")
        check(!root.palette.isDark, "native appearance update preserves contrast-selected theme text")
        root.drawsBackground = false
        check(material.isHidden, "locked sidebar backing visibility is preserved")
        root.drawsBackground = true
        check(root.drawsMaterial && !material.isHidden, "the window backdrop draws its native material by default")
        root.drawsMaterial = false
        check(material.isHidden, "a Library card's theme omits the behind-window material")
        check(root.subviews.compactMap { $0 as? MTKView }.allSatisfy { !$0.isHidden }, "a card without material still paints its theme colors")
        root.drawsMaterial = true
        check(!material.isHidden, "restoring the material shows the native backdrop again")
        root.theme = SpaceTheme()
        check(!material.isHidden && material.material.rawValue == 2, "removing final color restores native backing")
        check(root.subviews.compactMap { $0 as? MTKView }.allSatisfy(\.isHidden), "empty theme retires color/texture canvas")
        var invalid = darkTheme; invalid.intensity = .nan
        root.theme = invalid
        check(root.subviews.compactMap { $0 as? MTKView }.allSatisfy(\.isHidden), "malformed theme never reaches Metal")

        let child = ActivityWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        child.isReleasedWhenClosed = false
        window.addChildWindow(child, ordered: .above)
        check(!ThemeWindowActivity.isActive(child), "inactive ownership chain is dimmed")
        window.reportsMain = true
        check(ThemeWindowActivity.isActive(window) && ThemeWindowActivity.isActive(child), "main original window and descendants remain active with editor child")
        window.reportsMain = false; child.reportsKey = true
        check(ThemeWindowActivity.isActive(child), "key child is active")
        check(!ThemeWindowActivity.isActive(window), "unrelated descendant activity is not promoted to parent")
        check(ThemeWindowActivity.contains(window, in: child), "parent activation notification targets the child surface")
        check(!ThemeWindowActivity.contains(child, in: window), "unrelated activation does not redraw owner")
        window.removeChildWindow(child)
        check(!ThemeWindowActivity.contains(window, in: child), "reparented surface drops previous owner")
        check(!ThemeWindowActivity.isActive(nil), "detached renderer has no active owner")

        let canvas = root.subviews.compactMap { $0 as? MTKView }.first!
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        func settleCanvas() {
            canvas.draw(canvas.bounds)
            canvas.needsDisplay = false
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        root.theme = darkTheme
        settleCanvas()
        let zeroNoiseBefore = root.canvasActivityDisplayInvalidations
        window.reportsKey = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        check(root.canvasActivityDisplayInvalidations == zeroNoiseBefore,
              "zero-noise theme skips activity needsDisplay because Metal never samples isActive")
        window.reportsKey = false

        var noisy = darkTheme; noisy.noise = 0.5
        root.theme = noisy
        settleCanvas()
        let noisyBefore = root.canvasActivityDisplayInvalidations
        window.reportsKey = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        check(root.canvasActivityDisplayInvalidations == noisyBefore + 1,
              "noisy theme dirties the canvas when key flips isActive")
        settleCanvas()
        window.reportsMain = true
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: window)
        check(root.canvasActivityDisplayInvalidations == noisyBefore + 1,
              "becomeMain while already key leaves isActive unchanged and skips needsDisplay")

        window.reportsKey = false; window.reportsMain = false
        settleCanvas()
        let sameTurnBefore = root.canvasActivityDisplayInvalidations
        window.reportsKey = true; window.reportsMain = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: window)
        check(root.canvasActivityDisplayInvalidations == sameTurnBefore + 1,
              "paired becomeKey/becomeMain only invalidates once while needsDisplay is already set")

        settleCanvas()
        window.reportsKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(root.canvasActivityDisplayInvalidations == sameTurnBefore + 1,
              "resign key while main keeps isActive and skips needsDisplay")
        window.reportsMain = false
        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: window)
        check(root.canvasActivityDisplayInvalidations == sameTurnBefore + 2,
              "resign main after key resign flips isActive and dirties")
        let themeBefore = root.canvasActivityDisplayInvalidations
        root.theme = lightTheme
        check(root.canvasActivityDisplayInvalidations == themeBefore && !root.palette.isDark,
              "theme refresh still republishes palette without using the activity invalidation path")
        window.orderOut(nil)

        let size = NSSize(width: 800, height: 400)
        var theme = darkTheme; theme.intensity = 0
        var config = ThemeGradientUniforms(theme: theme, backgroundIsDark: false, pointSize: size)
        check(near(config.parameters.x, 0.2) && near(config.underlay.w, 0.2), "minimum intensity retains measured color and underlay alpha")
        check(config.underlay.x == 1 && config.baseStartEnd == SIMD4(0, 0.25, 1, 0.75), "light underlay and continuous full-window gradient coordinates")
        theme.intensity = 1
        config = ThemeGradientUniforms(theme: theme, backgroundIsDark: true, pointSize: size)
        check(near(config.parameters.x, 0.75) && near(config.underlay.w, 0.175) && config.underlay.x == 0,
              "dark native backing uses capped black underlay independently of text")
        for count in 1...3 {
            theme.colorCount = count
            config = ThemeGradientUniforms(theme: theme, backgroundIsDark: false, pointSize: size)
            check(config.parameters.y == Float(min(count, 2)), "base color count is bounded at two")
            check(config.parameters.z == (count == 3 ? 2 : 0), "third color supplies the separate overlay")
            if count == 3 { check(config.overlay0.w == 0 && config.overlay1.w == 1, "overlay endpoints preserve transparent color") }
        }
        theme.noise = 0.5
        for (texture, maximum): (SpaceTheme.Texture, Float) in [(.grain, 0.8), (.sand, 0.15), (.denim, 0.6), (.tweed, 0.4)] {
            theme.texture = texture
            let full = SIMD4<Float>(0, 0, 1, 1), crop = SIMD4<Float>(0, 0, 0.3, 1)
            let active = ThemeOutputUniforms(theme: theme, isActive: true, pointSize: size, sampleRect: crop, hasTexture: true)
            let inactive = ThemeOutputUniforms(theme: theme, isActive: false, pointSize: size, sampleRect: full, hasTexture: true)
            check(near(active.parameters.z, maximum / 2) && near(inactive.parameters.z, maximum / 8), "texture strength follows active ownership with measured maxima")
            check(active.sampleRect == crop && active.parameters.x == 8 && active.parameters.y == 4, "floating surface samples the same full-window texture coordinates")
        }
        check(ThemeOutputUniforms(theme: theme, isActive: true, pointSize: size, sampleRect: SIMD4(0, 0, 1, 1), hasTexture: false).parameters.w == 0,
              "unavailable texture leaves real gradient visible")
        checkGrainComposite { check($0, $1) }
        checkPagingMaterial { check($0, $1) }
        checkEditorPresentation { check($0, $1) }
        checkTooltipTheme { check($0, $1) }

        let handle = CALayer(); handle.position = CGPoint(x: 10, y: 10)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 100, y: 20), scale: 1.1, animatePosition: true, allowsMotion: true)
        let position = handle.animation(forKey: "position") as! CASpringAnimation
        let hover = handle.animation(forKey: "hover") as! CASpringAnimation
        check(abs(position.stiffness - pow(2 * .pi / 0.28, 2)) < 0.001, "position spring uses recovered response")
        check(abs(position.damping - 2 * 0.63 * (2 * .pi / 0.28)) < 0.001, "position spring uses recovered damping")
        check(abs(hover.damping - 2 * 0.9 * (2 * .pi / 0.25)) < 0.001, "hover spring uses recovered timing")
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 100, y: 20), scale: 1.1, animatePosition: true, allowsMotion: true)
        check((handle.animation(forKey: "position") as? CASpringAnimation)?.fromValue as? NSValue == NSValue(point: CGPoint(x: 10, y: 10)),
              "unchanged redraw retains the original spring instead of restarting at its model target")
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 110, y: 20), scale: 1.1, animatePosition: false, allowsMotion: true)
        check(handle.animation(forKey: "position") == nil && handle.position.x == 110, "direct input cancels stale spring before displaying current pointer")
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 20, y: 20), scale: 1, animatePosition: true, allowsMotion: true)
        check((handle.animation(forKey: "position") as? CASpringAnimation)?.fromValue as? NSValue == NSValue(point: CGPoint(x: 110, y: 20)),
              "reversal starts at current model when no presentation tree exists")
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 30, y: 30), scale: 1, animatePosition: true, allowsMotion: false)
        check(handle.animationKeys()?.isEmpty != false && handle.position == CGPoint(x: 30, y: 30), "Reduce Motion or retirement settles both animations at the authoritative target")
        ThemeColorPadMotion.update(handle, position: .zero, scale: 1, animatePosition: false, allowsMotion: true)
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 30, y: 30), scale: 1, animatePosition: true, allowsMotion: true)
        check((handle.animation(forKey: "position") as? CASpringAnimation)?.fromValue as? NSValue == NSValue(point: .zero),
              "an existing knob at the pad corner remains a valid spring origin")
        CATransaction.commit()
        window.contentView = nil
        check(root.window == nil && nested.window == nil, "physical renderer tree detaches without changing content ownership")

        let editorView = SpaceThemeEditorView(theme: darkTheme, performHapticFeedback: {})
        window.contentView = editorView
        editorView.layoutSubtreeIfNeeded()
        let pad = editorView.subviews.first { $0.accessibilityLabel() == "Theme color pad" }!
        let knob = pad.layer!.sublayers!.first { layer in
            !pad.subviews.contains { $0.layer === layer } && layer.sublayers?.isEmpty == false
        }!.sublayers!.first!
        check(knob.animationKeys()?.isEmpty != false, "initial physical pad layout places its knob without a spring")
        func inheritedMotion(_ key: String) {
            let animation = CABasicAnimation(keyPath: key == "position" ? "position" : "transform.scale")
            animation.duration = 1
            knob.add(animation, forKey: key)
        }
        inheritedMotion("position")
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: pad.convert(knob.position, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        pad.mouseDown(with: mouse(.leftMouseDown))
        check(knob.animation(forKey: "position") == nil, "production pad's admitted direct start retires inherited positional motion")
        pad.mouseUp(with: mouse(.leftMouseUp))
        inheritedMotion("position"); inheritedMotion("hover")
        window.contentView = nil
        check(knob.animationKeys()?.isEmpty != false, "production editor detachment retires all pending knob motion")
        NSCursor.arrow.set()
        print("Space theme rendering: \(assertions) assertions passed")
    }
}
