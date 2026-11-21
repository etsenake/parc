import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class Surface {
    let size = NSRect(x: 0, y: 0, width: 400, height: 300)
    let window: NSWindow
    let root: ThemeRendererView
    let systemPalette: ThemeChromePalette
    var published: [ThemeChromePalette] = []

    init() {
        _ = NSApplication.shared
        window = NSWindow(contentRect: size, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        root = ThemeRendererView(frame: size)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        systemPalette = root.palette
    }

    deinit { MainActor.assumeIsolated { window.contentView = nil } }

    func goIncognito() {
        root.onPaletteChange = { [weak self] in self?.published.append($0) }
        root.incognito = true
    }
}

private func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0005) -> Bool { abs(a - b) <= e }

private func components(_ color: NSColor?, _ space: NSColorSpace) -> [CGFloat]? {
    guard let c = color?.usingColorSpace(space) else { return nil }
    return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
}

private func same(_ a: NSColor, _ b: NSColor) -> Bool {
    guard let x = components(a, .extendedSRGB), let y = components(b, .extendedSRGB) else { return false }
    return zip(x, y).allSatisfy { near($0, $1, 0.0001) }
}

private func materials(_ view: NSView) -> [NSVisualEffectView] { view.subviews.compactMap { $0 as? NSVisualEffectView } }

private func canvases(_ view: NSView) -> [NSView] { view.subviews.filter { !($0 is NSVisualEffectView) && $0.className.contains("Canvas") } }

struct IncognitoWindowThemeTests {
    @MainActor @Test func theIncognitoBackgroundIsOpaqueDisplayP3() {
        let background = components(IncognitoWindowTheme.background, .displayP3)
        #expect(background.map { near($0[0], 0.054) && near($0[1], 0.06) && near($0[2], 0.075) && $0[3] == 1 } == true)
    }

    @MainActor @Test func thePaletteThemeIsOneSRGBColour() {
        let primary = IncognitoWindowTheme.paletteTheme.primaryColor
        #expect(IncognitoWindowTheme.paletteTheme == .singleColor(primary!))
        #expect(primary?.colorSpace == .sRGB)
    }

    @MainActor @Test func brandBlueInExtendedSRGBWithItsBlueClampedToOne() {
        let brand = NSColor(displayP3Red: 49 / 255, green: 57 / 255, blue: 251 / 255, alpha: 1).usingColorSpace(.extendedSRGB)!
        let primary = IncognitoWindowTheme.paletteTheme.primaryColor!
        #expect(near(CGFloat(primary.red), brand.redComponent, 0.0001))
        #expect(near(CGFloat(primary.green), brand.greenComponent, 0.0001))
        #expect(brand.blueComponent > 1)
        #expect(primary.blue == 1)
    }

    @MainActor @Test func anOrdinaryWindowKeepsItsMaterialAndHasNoFill() {
        let s = Surface()
        #expect(s.root.layer?.backgroundColor == nil)
        #expect(materials(s.root).first?.isHidden == false)
    }

    @MainActor @Test func anOrdinaryWindowsPaletteThemeIsItsSpaces() {
        let s = Surface()
        #expect(s.root.paletteTheme == s.root.theme)
    }

    @MainActor @Test func turningIncognitoOnPublishesThePaletteOnce() {
        let s = Surface()
        s.goIncognito()
        #expect(s.published.count == 1)
    }

    @MainActor @Test func incognitoHasNoTranslucencyAndNoThemeCanvas() {
        let s = Surface()
        s.goIncognito()
        #expect(materials(s.root).allSatisfy { $0.isHidden })
        #expect(canvases(s.root).allSatisfy { $0.isHidden })
    }

    @MainActor @Test func theWindowSurfaceIsTheOpaqueIncognitoColour() {
        let s = Surface()
        s.goIncognito()
        #expect(s.root.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor)
    }

    @MainActor @Test func aPrivateWindowsPaletteThemeIsTheIncognitoTheme() {
        let s = Surface()
        s.goIncognito()
        #expect(s.root.paletteTheme == IncognitoWindowTheme.paletteTheme)
    }

    @MainActor @Test func thePaletteResolvesAgainstTheDarkAquaWindow() {
        let s = Surface()
        s.goIncognito()
        #expect(s.root.palette.isDark)
        #expect(s.root.palette.contentAppearance?.name == .darkAqua)
    }

