import AppKit

@MainActor @main struct IncognitoWindowThemeChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("IncognitoWindowTheme: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0005) -> Bool { abs(a - b) <= e }
    static func components(_ color: NSColor?, _ space: NSColorSpace) -> [CGFloat]? {
        guard let c = color?.usingColorSpace(space) else { return nil }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
    static func same(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = components(a, .extendedSRGB), let y = components(b, .extendedSRGB) else { return false }
        return zip(x, y).allSatisfy { near($0, $1, 0.0001) }
    }
    static func materials(_ view: NSView) -> [NSVisualEffectView] {
        view.subviews.compactMap { $0 as? NSVisualEffectView }
    }
    static func canvases(_ view: NSView) -> [NSView] {
        view.subviews.filter { !($0 is NSVisualEffectView) && $0.className.contains("Canvas") }
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)

        let background = components(IncognitoWindowTheme.background, .displayP3)
        check(background.map { near($0[0], 0.054) && near($0[1], 0.06) && near($0[2], 0.075) && $0[3] == 1 } == true,
              "the incognito background is opaque Display P3 (0.054, 0.06, 0.075)")
        let brand = NSColor(displayP3Red: 49 / 255, green: 57 / 255, blue: 251 / 255, alpha: 1).usingColorSpace(.extendedSRGB)!
        let primary = IncognitoWindowTheme.paletteTheme.primaryColor
        check(IncognitoWindowTheme.paletteTheme == .singleColor(primary!) && primary?.colorSpace == .sRGB,
              "the palette theme is one sRGB colour")
        check(near(CGFloat(primary!.red), brand.redComponent, 0.0001) && near(CGFloat(primary!.green), brand.greenComponent, 0.0001)
              && brand.blueComponent > 1 && primary!.blue == 1, "BrandBlue in extended sRGB, its 1.024 blue clamped to 1")

        let size = NSRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(contentRect: size, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let root = ThemeRendererView(frame: size)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        let systemPalette = root.palette
        check(root.layer?.backgroundColor == nil && materials(root).first?.isHidden == false,
              "an ordinary window keeps its material and has no fill")
        check(root.paletteTheme == root.theme, "an ordinary window's palette theme is its Space's")

        var published: [ThemeChromePalette] = []
        root.onPaletteChange = { published.append($0) }
        root.incognito = true
        check(published.count == 1, "turning incognito on publishes the palette once")
        check(materials(root).allSatisfy(\.isHidden), "incognito has no translucency: the material is hidden")
        check(canvases(root).allSatisfy(\.isHidden), "and no theme canvas")
        check(root.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor, "the window surface is the opaque incognito colour")
        check(root.paletteTheme == IncognitoWindowTheme.paletteTheme, "a private window's palette theme is the incognito theme")
        let expected = ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: true)
        let palette = root.palette
        check(palette.isDark && palette.contentAppearance?.name == .darkAqua, "the palette resolves against the Dark Aqua window")
        for (name, a, b) in [("title", palette.title, expected.title), ("maxContrastColor", palette.maxContrastColor, expected.maxContrastColor),
                             ("foregroundPrimary", palette.foregroundPrimary, expected.foregroundPrimary), ("hover", palette.hover, expected.hover),
                             ("background", palette.background, expected.background)] {
            check(same(a, b), "the incognito \(name) is the brand palette's dark half")
        }
        check(!same(palette.title, systemPalette.title), "the incognito palette is not the uncoloured fallback")
        root.theme = .singleColor(ThemeColor(hex: "202020")!)
        check(root.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor && materials(root).allSatisfy(\.isHidden)
              && canvases(root).allSatisfy(\.isHidden) && same(root.palette.title, expected.title),
              "an incognito surface ignores its Space theme")
        root.theme = SpaceTheme()

        root.display(); CATransaction.flush()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .retagging(with: .sRGB)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.setFillColor(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        root.layer!.render(in: context)
        let pixel = rep.bitmapData!
        let rgb = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        check(abs(rgb.0 - 13) <= 1 && abs(rgb.1 - 15) <= 1 && abs(rgb.2 - 19) <= 1 && pixel[3] == 255,
              "the rendered surface is opaque (13, 15, 19), nothing behind it showing: got \(rgb)")

        let sidebar = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
        root.addSubview(sidebar)
        sidebar.coordinateSpace = root
        sidebar.incognito = true
        sidebar.drawsBackground = false
        check(sidebar.layer?.backgroundColor == nil && materials(sidebar).allSatisfy(\.isHidden),
              "a locked sidebar draws nothing; the window's surface shows through")
        sidebar.drawsBackground = true
        sidebar.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        check(sidebar.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor && sidebar.layer?.cornerRadius == 8
              && sidebar.layer?.borderWidth == 1 && sidebar.layer?.borderColor == FloatingSidebarSurface.borderColor,
              "a floating sidebar is the opaque colour inside its rounded edge")
        check(materials(sidebar).allSatisfy(\.isHidden), "the floating blur sits under an opaque theme, so it is hidden")
        sidebar.preparesFloatingDock = true; sidebar.docksFloatingSurface = true
        check(materials(sidebar).allSatisfy(\.isHidden) && sidebar.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor,
              "docking shows no behind-window material and keeps the fill")
        sidebar.preparesFloatingDock = false; sidebar.docksFloatingSurface = false

        root.incognito = false
        check(root.layer?.backgroundColor == nil && materials(root).first?.isHidden == false && same(root.palette.title, systemPalette.title),
              "turning incognito off restores the material and the Space palette")

        let sheet = expected.websiteStylesheet(theme: SpaceTheme(), basicBackground: IncognitoWindowTheme.background)
        check(sheet.contains("  --arc-background-simple-color: #0E0F13FF;"), "the incognito simple colour is the basic colour")
        check(!expected.websiteStylesheet(theme: SpaceTheme()).contains("#0E0F13FF"), "without it the theme's colours are used")

        let rest = components(SidebarAddressPillView.incognitoFill, .displayP3)
        check(rest.map { $0[0] == 1 && $0[1] == 1 && $0[2] == 1 && near($0[3], 0.15) } == true, "P3 white at 0.15")
        check(SidebarAddressPillView.fill(dark: true, hovered: false, incognito: true) == SidebarAddressPillView.incognitoFill,
              "incognito rests on CommandBarPlaceholderIncognitoBackground")
        check(SidebarAddressPillView.fill(dark: true, hovered: true, incognito: true) == SidebarAddressPillView.fill(dark: true, hovered: true),
              "incognito hovers on SidebarItemHoveredBackground")
        check(SidebarAddressPillView.fill(dark: true, hovered: false, incognito: false) == SidebarAddressPillView.fill(dark: true, hovered: false),
              "an ordinary window keeps SidebarItemBackground")
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        pill.dark = true
        check(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: false).cgColor, "ordinary rest fill")
        pill.incognito = true
        check(pill.layer?.backgroundColor == SidebarAddressPillView.incognitoFill.cgColor, "the incognito rest fill applies at once")
        pill.setHovered(true, animated: false)
        check(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: true).cgColor, "the incognito hover fill")
        pill.setHovered(false, animated: false); pill.incognito = false
        check(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: false).cgColor, "and back")

        window.contentView = nil
        print("IncognitoWindowTheme checks passed (\(count))")
    }
}
