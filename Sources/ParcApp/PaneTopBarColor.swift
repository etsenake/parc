import AppKit

enum PaneTopBarColor {
    static let crossfadeDuration: TimeInterval = 0.18

    static func usesDarkScheme(on background: NSColor) -> Bool? {
        components(background).map { usesDarkScheme(over: $0, compositesGammaEncoded: false) }
    }

    @MainActor static func usesDarkScheme(backingOver theme: NSColor, windowDark: Bool) -> Bool? {
        var resolved: RGBA?
        NSAppearance(named: windowDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = components(backing)
        }
        guard let base = components(theme), let resolved else { return nil }
        let surface = composite(red: resolved.red, green: resolved.green, blue: resolved.blue,
                                alpha: resolved.alpha, over: base)
        return usesDarkScheme(over: surface, compositesGammaEncoded: true)
    }

    @MainActor static var backing: NSColor { SplitPanePlaceholder.emptyContentBackground }

    static func glyph(dark: Bool) -> NSColor {
        (dark ? NSColor.white : .black).withAlphaComponent(dark ? 0.675 : 0.55)
    }

    static func fill(from color: NSColor?) -> NSColor? {
        guard let rgb = color?.usingColorSpace(.sRGB), rgb.alphaComponent >= 1 else { return nil }
        return rgb
    }

    private struct RGBA { var red, green, blue, alpha: CGFloat }

    private static func usesDarkScheme(over surface: RGBA, compositesGammaEncoded: Bool) -> Bool {
        let black = composite(red: 0, green: 0, blue: 0, alpha: 0.6, over: surface)
        let white = composite(red: 1, green: 1, blue: 1, alpha: 0.75, over: surface)
        let surfaceLuminance = luminance(surface, gammaEncoded: true)
        return contrast(surfaceLuminance, luminance(white, gammaEncoded: compositesGammaEncoded))
            >= contrast(surfaceLuminance, luminance(black, gammaEncoded: compositesGammaEncoded))
    }

    private static func components(_ color: NSColor) -> RGBA? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        return RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }

    private static func composite(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, over page: RGBA) -> RGBA {
        guard alpha < 1 else { return RGBA(red: red, green: green, blue: blue, alpha: alpha) }
        let remainder = page.alpha * (1 - alpha)
        let out = alpha + remainder
        guard out > 0 else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        return RGBA(red: (alpha * red + remainder * page.red) / out,
                    green: (alpha * green + remainder * page.green) / out,
                    blue: (alpha * blue + remainder * page.blue) / out, alpha: out)
    }

    private static func luminance(_ color: RGBA, gammaEncoded: Bool) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            guard gammaEncoded else { return value }
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private static func contrast(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let lighter = max(first, second) + 0.05, darker = min(first, second) + 0.05
        return lighter / darker
    }
}
