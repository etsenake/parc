import AppKit

///
/// browser's is a theme from its own icon, with the colour wheel's harmonies
/// the theme editor offers.
@MainActor
enum BrowserImportTheme {
    static func page(for source: PCNativeImportSource, icon: @autoclosure () -> NSImage) -> BrowserImportBackdrop.Page {
        if BrowserImportCoordinator.isArc(source) { return .sunset }
        if let cached = sampled[source.appURL] { return .theme(cached) }
        guard let theme = Self.theme(sampling: icon()) else { return .theme(SpaceTheme()) }
        sampled[source.appURL] = theme
        return .theme(theme)
    }
    private static var sampled: [URL: SpaceTheme] = [:]


    /// The icon's strongest hue, weighted toward saturated mid tones, becomes
    /// the primary colour. A second strong hue picks the wheel: near it,
    /// analogous; across the wheel, complementary.
    static func theme(sampling icon: NSImage) -> SpaceTheme? {
        let side = 32
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let bins = 36
        var weight = [Double](repeating: 0, count: bins), saturation = weight, lightness = weight
        var hueX = weight, hueY = weight
        for pixel in 0..<(side * side) {
            let alpha = Double(bytes[pixel * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            func channel(_ offset: Int) -> Double { min(1, Double(bytes[pixel * 4 + offset]) / 255 / alpha) }
            guard let color = ThemeColor(red: channel(0), green: channel(1), blue: channel(2)) else { continue }
            let hsl = color.hsl
            guard hsl.saturation > 0.3, (0.15...0.85).contains(hsl.lightness) else { continue }
            let w = alpha * hsl.saturation * (1 - abs(hsl.lightness - 0.5))
            let bin = Int(hsl.hue * Double(bins)) % bins
            weight[bin] += w; saturation[bin] += hsl.saturation * w; lightness[bin] += hsl.lightness * w
            hueX[bin] += cos(hsl.hue * 2 * .pi) * w; hueY[bin] += sin(hsl.hue * 2 * .pi) * w
        }
        func around(_ bin: Int) -> [Int] { [(bin + bins - 1) % bins, bin, (bin + 1) % bins] }
        let smoothed = (0..<bins).map { around($0).reduce(0) { $0 + weight[$1] } }
        guard let top = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }), smoothed[top] > 0 else { return nil }
        let near = around(top), total = near.reduce(0) { $0 + weight[$1] }
        var hue = atan2(near.reduce(0) { $0 + hueY[$1] }, near.reduce(0) { $0 + hueX[$1] }) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let s = min(0.85, max(0.55, near.reduce(0) { $0 + saturation[$1] } / total))
        let l = min(0.62, max(0.5, near.reduce(0) { $0 + lightness[$1] } / total))
        guard let primary = ThemeColor.hsl(hue: hue, saturation: s, lightness: l) else { return nil }
        func distance(_ a: Int, _ b: Int) -> Int { min(abs(a - b), bins - abs(a - b)) }
        // The other strong hues, each at least 40° from those already kept.
        var strong = [top]
        for bin in smoothed.indices.sorted(by: { smoothed[$0] > smoothed[$1] })
        where smoothed[bin] >= smoothed[top] * 0.25 && strong.allSatisfy({ distance($0, bin) >= 4 }) { strong.append(bin) }
        // Grain at 0.7 of the dial (strength 0.56): visible at a glance, as on a themed Space.
        var theme = SpaceTheme(primaryColor: primary, colorCount: 2, wheel: .analogous, noise: 0.7, intensity: 0.8)
        if strong.count >= 3 {
            theme.wheel = .complimentary; theme.colorCount = 3
        } else if strong.count == 2, distance(strong[1], top) > 9 {
            theme.wheel = .complimentary; theme.colorCount = distance(strong[1], top) >= 16 ? 2 : 3
        }
        return theme
    }
}

///
///
///
@MainActor
enum BrowserImportArcIcon {
    static func icon(appURL: URL) -> NSImage {
        if let cached = installed[appURL] { return cached }
        let image = Bundle(url: appURL).flatMap { bundle in
            bundle.bundleIdentifier == BrowserImportCoordinator.arcBundleIdentifier ? bundle.image(forResource: "AppIcon") : nil
        } ?? bundled
        installed[appURL] = image
        return image
    }
    private static var installed: [URL: NSImage] = [:]
    static let bundled = Bundle.main.url(forResource: "Arc", withExtension: "icns", subdirectory: "BrowserImport")
        .flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 64, height: 64))
}
