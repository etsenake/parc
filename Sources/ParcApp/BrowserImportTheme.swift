import AppKit
import ParcCore
import ParcEngine

@MainActor
enum BrowserImportTheme {
    static let brands: [String: (UInt32, UInt32)] = [
        "com.google.Chrome": (0x1E8E3E, 0xFBBC04), "com.apple.Safari": (0x0B57D0, 0x22C3EE),
        "org.mozilla.firefox": (0x7542E5, 0xFF9500), "com.microsoft.edgemac": (0x0F5BD6, 0x2BC46B),
        "com.brave.Browser": (0xA3123A, 0xFB542B), "com.operasoftware.Opera": (0x8E0E1C, 0xFF1B2D),
        "com.operasoftware.OperaGX": (0x8E0E1C, 0xFF1B2D), "com.vivaldi.Vivaldi": (0x8A1E3A, 0xEF3939),
    ]

    static func wash(for source: PCNativeImportSource, icon: @autoclosure () -> NSImage) -> BrowserImportWash {
        if BrowserImportCoordinator.isArc(source) { return .arc }
        let id = Bundle(url: source.appURL)?.bundleIdentifier ?? source.identifier
        if let brand = brands[id] { return .pair(brand.0, brand.1) }
        if let cached = sampled[source.appURL] { return cached }
        guard let pair = Self.pair(sampling: icon()) else { return .arc }
        let wash = BrowserImportWash.pair(pair.0, pair.1)
        sampled[source.appURL] = wash
        return wash
    }
    private static var sampled: [URL: BrowserImportWash] = [:]

    static func pair(sampling icon: NSImage) -> (UInt32, UInt32)? {
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
        var weight = [Double](repeating: 0, count: bins)
        for pixel in 0..<(side * side) {
            let alpha = Double(bytes[pixel * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            func channel(_ offset: Int) -> Double { min(1, Double(bytes[pixel * 4 + offset]) / 255 / alpha) }
            guard let color = ThemeColor(red: channel(0), green: channel(1), blue: channel(2)) else { continue }
            let hsl = color.hsl
            guard hsl.saturation > 0.3, (0.15...0.85).contains(hsl.lightness) else { continue }
            weight[Int(hsl.hue * Double(bins)) % bins] += alpha * hsl.saturation * (1 - abs(hsl.lightness - 0.5))
        }
        func distance(_ a: Int, _ b: Int) -> Int { min(abs(a - b), bins - abs(a - b)) }
        let smoothed = (0..<bins).map { bin in [-1, 0, 1].reduce(0) { $0 + weight[(bin + $1 + bins) % bins] } }
        guard let top = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }), smoothed[top] > 0 else { return nil }
        let second = smoothed.indices.filter { distance($0, top) >= 4 }.max { smoothed[$0] < smoothed[$1] }
        let other = second.flatMap { smoothed[$0] >= smoothed[top] * 0.25 ? $0 : nil } ?? (top + 4) % bins
        func color(_ bin: Int, lightness: Double) -> UInt32 {
            let value = ThemeColor.hsl(hue: (Double(bin) + 0.5) / Double(bins), saturation: 0.8, lightness: lightness)!
            return [value.red, value.green, value.blue].reduce(0) { $0 << 8 | UInt32(($1 * 255).rounded()) }
        }
        return (color(top, lightness: 0.4), color(other, lightness: 0.58))
    }
}

@MainActor
enum BrowserImportArcIcon {
    static func icon(appURL: URL) -> NSImage {
        if let cached = installed[appURL] { return cached }
        let image = Bundle(url: appURL).flatMap { bundle in
            bundle.bundleIdentifier == BrowserImportCoordinator.arcBundleIdentifier ? bundle.image(forResource: "AppIcon") : nil
        } ?? NSWorkspace.shared.icon(forFile: appURL.path)
        installed[appURL] = image
        return image
    }
    private static var installed: [URL: NSImage] = [:]
}
