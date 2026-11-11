import AppKit

enum CommandBarSiteColor {
    static let bundled: [(template: String, hex: String)] = [
        ("https://drive.google.com/drive/search?q={searchTerms}", "0F9D58"),
        ("https://mail.google.com/mail/ca/u/0/#apps/{searchTerms}", "D44638"),
        ("https://www.google.com/maps/search/{searchTerms}", "FBBC05"),
        ("https://calendar.google.com/calendar/u/0/r/search?q={searchTerms}", "9C27B0"),
        ("https://docs.google.com/document/u/0/?q={searchTerms}", "4285F4"),
        ("https://www.dropbox.com/search/personal?&query={searchTerms}", "007EE5"),
        ("https://www.amazon.com/s?k={searchTerms}", "FF9900"),
        ("https://github.com/search?q={searchTerms}", "743FC7"),
        ("https://www.figma.com/files/search?q={searchTerms}", "F24E1E"),
        ("https://x.com/search?q={searchTerms}", "000000"),
        ("https://twitter.com/search?q={searchTerms}", "000000"),
        ("https://www.youtube.com/results?search_query={searchTerms}", "FF0000"),
        ("https://wikipedia.org/w/index.php?search={searchTerms}", "FF4500"),
        ("https://www.reddit.com/search/?q={searchTerms}", "FF4500"),
        ("https://soundcloud.com/search?q={searchTerms}", "F85216"),
        ("https://app.asana.com/0/search?q={searchTerms}", "F06A6A"),
        ("https://linkedin.com/search/results/all/?keywords={searchTerms}", "0B66C2"),
        ("https://music.apple.com/us/search?term={searchTerms}", "FA2A44"),
        ("https://open.spotify.com/search/{searchTerms}", "1DB954"),
    ]

    static func scope<Scope>(forPageHost pageHost: String, in scopes: [Scope], searchHost: (Scope) -> String?) -> Scope? {
        scopes.first { scope in searchHost(scope).map { !$0.isEmpty && host($0, matches: pageHost) } == true }
    }

    static func bundledColor(template: String, searchHost: String, prepopulated: Bool) -> NSColor? {
        guard !prepopulated else { return nil }
        let entry = bundled.first { $0.template == template } ?? bundled.first { entry in
            URL(string: entry.template.replacingOccurrences(of: "{searchTerms}", with: ""))?.host
                .map { host(searchHost, matches: $0) } == true
        }
        return entry.flatMap { color(hex: $0.hex) }
    }