    @MainActor @Test(arguments: ["title", "maxContrastColor", "foregroundPrimary", "hover", "background"])
    func theIncognitoPaletteIsTheBrandPalettesDarkHalf(_ name: String) {
        let s = Surface()
        s.goIncognito()
        let expected = ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: true)
        let palette = s.root.palette
        let pairs: [String: (NSColor, NSColor)] = ["title": (palette.title, expected.title), "maxContrastColor": (palette.maxContrastColor, expected.maxContrastColor),
            "foregroundPrimary": (palette.foregroundPrimary, expected.foregroundPrimary), "hover": (palette.hover, expected.hover),
            "background": (palette.background, expected.background)]
        #expect(same(pairs[name]!.0, pairs[name]!.1))
    }

    @MainActor @Test func theIncognitoPaletteIsNotTheUncolouredFallback() {
        let s = Surface()
        s.goIncognito()
        #expect(!same(s.root.palette.title, s.systemPalette.title))
    }

    @MainActor @Test func anIncognitoSurfaceIgnoresItsSpaceTheme() {
        let s = Surface()
        s.goIncognito()
        let expected = ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: true)
        s.root.theme = .singleColor(ThemeColor(hex: "202020")!)
        #expect(s.root.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor)
        #expect(materials(s.root).allSatisfy { $0.isHidden })
        #expect(canvases(s.root).allSatisfy { $0.isHidden })
        #expect(same(s.root.palette.title, expected.title))
    }

    @MainActor @Test func theRenderedSurfaceIsOpaqueWithNothingBehindItShowing() {
        let s = Surface()
        s.goIncognito()
        s.root.display()
        CATransaction.flush()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .retagging(with: .sRGB)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.setFillColor(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        s.root.layer!.render(in: context)
        let pixel = rep.bitmapData!
        #expect(abs(Int(pixel[0]) - 13) <= 1)
        #expect(abs(Int(pixel[1]) - 15) <= 1)
        #expect(abs(Int(pixel[2]) - 19) <= 1)
        #expect(pixel[3] == 255)
    }

    @MainActor private static func sidebar(_ s: Surface) -> ThemeRendererView {
        let sidebar = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
        s.root.addSubview(sidebar)
        sidebar.coordinateSpace = s.root
        sidebar.incognito = true
        sidebar.drawsBackground = false
        return sidebar
    }

    @MainActor @Test func aLockedSidebarDrawsNothingSoTheWindowsSurfaceShowsThrough() {
        let s = Surface()
        let sidebar = Self.sidebar(s)
        defer { withExtendedLifetime(s) {} }
        #expect(sidebar.layer?.backgroundColor == nil)
        #expect(materials(sidebar).allSatisfy { $0.isHidden })
    }

    @MainActor @Test func aFloatingSidebarIsTheOpaqueColourInsideItsRoundedEdge() {
        let s = Surface()
        let sidebar = Self.sidebar(s)
        defer { withExtendedLifetime(s) {} }
        sidebar.drawsBackground = true
        sidebar.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        #expect(sidebar.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor)
        #expect(sidebar.layer?.cornerRadius == 8)
        #expect(sidebar.layer?.borderWidth == 1)
        #expect(sidebar.layer?.borderColor == FloatingSidebarSurface.borderColor)
        #expect(materials(sidebar).allSatisfy { $0.isHidden })
    }

    @MainActor @Test func dockingShowsNoBehindWindowMaterialAndKeepsTheFill() {
        let s = Surface()
        let sidebar = Self.sidebar(s)
        defer { withExtendedLifetime(s) {} }
        sidebar.drawsBackground = true
        sidebar.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        sidebar.preparesFloatingDock = true
        sidebar.docksFloatingSurface = true
        #expect(materials(sidebar).allSatisfy { $0.isHidden })
        #expect(sidebar.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor)
    }

    @MainActor @Test func turningIncognitoOffRestoresTheMaterialAndTheSpacePalette() {
        let s = Surface()
        s.goIncognito()
        s.root.incognito = false
        #expect(s.root.layer?.backgroundColor == nil)
        #expect(materials(s.root).first?.isHidden == false)
        #expect(same(s.root.palette.title, s.systemPalette.title))
    }

    @MainActor @Test func theIncognitoSimpleColourIsTheBasicColourInTheWebsiteStylesheet() {
        let expected = ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: true)
        #expect(expected.websiteStylesheet(theme: SpaceTheme(), basicBackground: IncognitoWindowTheme.background)
            .contains("  --arc-background-simple-color: #0E0F13FF;"))
    }

    @MainActor @Test func withoutItTheThemesColoursAreUsed() {
        let expected = ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: true)
        #expect(!expected.websiteStylesheet(theme: SpaceTheme()).contains("#0E0F13FF"))
    }

    @MainActor @Test func theAddressPillIncognitoFillIsP3WhiteAtFifteenPercent() {
        let rest = components(SidebarAddressPillView.incognitoFill, .displayP3)
        #expect(rest.map { $0[0] == 1 && $0[1] == 1 && $0[2] == 1 && near($0[3], 0.15) } == true)
    }

    @MainActor @Test func incognitoRestsOnTheIncognitoPlaceholderBackground() {
        #expect(SidebarAddressPillView.fill(dark: true, hovered: false, incognito: true) == SidebarAddressPillView.incognitoFill)
    }

    @MainActor @Test func incognitoHoversOnTheSidebarHoveredBackground() {
        #expect(SidebarAddressPillView.fill(dark: true, hovered: true, incognito: true) == SidebarAddressPillView.fill(dark: true, hovered: true))
    }

    @MainActor @Test func anOrdinaryWindowKeepsTheSidebarItemBackground() {
        #expect(SidebarAddressPillView.fill(dark: true, hovered: false, incognito: false) == SidebarAddressPillView.fill(dark: true, hovered: false))
    }

    @MainActor @Test func thePillAppliesTheOrdinaryRestFill() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        pill.dark = true
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: false).cgColor)
    }

    @MainActor @Test func theIncognitoRestFillAppliesAtOnce() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        pill.dark = true
        pill.incognito = true
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.incognitoFill.cgColor)
    }

    @MainActor @Test func theIncognitoHoverFill() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        pill.dark = true
        pill.incognito = true
        pill.setHovered(true, animated: false)
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: true).cgColor)
    }

    @MainActor @Test func leavingIncognitoRestoresTheOrdinaryFill() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        pill.dark = true
        pill.incognito = true
        pill.setHovered(true, animated: false)
        pill.setHovered(false, animated: false)
        pill.incognito = false
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: false).cgColor)
    }
}
