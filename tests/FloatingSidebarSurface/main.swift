import AppKit
import MetalKit

@MainActor @main struct FloatingSidebarSurfaceChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("FloatingSidebarSurface: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.002) -> Bool { abs(a - b) <= e }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)

        check(FloatingSidebarSurface.cornerRadius == 8, "updateLayer's and the blur masks' radius is 10 − 2")
        check(FloatingSidebarSurface.borderWidth == 1, "a 1-point edge")
        let border = NSColor(cgColor: FloatingSidebarSurface.borderColor)?.usingColorSpace(.sRGB)
        check(border.map { near($0.redComponent, 1) && near($0.greenComponent, 1) && near($0.blueComponent, 1) && near($0.alphaComponent, 0.3) } == true,
              "SidebarBorderColor is sRGB white at 0.3")
        check(FloatingSidebarSurface.shadowAlpha == 0.2 && FloatingSidebarSurface.shadowOutset == 10, "shadowView at 0.2, pinned 10 points out")

        guard let shadowImage = FloatingSidebarSurface.shadowImage else { fatalError("FloatingSidebarSurface: CellDropShadow loads from the bundle") }
        check(shadowImage.size == NSSize(width: 40, height: 40), "40-point image")
        let caps = shadowImage.capInsets
        check(caps.top == 19 && caps.left == 19 && caps.bottom == 20 && caps.right == 20, "the catalog's cap insets")
        let bitmaps = shadowImage.representations.compactMap { $0 as? NSBitmapImageRep }
        check(bitmaps.map(\.pixelsWide).sorted() == [40, 80] && bitmaps.allSatisfy { $0.size == NSSize(width: 40, height: 40) },
              "both renditions at the 1× point size")
        check(FloatingSidebarSurface.shadowImage === shadowImage, "the image is built once")
        if let base = bitmaps.first(where: { $0.pixelsWide == 40 }) {
            func alpha(_ x: Int, _ y: Int) -> CGFloat { base.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
            check(alpha(0, 20) < 0.01 && alpha(20, 20) < 0.01, "a ring: clear outside and in its hole")
            check(alpha(9, 20) > 0.35 && alpha(9, 20) < 0.4, "about 0.37 alpha at the hole's edge")
        }

        check(FloatingSidebarSurface.mask(radius: 0) == nil, "square corners need no mask")
        guard let mask = FloatingSidebarSurface.mask(radius: 8) else { fatalError("FloatingSidebarSurface: radius-8 mask") }
        check(mask.size == NSSize(width: 17, height: 17) && mask.resizingMode == .stretch
              && mask.capInsets.top == 8 && mask.capInsets.left == 8 && mask.capInsets.bottom == 8 && mask.capInsets.right == 8,
              "a 17-point square stretched from 8-point caps")
        let maskBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 17, pixelsHigh: 17, bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: maskBitmap)
        mask.draw(in: NSRect(x: 0, y: 0, width: 17, height: 17))
        NSGraphicsContext.restoreGraphicsState()
        check((maskBitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05 && (maskBitmap.colorAt(x: 8, y: 8)?.alphaComponent ?? 0) > 0.99,
              "rounded corners, opaque middle")

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        root.wantsLayer = true
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        let page = NSView(frame: root.bounds)
        page.wantsLayer = true
        root.addSubview(page)
        let container = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 390))
        root.addSubview(container)
        container.coordinateSpace = root
        container.theme = .singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)
        let sidebar = NSView(frame: container.bounds)
        container.addSubview(sidebar)
        func material() -> NSVisualEffectView { container.subviews.compactMap { $0 as? NSVisualEffectView }.first! }
        func canvas() -> MTKView? { container.subviews.compactMap { $0 as? MTKView }.first }
        func shadows() -> [FloatingSidebarShadowView] { container.subviews.compactMap { $0 as? FloatingSidebarShadowView } }
        let windowMaterial = material().material
        check(material().blendingMode == .behindWindow && shadows().isEmpty && container.layer?.borderWidth == 0,
              "the window's own surface: behind-window material, no shadow or edge")

        container.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        check(material().blendingMode == .withinWindow && material().material == .popover && material().isEmphasized,
              "blurView: within-window popover, emphasized")
        check(material().maskImage.map { $0.size == NSSize(width: 17, height: 17) && $0.capInsets.left == 8 } == true, "the blur is masked to radius 8")
        if let canvas = canvas() { check(canvas.layer?.cornerRadius == 8 && canvas.clipsToBounds, "the theme rounds to radius 8") }
        check(container.layer?.cornerRadius == 8 && container.layer?.borderWidth == 1
              && container.layer?.borderColor == FloatingSidebarSurface.borderColor, "the surface's own rounded 1-point edge")
        check(!container.clipsToBounds && container.layer?.masksToBounds == false, "AppKit's corner-radius clip is undone, so the shadow shows")
        guard let shadow = shadows().first, shadows().count == 1 else { fatalError("FloatingSidebarSurface: one shadow") }
        check(container.subviews.first === shadow, "the shadow lies under the material and the theme")
        check(shadow.frame == container.bounds.insetBy(dx: -10, dy: -10), "10 points past the surface on every side")
        check(shadow.alphaValue == 0.2 && !shadow.isHidden && shadow.image === shadowImage, "CellDropShadow at 0.2")
        check(shadow.hitTest(NSPoint(x: 50, y: 50)) == nil && !shadow.isAccessibilityElement(), "no click or accessibility element")
        container.frame = NSRect(x: 5, y: 5, width: 240, height: 380)
        check(shadow.frame == container.bounds.insetBy(dx: -10, dy: -10), "the shadow follows the surface's size")
        container.theme = .singleColor(ThemeColor(red: 0.2, green: 0.6, blue: 0.4)!)
        check(material().blendingMode == .withinWindow && material().material == .popover, "a theme change keeps the floating material")

        container.drawsBackground = false
        func render() -> NSBitmapImageRep {
            root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            context.translateBy(x: 0, y: 400); context.scaleBy(x: 1, y: -1)
            root.layer!.render(in: context)
            return rep
        }
        func white(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceGray)?.whiteComponent ?? -1 }
        let edge = Int(container.frame.maxX), middle = Int(container.frame.midY)
        page.layer?.backgroundColor = NSColor.white.cgColor
        let light = render()
        let center = shadow.layer?.contentsCenter ?? .zero
        check(shadow.layer?.contents != nil && shadow.layer?.contentsGravity == .resize
              && near(center.minX, 19.0 / 40) && near(center.minY, 20.0 / 40) && near(center.width, 1.0 / 40) && near(center.height, 1.0 / 40),
              "the artwork stretches from its cap insets, axes independently")
        check(white(light, edge, middle) < 0.95 && white(light, edge + 15, middle) > 0.99, "the shadow darkens just outside, not 15 points out")
        page.layer?.backgroundColor = NSColor.black.cgColor
        let dark = render()
        check(white(dark, edge - 1, middle) > 0.2 && white(dark, edge - 3, middle) < 0.02, "a light 1-point edge just inside")
        container.drawsBackground = true

        container.theme = SpaceTheme()
        container.pagingTransition = ThemePagingTransition(from: SpaceTheme(), theme: .singleColor(ThemeColor(red: 0.9, green: 0.4, blue: 0.2)!),
                                                           progress: 0.4)
        if let canvas = canvas() { check(!canvas.isHidden, "the canvas draws a swipe into a coloured Space") }
        container.pagingTransition = nil
        if let canvas = canvas() { check(canvas.isHidden, "an uncoloured Space at rest draws no canvas") }
        container.theme = .singleColor(ThemeColor(red: 0.2, green: 0.6, blue: 0.4)!)
        checkSwipeCommit(floating: true)
        checkSwipeCommit(floating: false)
        checkSwipeMaterial()

        func materials() -> [NSVisualEffectView] { container.subviews.compactMap { $0 as? NSVisualEffectView } }
        check(materials().count == 1, "no dock material before the first dock")
        container.preparesFloatingDock = true
        guard materials().count == 2, let blurIndex = container.subviews.firstIndex(of: material()) else {
            fatalError("FloatingSidebarSurface: the dock's preparation adds behindWindowBlurView")
        }
        let dock = materials()[1]
        check(container.subviews.firstIndex(of: dock) == blurIndex + 1
              && canvas().map { container.subviews.firstIndex(of: $0)! > blurIndex + 1 } != false,
              "the dock material lies over the blur and under the theme")
        let side: NSAppearance.Name = container.surfaceStyle.backgroundIsDark ? .darkAqua : .aqua
        check(dock.blendingMode == .behindWindow && dock.isEmphasized && dock.material == windowMaterial && dock.appearance?.name == side
              && dock.maskImage.map { $0.size == NSSize(width: 17, height: 17) && $0.capInsets.left == 8 } == true,
              "behindWindowBlurView: the window surface's behind-window material and side, emphasized and masked to radius 8")
        check(!dock.isHidden && dock.alphaValue == 0 && material().alphaValue == 1 && shadow.alphaValue == 0.2,
              "prepared: unhidden at 0, with the blur and shadow untouched")
        check(dock.hitTest(NSPoint(x: 50, y: 50)) == nil && !dock.isAccessibilityElement(), "the dock material passes clicks through")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            context.allowsImplicitAnimation = true
            container.docksFloatingSurface = true
        }
        check(container.layer?.cornerRadius == 8 && material().maskImage != nil && container.layer?.borderWidth == 1
              && material().blendingMode == .withinWindow && canvas().map { $0.layer?.cornerRadius == 8 } != false,
              "the corners, mask, edge and blur stay through the slide")
        check(shadow.alphaValue == 0 && !shadow.isHidden, "the shadow fades out")
        check(material().alphaValue == 0 && dock.alphaValue == 1 && !dock.isHidden, "the blur fades out and the window's material in")
        for (view, name) in [(shadow as NSView, "shadow"), (material(), "blur"), (dock, "dock material")] {
            let fade = view.layer?.animation(forKey: "opacity") as? CABasicAnimation
            check(fade.map { near($0.duration, 0.08, 1e-6) } == true, "the \(name) fades on the group's 0.08 s timing")
        }
        container.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        container.docksFloatingSurface = true
        container.preparesFloatingDock = false
        check(shadow.alphaValue == 0 && container.layer?.cornerRadius == 8, "a full pass mid-dock keeps the faded shadow")
        check(material().alphaValue == 0 && dock.alphaValue == 1 && !dock.isHidden, "and keeps the cross-faded materials")

        container.docksFloatingSurface = false
        check(shadow.alphaValue == 0.2 && !shadow.isHidden && container.layer?.cornerRadius == 8 && material().maskImage != nil,
              "a reversed dock floats with its shadow, corners and mask")
        check(material().alphaValue == 1 && dock.isHidden && dock.alphaValue == 0, "a reversed dock shows the blur and hides the dock material")
        check([shadow as NSView, material(), dock].allSatisfy { $0.layer?.animation(forKey: "opacity") == nil },
              "a reversed dock leaves no fade in flight")
        container.docksFloatingSurface = true

        container.floatingCornerRadius = nil
        container.docksFloatingSurface = false
        check(material().blendingMode == .behindWindow && material().material == windowMaterial && material().maskImage == nil,
              "the window's own material again")
        check(material().alphaValue == 1 && dock.isHidden && dock.alphaValue == 0, "the settled dock restores the blur's alpha and hides the dock material")
        check(container.layer?.borderWidth == 0 && container.layer?.borderColor == nil && container.layer?.cornerRadius == 0, "no edge or corners")
        if let canvas = canvas() { check(!canvas.clipsToBounds && canvas.layer?.cornerRadius == 0, "the theme is square and unclipped") }
        check(shadow.isHidden && shadow.alphaValue == 0.2, "the shadow hides and is ready for the next float")
        check(!container.clipsToBounds && container.layer?.masksToBounds == false, "a settled surface stays unclipped")
        container.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        check(shadows().count == 1 && shadows().first === shadow && !shadow.isHidden && shadow.alphaValue == 0.2, "floating again reuses it")
        check(materials().count == 2 && materials()[1] === dock && dock.isHidden && material().alphaValue == 1,
              "floating again keeps the dock material hidden for the next dock")

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        content.wantsLayer = true
        root.addSubview(content)
        for floating in [true, false, true, false] {
            content.layer?.cornerRadius = floating ? FloatingSidebarSurface.cornerRadius : 0
            content.clipsToBounds = floating
            check(content.layer?.masksToBounds == floating && content.layer?.cornerRadius == (floating ? 8 : 0),
                  floating ? "a floating sidebar clips to the rounded surface" : "a locked sidebar stays unclipped")
        }
        window.contentView = nil
        print("FloatingSidebarSurface checks passed: \(count)")
    }

    static func checkSwipeCommit(floating: Bool) {
        let width = 128, height = 96, surfaceName = floating ? "floating surface" : "window surface"
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        let surface = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = surface; window.orderFront(nil); surface.layout()
        if floating { surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius }
        defer { window.orderOut(nil); window.contentView = nil }
        guard let canvas = surface.subviews.compactMap({ $0 as? MTKView }).first, let device = canvas.device,
              let queue = device.makeCommandQueue() else { print("FloatingSidebarSurface: no Metal; swipe commit not rendered"); return }
        canvas.framebufferOnly = false; canvas.autoResizeDrawable = false
        canvas.drawableSize = CGSize(width: width, height: height)
        func render(_ theme: SpaceTheme, _ transition: ThemePagingTransition?) -> [Int] {
            surface.theme = theme; surface.pagingTransition = transition
            canvas.releaseDrawables()
            guard let drawable = canvas.currentDrawable else { return [] }
            canvas.draw(canvas.bounds); canvas.needsDisplay = false
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let texture = drawable.texture, length = texture.width * texture.height * 4
            let buffer = device.makeBuffer(length: length, options: .storageModeShared)!
            let command = queue.makeCommandBuffer()!, blit = command.makeBlitCommandEncoder()!
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                      to: buffer, destinationOffset: 0, destinationBytesPerRow: texture.width * 4, destinationBytesPerImage: length)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
            return (0..<length).map { Int(bytes[$0]) }
        }
        func largest(_ a: [Int], _ b: [Int]) -> Int { a.count == b.count && !a.isEmpty ? zip(a, b).map { abs($0 - $1) }.max()! : .max }
        func over(_ source: [Int], opacity: Double, _ backdrop: [Int]) -> [Int] {
            (0..<source.count).map { index in
                let alpha = Double(source[index - index % 4 + 3]) * opacity / 255
                return Int((Double(source[index]) * opacity + Double(backdrop[index]) * (1 - alpha)).rounded())
            }
        }
        var current = SpaceTheme(primaryColor: ThemeColor(red: 0.85, green: 0.25, blue: 0.3)!, colorCount: 2, intensity: 0.3)
        current.noise = 0.6
        var incoming = SpaceTheme(primaryColor: ThemeColor(red: 0.15, green: 0.35, blue: 0.9)!, colorCount: 1, intensity: 1)
        incoming.noise = 0.25; incoming.texture = .tweed; incoming.appearance = .dark
        _ = render(current, nil)
        let alone = render(current, nil), other = render(incoming, nil)
        let p: CGFloat = 0.37
        func across(_ from: SpaceTheme, _ to: SpaceTheme, _ progress: CGFloat) -> ThemePagingTransition {
            ThemePagingTransition(from: from, theme: to, progress: progress)
        }
        let swipe = across(current, incoming, p)
        let before = render(current, swipe), after = render(incoming, swipe)
        check(largest(before, after) <= 1, "a mid-swipe commit leaves the \(surfaceName)'s picture unchanged (\(largest(before, after)) levels)")
        let pastOnePage = render(SpaceTheme(), swipe)
        check(largest(pastOnePage, before) <= 1,
              "past one page, neither page the surface's own, the same picture (\(largest(pastOnePage, before)) levels)")
        check(largest(render(current, across(current, incoming, 0)), alone) <= 1
              && largest(render(incoming, across(current, incoming, 1)), other) <= 1, "the swipe's ends are each theme alone")
        var plainCurrent = current, plainIncoming = incoming
        plainCurrent.noise = 0; plainIncoming.noise = 0
        let a = render(plainCurrent, nil), b = render(plainIncoming, nil)
        let mixed = render(plainCurrent, across(plainCurrent, plainIncoming, p))
        let expected = (0..<a.count).map { index -> Int in
            let base = index - index % 4
            let alphaA = Double(a[base + 3]) / 255, alphaB = Double(b[base + 3]) / 255
            let alpha = alphaA * (1 - p) + alphaB * p
            if index % 4 == 3 { return Int((alpha * 255).rounded()) }
            let straightA = alphaA > 0 ? Double(a[index]) / alphaA : 0, straightB = alphaB > 0 ? Double(b[index]) / alphaB : 0
            return Int(((straightA * (1 - p) + straightB * p) * alpha).rounded())
        }
        let crossfade = (0..<a.count).map { Int((Double(a[$0]) * (1 - p) + Double(b[$0]) * p).rounded()) }
        check(largest(mixed, expected) <= 2, "the \(surfaceName) mixes both themes' straight layers (\(largest(mixed, expected)) levels)")
        check(largest(mixed, crossfade) >= 4, "which is not a crossfade of the two pictures (\(largest(mixed, crossfade)) levels apart)")
        let uncoloured = render(current, across(current, SpaceTheme(), 1))
        check(!uncoloured.isEmpty && uncoloured.allSatisfy { $0 == 0 }, "a swipe's end in an uncoloured Space clears the canvas")
        let arrived = render(SpaceTheme(), across(SpaceTheme(), current, 1))
        check(largest(arrived, alone) <= 1, "a swipe from an uncoloured Space ends on the incoming gradient as it rests (\(largest(arrived, alone)) levels)")
        let fromUncoloured = across(SpaceTheme(), current, p), toUncoloured = across(current, SpaceTheme(), 1 - p)
        let leftBefore = render(SpaceTheme(), fromUncoloured), leftAfter = render(current, fromUncoloured)
        let rightBefore = render(current, toUncoloured), rightAfter = render(SpaceTheme(), toUncoloured)
        check(largest(leftBefore, leftAfter) <= 1 && largest(rightBefore, rightAfter) <= 1,
              "a mid-swipe commit with an uncoloured Space leaves the picture unchanged "
              + "(\(max(largest(leftBefore, leftAfter), largest(rightBefore, rightAfter))) levels)")
        check(largest(leftBefore, rightBefore) <= 1,
              "an uncoloured Space fades the theme the same from either side (\(largest(leftBefore, rightBefore)) levels)")
        let fading = render(plainCurrent, across(plainCurrent, SpaceTheme(), p))
        let faded = a.map { Int((Double($0) * (1 - p)).rounded()) }
        check(largest(fading, faded) <= 1, "towards an uncoloured Space the theme fades as a whole (\(largest(fading, faded)) levels)")
        let backdrop = (0..<alone.count).map { $0 % 4 == 3 ? 255 : 200 }
        let stackedBefore = over(other, opacity: p, over(alone, opacity: 1, backdrop))
        let stackedAfter = over(alone, opacity: 1 - p, over(other, opacity: 1, backdrop))
        check(largest(over(before, opacity: 1, backdrop), over(after, opacity: 1, backdrop)) <= 1 && largest(stackedBefore, stackedAfter) > 8,
              "control: a second translucent canvas stacked over the first jumps \(largest(stackedBefore, stackedAfter)) levels at the commit")
        print("FloatingSidebarSurface \(surfaceName) swipe commit at p = \(p): \(largest(before, after)) levels across it,"
              + " \(largest(mixed, expected)) from the expected mix, \(largest(mixed, crossfade)) from a crossfade;"
              + " the stacked canvas jumped \(largest(stackedBefore, stackedAfter))")
    }

    static func checkSwipeMaterial() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        window.contentView = root
        defer { window.contentView = nil }
        let surface = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 290))
        root.addSubview(surface)
        var light = SpaceTheme.singleColor(ThemeColor(red: 0.8, green: 0.88, blue: 0.97)!); light.appearance = .light
        var dark = SpaceTheme.singleColor(ThemeColor(red: 0.36, green: 0.22, blue: 0.62)!); dark.appearance = .dark
        var uncoloured = SpaceTheme(); uncoloured.appearance = .dark
        func side(_ appearance: NSAppearance) -> NSAppearance.Name? { appearance.bestMatch(from: [.aqua, .darkAqua]) }
        struct Material: Equatable {
            var kind: NSVisualEffectView.Material, withinWindow: Bool, alpha: CGFloat, hidden: Bool, side: NSAppearance.Name?
        }
        func materials() -> [Material] {
            surface.subviews.compactMap { $0 as? NSVisualEffectView }.map {
                Material(kind: $0.material, withinWindow: $0.blendingMode == .withinWindow, alpha: $0.alphaValue,
                         hidden: $0.isHidden, side: side($0.effectiveAppearance))
            }
        }
        func until(_ done: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !done(), Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        }
        surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        surface.theme = uncoloured
        check(materials().map(\.side) == [.darkAqua], "an uncoloured dark-style Space's blur, its whole backdrop, stays dark in an Aqua window")
        guard surface.subviews.contains(where: { $0 is MTKView }) else {
            print("FloatingSidebarSurface: no Metal; the blur is the whole backdrop, so the swipe's blur is not checked"); return
        }
        surface.theme = light
        let rest = materials()
        check(rest == [Material(kind: .popover, withinWindow: true, alpha: 1, hidden: false, side: .aqua)],
              "one floating blur, in the window's appearance")
        func across(_ from: SpaceTheme, _ to: SpaceTheme, _ p: CGFloat) -> ThemePagingTransition {
            ThemePagingTransition(from: from, theme: to, progress: p)
        }
        let swipe: [(SpaceTheme, ThemePagingTransition?)] = [
            (light, across(light, dark, 0.25)), (light, across(light, dark, 0.6)),
            (dark, across(light, dark, 0.6)), (dark, across(light, dark, 0.9)), (dark, nil),
        ]
        for (theme, transition) in swipe {
            surface.theme = theme; surface.pagingTransition = transition
            check(materials() == rest, "a light ↔ dark swipe leaves the floating blur as it was "
                  + "(p \(transition?.progress ?? 1), \(theme == light ? "before" : "after") the commit)")
        }
        check(surface.palette.contentAppearance.flatMap(side) == .darkAqua, "palette: the dark-style Space's text still takes Dark Aqua")
        window.appearance = NSAppearance(named: .darkAqua)
        check(materials().map(\.side) == [.darkAqua], "the floating blur follows the window's own appearance")
        surface.floatingCornerRadius = nil
        surface.theme = light
        check(materials().map(\.side) == [.aqua] && materials().first?.kind.rawValue == 1,
              "a locked surface's material keeps its light theme's side in a Dark Aqua window")
        surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        check(materials().map(\.side) == [.darkAqua] && materials().first?.kind == .popover, "floating again resolves against the window")
        window.appearance = nil
        guard let inherited = side(window.effectiveAppearance) else { fatalError("FloatingSidebarSurface: an Aqua or Dark Aqua window") }
        let flipped: NSAppearance.Name = inherited == .darkAqua ? .aqua : .darkAqua
        check(materials().map(\.side) == [inherited], "the floating blur takes the appearance the window inherits")
        NSApp.appearance = NSAppearance(named: flipped)
        until { side(window.effectiveAppearance) == flipped }
        check(materials().map(\.side) == [flipped], "the floating blur follows an app appearance change the window inherits")
        NSApp.appearance = nil
        until { side(window.effectiveAppearance) == inherited }
        check(materials().map(\.side) == [inherited], "and follows it back")
        let automatic = SpaceTheme.singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)
        let names: [(SpaceTheme, ThemePagingTransition?)] = [
            (automatic, nil), (automatic, across(automatic, SpaceTheme(), 0.6)),
            (SpaceTheme(), across(automatic, SpaceTheme(), 0.6)), (SpaceTheme(), nil),
        ]
        for (theme, transition) in names {
            surface.theme = theme; surface.pagingTransition = transition
            check(surface.subviews.compactMap { ($0 as? NSVisualEffectView)?.effectiveAppearance.name } == [window.effectiveAppearance.name],
                  "a coloured ↔ uncoloured automatic swipe keeps the window's own appearance "
                  + "(p \(transition?.progress ?? 1), \(theme == automatic ? "before" : "after") the commit)")
        }
    }
}