    static func color(hex: String) -> NSColor? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(displayP3Red: CGFloat(value >> 16 & 0xff) / 255, green: CGFloat(value >> 8 & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    static func host(_ host: String, matches site: String) -> Bool {
        let host = host.lowercased(), site = site.lowercased()
        return host == site || host.hasSuffix("." + site) || host.components(separatedBy: ".").contains(site)
    }

    static func faviconPixels(_ image: NSImage) -> [UInt8]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let info = cgImage.bitmapInfo.rawValue, alpha = info & CGBitmapInfo.alphaInfoMask.rawValue
        if cgImage.colorSpace?.model == .rgb,
           alpha == CGImageAlphaInfo.last.rawValue || alpha == CGImageAlphaInfo.noneSkipLast.rawValue,
           info & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue,
           cgImage.bitsPerComponent == 8, cgImage.bitsPerPixel == 32, cgImage.bytesPerRow == cgImage.width * 4,
           let data = cgImage.dataProvider?.data as Data? {
            return [UInt8](data)
        }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    static func dominantRGB(_ pixels: [UInt8]) -> (UInt8, UInt8, UInt8)? {
        guard let palette = MedianCutPalette.palette(pixels, colorCount: 5, quality: 10, ignoresWhite: true),
              let first = palette.first else { return nil }
        return palette.first { brightness($0) >= 0.15 } ?? first
    }

    static func faviconColor(_ rgb: (UInt8, UInt8, UInt8)) -> NSColor {
        lightnessAdjusted(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, by: -0.15)
    }

    static func lightnessAdjusted(red r: CGFloat, green g: CGFloat, blue b: CGFloat, by delta: CGFloat,
                                  alpha: CGFloat = 1) -> NSColor {
        let high = max(r, g, b), low = min(r, g, b), lightness = (high + low) / 2
        var hue: CGFloat = 0, saturation: CGFloat = 0
        if high != low {
            let range = high - low
            saturation = lightness > 0.5 ? range / (2 - high - low) : range / (high + low)
            hue = high == r ? (g - b) / range + (g < b ? 6 : 0) : high == g ? (b - r) / range + 2 : (r - g) / range + 4
            hue /= 6
        }
        let adjusted = min(max(lightness + delta, 0), 1)
        func channel(_ t: CGFloat) -> CGFloat {
            guard saturation > 0 else { return adjusted }
            let q = adjusted < 0.5 ? adjusted * (1 + saturation) : adjusted + saturation - adjusted * saturation
            let p = 2 * adjusted - q
            let t = t < 0 ? t + 1 : t > 1 ? t - 1 : t
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return NSColor(srgbRed: channel(hue + 1.0 / 3), green: channel(hue), blue: channel(hue - 1.0 / 3), alpha: alpha)
    }

    private static func brightness(_ rgb: (UInt8, UInt8, UInt8)) -> CGFloat {
        CGFloat(max(rgb.0, rgb.1, rgb.2)) / 255
    }
}

enum MedianCutPalette {
    private static let significantBits = 5, shift = 8 - 5, side = 1 << 5

    private final class Box {
        var low: [Int], high: [Int]
        let histogram: [Int]
        private var cachedCount: Int?
        init(low: [Int], high: [Int], histogram: [Int]) { self.low = low; self.high = high; self.histogram = histogram }
        func copy() -> Box { Box(low: low, high: high, histogram: histogram) }
        var volume: Int { (0..<3).reduce(1) { $0 * (high[$1] - low[$1] + 1) } }
        var count: Int {
            if let cachedCount { return cachedCount }
            var total = 0
            forEachCell { total += histogram[$0] }
            cachedCount = total
            return total
        }
        func levels(_ channel: Int) -> StrideThrough<Int> { stride(from: low[channel], through: high[channel], by: 1) }
        func forEachCell(_ body: (Int) -> Void) {
            for r in levels(0) { for g in levels(1) { for b in levels(2) { body(index(r, g, b)) } } }
        }
        var average: (UInt8, UInt8, UInt8) {
            var total = 0, sums = [0, 0, 0]
            for r in levels(0) {
                for g in levels(1) {
                    for b in levels(2) {
                        let value = histogram[index(r, g, b)]
                        total += value
                        for (channel, level) in [r, g, b].enumerated() {
                            sums[channel] += Int(Double(value) * (Double(level) + 0.5) * Double(1 << shift))
                        }
                    }
                }
            }
            func component(_ channel: Int) -> UInt8 {
                total > 0 ? UInt8(sums[channel] / total) : UInt8(min((1 << shift) * (low[channel] + high[channel] + 1) / 2, 255))
            }
            return (component(0), component(1), component(2))
        }
        var widestChannel: Int {
            let widths = (0..<3).map { high[$0] - low[$0] }
            let widest = widths.max() ?? 0
            return widths.firstIndex(of: widest) ?? 0
        }
    }

    private static func index(_ r: Int, _ g: Int, _ b: Int) -> Int {
        (r << (2 * significantBits)) + (g << significantBits) + b
    }

    static func palette(_ pixels: [UInt8], colorCount: Int, quality: Int, ignoresWhite: Bool) -> [(UInt8, UInt8, UInt8)]? {
        guard !pixels.isEmpty, colorCount > 1, colorCount <= 256, quality > 0 else { return nil }
        var histogram = [Int](repeating: 0, count: 1 << (3 * significantBits))
        var low = [Int](repeating: side - 1, count: 3), high = [Int](repeating: 0, count: 3)
        var sampled = false
        for pixel in stride(from: 0, to: pixels.count / 4, by: quality) {
            let a = pixels[pixel * 4], b = pixels[pixel * 4 + 1], g = pixels[pixel * 4 + 2], r = pixels[pixel * 4 + 3]
            guard a >= 125, !(ignoresWhite && r > 250 && g > 250 && b > 250) else { continue }
            let levels = [Int(r) >> shift, Int(g) >> shift, Int(b) >> shift]
            for channel in 0..<3 { low[channel] = min(low[channel], levels[channel]); high[channel] = max(high[channel], levels[channel]) }
            histogram[index(levels[0], levels[1], levels[2])] += 1
            sampled = true
        }
        guard sampled else { return nil }
        var queue = [Box(low: low, high: high, histogram: histogram)]
        let byCount: (Box, Box) -> Bool = { $0.count < $1.count }
        let byProduct: (Box, Box) -> Bool = {
            $0.count == $1.count ? $0.volume < $1.volume : Int64($0.count) * Int64($0.volume) < Int64($1.count) * Int64($1.volume)
        }
        iterate(&queue, by: byCount, target: Int((0.75 * Double(colorCount)).rounded(.up)))
        queue.sort(by: byProduct)
        iterate(&queue, by: byProduct, target: colorCount - queue.count)
        return queue.reversed().map(\.average)
    }

    private static func iterate(_ queue: inout [Box], by order: (Box, Box) -> Bool, target: Int) {
        var colors = 1
        for _ in 0..<1000 {
            guard let box = queue.last else { return }
            if box.count == 0 { queue.sort(by: order); continue }
            queue.removeLast()
            let cut = medianCut(box)
            queue.append(contentsOf: cut)
            if cut.count == 2 { colors += 1 }
            queue.sort(by: order)
            if colors >= target { return }
        }
    }

    private static func medianCut(_ box: Box) -> [Box] {
        guard box.count != 1 else { return [box] }
        let axis = box.widestChannel
        var partial = [Int](repeating: -1, count: side), total = 0
        for level in box.levels(axis) {
            let slice = box.copy(); slice.low[axis] = level; slice.high[axis] = level
            total += slice.count; partial[level] = total
        }
        var lookAhead = [Int](repeating: -1, count: side)
        for (level, sum) in partial.enumerated() where sum != -1 { lookAhead[level] = total - sum }
        let lower = box.low[axis], upper = box.high[axis]
        for level in box.levels(axis) where partial[level] > total / 2 {
            let first = box.copy(), second = box.copy()
            let left = level - lower, right = upper - level
            var split = left <= right ? min(upper - 1, level + right / 2) : max(lower, Int(Double(level - 1) - Double(left) / 2))
            while split < 0 || partial[split] <= 0 { split += 1 }
            var remaining = lookAhead[split]
            while remaining == 0 && split > 0 && partial[split - 1] > 0 { split -= 1; remaining = lookAhead[split] }
            first.high[axis] = split; second.low[axis] = split + 1
            return [first, second]
        }
        return [box]
    }
}
