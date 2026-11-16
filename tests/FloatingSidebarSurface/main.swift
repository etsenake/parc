import AppKit
import MetalKit

@MainActor @main struct FloatingSidebarSurfaceChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("FloatingSidebarSurface: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.002) -> Bool { abs(a - b) <= e }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
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
        check(caps.top == 19 && caps.left == 19 && caps.bottom == 20 && caps.right == 20, "the cap insets")
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
        checkPagingBlend()
        checkSwipeDock()

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
        var alsoLight = SpaceTheme.singleColor(ThemeColor(red: 0.95, green: 0.8, blue: 0.6)!); alsoLight.appearance = .light
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
        func shown() -> [Material] { materials().filter { !$0.hidden } }
        func until(_ done: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !done(), Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        }
        func blur(_ alpha: CGFloat, _ side: NSAppearance.Name) -> Material {
            Material(kind: .popover, withinWindow: true, alpha: alpha, hidden: false, side: side)
        }
        surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        surface.theme = uncoloured
        check(materials().map(\.side) == [.darkAqua], "an uncoloured dark-style Space's blur, its whole backdrop, stays dark in an Aqua window")
        guard surface.subviews.contains(where: { $0 is MTKView }) else {
            print("FloatingSidebarSurface: no Metal; the blur is the whole backdrop, so the swipe's blur is not checked"); return
        }
        surface.theme = dark
        check(materials() == [blur(1, .darkAqua)], "a coloured Space forced Dark keeps a dark blur in an Aqua window")
        check(surface.palette.contentAppearance.flatMap(side) == .darkAqua, "and its text takes Dark Aqua, so text and blur agree")
        surface.theme = light
        check(materials() == [blur(1, .aqua)], "one floating blur on the light side of a Space forced Light")

        func across(_ from: SpaceTheme, _ to: SpaceTheme, _ p: CGFloat) -> ThemePagingTransition {
            ThemePagingTransition(from: from, theme: to, progress: p)
        }
        surface.pagingTransition = across(light, alsoLight, 0.5)
        check(shown() == [blur(1, .aqua)], "a swipe between two light-side Spaces adds no second blur")
        surface.pagingTransition = across(light, dark, 0.3)
        let blurs = surface.subviews.compactMap { $0 as? NSVisualEffectView }
        guard blurs.count == 2 else { fatalError("FloatingSidebarSurface: a light ↔ dark swipe adds the floating crossfade") }
        let base = blurs[0], crossfade = blurs[1]
        check(surface.subviews.firstIndex(of: crossfade) == surface.subviews.firstIndex(of: base).map { $0 + 1 }
              && surface.subviews.firstIndex { $0 is MTKView }.map { $0 > surface.subviews.firstIndex(of: crossfade)! } == true,
              "the crossfade blur lies just above the floating blur and under the theme")
        check(crossfade.state == .followsWindowActiveState && crossfade.isEmphasized
              && crossfade.maskImage.map { $0.size == NSSize(width: 17, height: 17) && $0.capInsets.left == 8 } == true,
              "the crossfade is the floating blur's twin: emphasized, following the window's state, masked to radius 8")
        check(crossfade.hitTest(NSPoint(x: 50, y: 50)) == nil, "the crossfade passes clicks through")
        surface.setFrameSize(NSSize(width: 180, height: 270))
        surface.layout()
        check(crossfade.frame == surface.bounds && base.frame == surface.bounds, "it follows the surface's size")
        surface.setFrameSize(NSSize(width: 200, height: 290))
        surface.layout()
        for progress: CGFloat in [0, 0.3, 0.6, 0.9, 0.95, 1] {
            let blend = FloatingSidebarSurface.pagingBlend(progress: progress)
            let expected = [blur(blend.base, .aqua), blur(blend.incoming, .darkAqua)]
            surface.theme = light; surface.pagingTransition = across(light, dark, progress)
            let before = materials()
            surface.theme = dark
            check(before == expected && materials() == expected,
                  "light → dark at \(progress): the left page's blur under the right page's, \(blend), unchanged by the commit")
        }
        surface.pagingTransition = nil
        check(shown() == [blur(1, .darkAqua)] && crossfade.isHidden, "at rest only the arrived Space's dark blur shows")
        surface.pagingTransition = across(dark, light, 0.3)
        check(materials() == [blur(1, .darkAqua), blur(FloatingSidebarSurface.pagingBlend(progress: 0.3).incoming, .aqua)],
              "dark → light: the dark page's blur is the base")
        func visible() -> [Material] {
            materials().filter { !$0.hidden && $0.alpha > 0 }.map { var m = $0; m.alpha = 1; return m }.suffix(1)
        }
        surface.pagingTransition = across(light, dark, 1)
        let leaving = visible()
        surface.pagingTransition = across(dark, alsoLight, 0)
        check(leaving == visible() && leaving == [blur(1, .darkAqua)],
              "dragging on past a page boundary hands over from a fully shown crossfade to the same blur as the base")
        surface.pagingTransition = across(uncoloured, light, 0.5)
        check(shown().count == 2 && shown()[0].side == .darkAqua && shown()[1].side == .aqua,
              "a forced uncoloured Space ↔ coloured Space swipe blends the two blurs")
        surface.pagingTransition = across(light, alsoLight, 0.95)
        check(shown() == [blur(1, .aqua)], "past 90% into a same-side Space the blur is whole again, with no crossfade")
        surface.pagingTransition = across(uncoloured, light, 0.95)
        let late = FloatingSidebarSurface.pagingBlend(progress: 0.95)
        check(materials() == [blur(late.base, .darkAqua), blur(late.incoming, .aqua)], "late in the swipe the base fades beneath the crossfade")
        surface.drawsMaterial = false
        check(crossfade.isHidden && base.alphaValue == 1, "a surface without material draws no crossfade and resets the blur")
        surface.drawsMaterial = true; surface.drawsBackground = false
        check(crossfade.isHidden && base.alphaValue == 1, "nor does a surface that draws no background")
        surface.drawsBackground = true; surface.incognito = true
        check(crossfade.isHidden && base.alphaValue == 1, "nor does a private window's surface")
        surface.incognito = false
        check(materials() == [blur(late.base, .darkAqua), blur(late.incoming, .aqua)], "restored with the surface's background and blend")
        surface.floatingCornerRadius = nil
        check(crossfade.isHidden && base.alphaValue == 1 && materials().first?.withinWindow == false,
              "a locked surface never shows the floating crossfade")
        surface.floatingCornerRadius = 12
        check(!crossfade.isHidden && crossfade.maskImage.map { $0.size == NSSize(width: 25, height: 25) && $0.capInsets.left == 12 } == true,
              "floating again restores it with the surface's current mask")
        surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        check(crossfade.maskImage.map { $0.size == NSSize(width: 17, height: 17) } == true, "and follows the radius back")
        surface.pagingTransition = nil

        surface.theme = dark
        window.appearance = NSAppearance(named: .darkAqua)
        check(shown() == [blur(1, .darkAqua)], "a forced Dark Space's blur in a Dark Aqua window")
        surface.floatingCornerRadius = nil
        surface.theme = light
        check(shown().map(\.side) == [.aqua] && shown().first?.kind.rawValue == 1,
              "a locked surface's material keeps its light theme's side in a Dark Aqua window")
        surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        check(shown() == [blur(1, .aqua)], "floating, a forced Light Space keeps a light blur in a Dark Aqua window")
        let automatic = SpaceTheme.singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)
        surface.theme = automatic
        check(shown().map(\.side) == [.darkAqua], "an automatic coloured Space's blur follows the Dark Aqua window")
        window.appearance = nil
        guard let inherited = side(window.effectiveAppearance) else { fatalError("FloatingSidebarSurface: an Aqua or Dark Aqua window") }
        let flipped: NSAppearance.Name = inherited == .darkAqua ? .aqua : .darkAqua
        check(shown().map(\.side) == [inherited], "the floating blur takes the appearance the window inherits")
        NSApp.appearance = NSAppearance(named: flipped)
        until { side(window.effectiveAppearance) == flipped }
        check(shown().map(\.side) == [flipped], "the floating blur follows an app appearance change the window inherits")
        NSApp.appearance = nil
        until { side(window.effectiveAppearance) == inherited }
        check(shown().map(\.side) == [inherited], "and follows it back")
        let names: [(SpaceTheme, ThemePagingTransition?)] = [
            (automatic, nil), (automatic, across(automatic, SpaceTheme(), 0.6)),
            (SpaceTheme(), across(automatic, SpaceTheme(), 0.6)), (SpaceTheme(), nil),
        ]
        for (theme, transition) in names {
            surface.theme = theme; surface.pagingTransition = transition
            check(surface.subviews.compactMap { $0 as? NSVisualEffectView }.filter { !$0.isHidden }.map(\.effectiveAppearance.name)
                    == [window.effectiveAppearance.name],
                  "a coloured ↔ uncoloured automatic swipe keeps the window's own appearance and one blur "
                  + "(p \(transition?.progress ?? 1), \(theme == automatic ? "before" : "after") the commit)")
        }
        window.appearance = NSAppearance(named: .aqua)
        surface.theme = automatic
        surface.pagingTransition = across(automatic, dark, 0.5)
        check(shown().map(\.side) == [.aqua, .darkAqua], "automatic → forced Dark in an Aqua window blends the two blurs")
        window.appearance = NSAppearance(named: .darkAqua)
        check(shown() == [blur(1, .darkAqua)], "turning the window Dark Aqua mid-swipe leaves one dark blur, as both pages now agree")
        window.appearance = NSAppearance(named: .aqua)
        check(shown().map(\.side) == [.aqua, .darkAqua], "and back to Aqua blends them again")
        surface.pagingTransition = nil
    }

    static func checkPagingBlend() {
        func blend(_ p: CGFloat) -> (CGFloat, CGFloat) { let b = FloatingSidebarSurface.pagingBlend(progress: p); return (b.base, b.incoming) }
        check(FloatingSidebarSurface.pagingOpaqueProgress == 0.9, "the crossfade is fully shown at 90% of the swipe")
        check(blend(0) == (1, 0) && blend(-0.2) == (1, 0), "at the start only the left page's blur shows")
        check(near(blend(0.45).0, 1) && near(blend(0.45).1, 0.5), "halfway to opaque the crossfade is at half")
        check(near(blend(0.9).0, 1) && near(blend(0.9).1, 1), "at 90% both blurs are fully shown, so the page never shows through")
        check(near(blend(0.95).0, 0.5) && near(blend(0.95).1, 1), "past it the base fades out beneath the opaque crossfade")
        check(blend(1) == (0, 1) && blend(1.3) == (0, 1), "at the end only the right page's blur remains, as it rests")
        var previous = blend(0)
        for step in 1...100 {
            let next = blend(CGFloat(step) / 100)
            check(next.0 <= previous.0 + 1e-9 && next.1 >= previous.1 - 1e-9 && abs(next.0 - previous.0) <= 0.11 && abs(next.1 - previous.1) <= 0.012,
                  "the blend moves steadily at \(step)%")
            check(next.0 >= 1 - 1e-9 || next.1 >= 1 - 1e-9, "one of the two blurs is always fully shown at \(step)%")
            previous = next
        }
    }

    static func checkSwipeDock() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        root.wantsLayer = true
        window.contentView = root
        defer { window.contentView = nil }
        let surface = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 290))
        root.addSubview(surface)
        guard surface.subviews.contains(where: { $0 is MTKView }) else { print("FloatingSidebarSurface: no Metal; the swipe's dock is not checked"); return }
        var light = SpaceTheme.singleColor(ThemeColor(red: 0.8, green: 0.88, blue: 0.97)!); light.appearance = .light
        var dark = SpaceTheme.singleColor(ThemeColor(red: 0.36, green: 0.22, blue: 0.62)!); dark.appearance = .dark
        surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        surface.drawsBackground = true
        surface.theme = light
        surface.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.95)
        let blend = FloatingSidebarSurface.pagingBlend(progress: 0.95)
        func blurs() -> [NSVisualEffectView] { surface.subviews.compactMap { $0 as? NSVisualEffectView } }
        guard blurs().count == 2 else { fatalError("FloatingSidebarSurface: the swipe's crossfade") }
        let base = blurs()[0], crossfade = blurs()[1]
        surface.preparesFloatingDock = true
        guard blurs().count == 3, let dock = blurs().last else { fatalError("FloatingSidebarSurface: the dock's preparation adds its material") }
        check(surface.subviews.firstIndex(of: dock) == surface.subviews.firstIndex(of: crossfade).map { $0 + 1 },
              "the window's material, created mid-swipe, lies over the crossfade so it covers both blurs as it fades in")
        check(dock.alphaValue == 0 && near(base.alphaValue, blend.base) && near(crossfade.alphaValue, blend.incoming),
              "prepared: the swipe's blend is untouched")
        root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.allowsImplicitAnimation = true
            surface.docksFloatingSurface = true
        }
        check(base.alphaValue == 0 && crossfade.alphaValue == 0 && dock.alphaValue == 1, "docking fades both blurs out and the window's material in")
        for (view, name) in [(base, "blur"), (crossfade, "crossfade"), (dock, "dock material")] {
            let fade = view.layer?.animation(forKey: "opacity") as? CABasicAnimation
            check(fade.map { near($0.duration, 0.08, 1e-6) } == true, "the \(name) fades on the group's 0.08 s timing")
        }
        surface.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.97)
        check(base.alphaValue == 0 && crossfade.alphaValue == 0, "the swipe moving on mid-dock keeps both blurs faded")
        surface.theme = dark
        surface.preparesFloatingDock = false
        check(base.alphaValue == 0 && crossfade.alphaValue == 0 && dock.alphaValue == 1,
              "the swipe's commit and the full pass's end of preparation keep the fades mid-dock")
        surface.docksFloatingSurface = false
        let resumed = FloatingSidebarSurface.pagingBlend(progress: 0.97)
        check(near(base.alphaValue, resumed.base) && near(crossfade.alphaValue, resumed.incoming) && dock.isHidden,
              "a reversed dock restores the swipe's blend")
        check([base, crossfade, dock].allSatisfy { $0.layer?.animation(forKey: "opacity") == nil }, "a reversed dock leaves no fade in flight")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.allowsImplicitAnimation = true
            surface.docksFloatingSurface = true
        }
        surface.pagingTransition = nil
        check(!crossfade.isHidden && crossfade.alphaValue == 0 && crossfade.layer?.animation(forKey: "opacity") != nil,
              "a swipe ending mid-dock lets the crossfade finish fading instead of vanishing")
        surface.docksFloatingSurface = false
        check(crossfade.isHidden && base.alphaValue == 1 && crossfade.layer?.animation(forKey: "opacity") == nil,
              "reversing that dock hides the finished swipe's crossfade and shows the whole blur")
        var alsoLight = SpaceTheme.singleColor(ThemeColor(red: 0.95, green: 0.8, blue: 0.6)!); alsoLight.appearance = .light
        surface.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.97)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.allowsImplicitAnimation = true
            surface.docksFloatingSurface = true
        }
        surface.pagingTransition = ThemePagingTransition(from: light, theme: alsoLight, progress: 0.97)
        check(!crossfade.isHidden && crossfade.alphaValue == 0 && crossfade.layer?.animation(forKey: "opacity") != nil,
              "pages coming to agree mid-dock let the crossfade finish fading")
        surface.docksFloatingSurface = false
        check(crossfade.isHidden && base.alphaValue == 1, "and reversing that dock hides it and shows the whole blur")
        surface.pagingTransition = ThemePagingTransition(from: light, theme: dark, progress: 0.97)
        surface.docksFloatingSurface = true
        surface.floatingCornerRadius = nil
        surface.docksFloatingSurface = false
        check(crossfade.isHidden && base.alphaValue == 1 && dock.isHidden,
              "a dock settling mid-swipe hides the crossfade and restores the blur, though the swipe goes on")
        surface.pagingTransition = nil
    }
}
