import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct NoteCoverStyle: Hashable, Identifiable {
    enum Pattern: Hashable { case mesh, waves, confetti, stripes, grid, ripples, paper }

    let id: String
    let name: String
    let pattern: Pattern
    let colors: [UInt32]
    let seed: UInt64
}

struct NoteCoverRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }

    mutating func between(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * unit() }
}

enum NoteCoverGallery {
    static let exportPixelSize = CGSize(width: 1500, height: 600)
    static let thumbnailPixelSize = CGSize(width: 360, height: 144)
    static let fileExtension = "jpg"

    static let styles: [NoteCoverStyle] = [
        NoteCoverStyle(id: "indigo-hour", name: "Indigo Hour", pattern: .mesh, colors: [0x2702C2, 0x6B4CFF, 0xB9A7FF, 0xFF8FB8], seed: 11),
        NoteCoverStyle(id: "peach-fizz", name: "Peach Fizz", pattern: .mesh, colors: [0xFFD7B5, 0xFF8A80, 0xFFC46B, 0xFFF1E0], seed: 23),
        NoteCoverStyle(id: "matcha", name: "Matcha Latte", pattern: .mesh, colors: [0xDCEFD2, 0x7DBE8C, 0xB6D98E, 0xF6F4DC], seed: 37),
        NoteCoverStyle(id: "lagoon", name: "Lagoon", pattern: .mesh, colors: [0x1F6FD1, 0x41D3C8, 0x9BE7FF, 0x2B3FB8], seed: 41),
        NoteCoverStyle(id: "night-drive", name: "Night Drive", pattern: .mesh, colors: [0x120F2E, 0x3A1C71, 0xD76D77, 0x5B2A86], seed: 53),
        NoteCoverStyle(id: "sunset-strip", name: "Sunset Strip", pattern: .waves, colors: [0xFFD166, 0xFF8C61, 0xEF476F, 0x845EC2], seed: 61),
        NoteCoverStyle(id: "lilac-tide", name: "Lilac Tide", pattern: .waves, colors: [0xF3EEFF, 0xD9CCFF, 0xB39DFF, 0x7C5CFF], seed: 71),
        NoteCoverStyle(id: "confetti", name: "Confetti", pattern: .confetti, colors: [0xFFF8EC, 0x2702C2, 0xFF6B6B, 0xFFC93C, 0x3BC9A7, 0x9D7BFF], seed: 83),
        NoteCoverStyle(id: "pinstripe", name: "Pinstripe", pattern: .stripes, colors: [0xEDE9FF, 0xDCD4FF, 0x6B4CFF], seed: 97),
        NoteCoverStyle(id: "blueprint", name: "Blueprint", pattern: .grid, colors: [0x15206B, 0x2340B8, 0x9FB7FF], seed: 101),
        NoteCoverStyle(id: "ripples", name: "Ripples", pattern: .ripples, colors: [0xE6F6FF, 0xB5E3FF, 0x7CC6F2, 0x3D8BD9], seed: 113),
        NoteCoverStyle(id: "sandpaper", name: "Sandpaper", pattern: .paper, colors: [0xF4EBDD, 0xE7D6BD, 0xC9A97E], seed: 127),
    ]

    static func style(id: String) -> NoteCoverStyle? { styles.first { $0.id == id } }

    static func random<Generator: RandomNumberGenerator>(using generator: inout Generator) -> NoteCoverStyle {
        styles.randomElement(using: &generator) ?? styles[0]
    }

    static func randomStyle() -> NoteCoverStyle {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func suggestedName(for style: NoteCoverStyle) -> String { "Cover " + style.name }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func texture(_ name: String) -> CGImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ThemeTextures/\(name).png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func image(for style: NoteCoverStyle, pixelSize: CGSize, grain: CGImage? = texture("grain"),
                      sand: CGImage? = texture("sand")) -> CGImage? {
        let width = max(1, Int(pixelSize.width.rounded())), height = max(1, Int(pixelSize.height.rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let scale = CGFloat(width) / exportPixelSize.width
        var random = NoteCoverRandom(seed: style.seed)
        context.interpolationQuality = .high
        switch style.pattern {
        case .mesh: drawMesh(style, in: context, bounds: bounds, random: &random)
        case .waves: drawWaves(style, in: context, bounds: bounds, random: &random)
        case .confetti: drawConfetti(style, in: context, bounds: bounds, scale: scale, random: &random)
        case .stripes: drawStripes(style, in: context, bounds: bounds, scale: scale)
        case .grid: drawGrid(style, in: context, bounds: bounds, scale: scale, random: &random)
        case .ripples: drawRipples(style, in: context, bounds: bounds, random: &random)
        case .paper: drawPaper(style, in: context, bounds: bounds, sand: sand)
        }
        if let grain {
            context.saveGState()
            context.setBlendMode(.overlay)
            context.setAlpha(style.pattern == .paper ? 0.35 : 0.55)
            context.draw(grain, in: CGRect(x: 0, y: 0, width: grain.width, height: grain.height), byTiling: true)
            context.restoreGState()
        }
        return context.makeImage()
    }

    static func encoded(_ image: CGImage, quality: Double = 0.9) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func assetData(for style: NoteCoverStyle) -> Data? {
        image(for: style, pixelSize: exportPixelSize).flatMap { encoded($0) }
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [CGFloat(hex >> 16 & 255) / 255, CGFloat(hex >> 8 & 255) / 255,
                                                     CGFloat(hex & 255) / 255, alpha])!
    }

    private static func linear(_ colors: [CGColor], in context: CGContext, from start: CGPoint, to end: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func glow(_ hex: UInt32, alpha: CGFloat, at center: CGPoint, radius: CGFloat, in context: CGContext) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(hex, alpha), color(hex, alpha * 0.45), color(hex, 0)] as CFArray,
                                        locations: [0, 0.45, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func drawMesh(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, random: inout NoteCoverRandom) {
        let colors = style.colors
        linear([color(colors[0]), color(colors[colors.count - 1])], in: context,
               from: CGPoint(x: bounds.minX, y: bounds.maxY), to: CGPoint(x: bounds.maxX, y: bounds.minY))
        for index in 0..<7 {
            let hex = colors[(index + 1) % colors.count]
            let center = CGPoint(x: bounds.width * random.between(-0.1, 1.1), y: bounds.height * random.between(-0.2, 1.2))
            glow(hex, alpha: random.between(0.55, 0.9), at: center, radius: bounds.width * random.between(0.25, 0.55), in: context)
        }
    }

    private static func drawWaves(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, random: inout NoteCoverRandom) {
        let colors = style.colors
        linear([color(colors[0]), color(colors[1])], in: context,
               from: CGPoint(x: 0, y: bounds.maxY), to: CGPoint(x: 0, y: bounds.minY))
        let bands = 5
        for band in 0..<bands {
            let progress = CGFloat(band + 1) / CGFloat(bands + 1)
            let baseline = bounds.maxY - bounds.height * progress
            let amplitude = bounds.height * random.between(0.06, 0.12)
            let wavelength = bounds.width * random.between(0.45, 0.8)
            let phase = random.between(0, .pi * 2)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
            var x = bounds.minX
            while x <= bounds.maxX + 4 {
                path.addLine(to: CGPoint(x: x, y: baseline + amplitude * sin(phase + x / wavelength * .pi * 2)))
                x += max(2, bounds.width / 300)
            }
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY))
            path.closeSubpath()
            let hex = colors[min(colors.count - 1, 1 + band * (colors.count - 1) / bands)]
            context.addPath(path)
            context.setFillColor(color(hex, 0.32 + 0.1 * CGFloat(band)))
            context.fillPath()
        }
    }

    private static func drawConfetti(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, scale: CGFloat,
                                     random: inout NoteCoverRandom) {
        let colors = style.colors
        context.setFillColor(color(colors[0]))
        context.fill(bounds)
        glow(colors[5 % colors.count], alpha: 0.18, at: CGPoint(x: bounds.width * 0.8, y: bounds.height * 0.2),
             radius: bounds.width * 0.5, in: context)
        let pieces = 90
        for _ in 0..<pieces {
            let hex = colors[1 + Int(random.next() % UInt64(colors.count - 1))]
            let center = CGPoint(x: bounds.width * random.unit(), y: bounds.height * random.unit())
            let size = random.between(10, 30) * scale
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: random.between(0, .pi))
            context.setFillColor(color(hex, random.between(0.7, 0.95)))
            switch random.next() % 3 {
            case 0:
                context.fillEllipse(in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            case 1:
                let pill = CGPath(roundedRect: CGRect(x: -size, y: -size * 0.22, width: size * 2, height: size * 0.44),
                                  cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil)
                context.addPath(pill)
                context.fillPath()
            default:
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -size * 0.9, y: 0))
                path.addCurve(to: CGPoint(x: size * 0.9, y: 0), control1: CGPoint(x: -size * 0.3, y: size * 0.9),
                              control2: CGPoint(x: size * 0.3, y: -size * 0.9))
                context.addPath(path)
                context.setStrokeColor(color(hex, 0.9))
                context.setLineWidth(max(1, size * 0.22))
                context.setLineCap(.round)
                context.strokePath()
            }
            context.restoreGState()
        }
    }

    private static func drawStripes(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, scale: CGFloat) {
        let colors = style.colors
        context.setFillColor(color(colors[0]))
        context.fill(bounds)
        let stripe = 26 * scale, gap = 46 * scale
        context.saveGState()
        context.setFillColor(color(colors[1]))
        var x = -bounds.height
        while x < bounds.width + bounds.height {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: bounds.minY))
            path.addLine(to: CGPoint(x: x + stripe, y: bounds.minY))
            path.addLine(to: CGPoint(x: x + stripe + bounds.height, y: bounds.maxY))
            path.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
            path.closeSubpath()
            context.addPath(path)
            x += stripe + gap
        }
        context.fillPath()
        context.restoreGState()
        glow(colors[2], alpha: 0.35, at: CGPoint(x: bounds.width * 0.15, y: bounds.height * 0.1), radius: bounds.width * 0.45, in: context)
        glow(colors[2], alpha: 0.2, at: CGPoint(x: bounds.width * 0.95, y: bounds.height * 0.95), radius: bounds.width * 0.35, in: context)
    }

    private static func drawGrid(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, scale: CGFloat,
                                 random: inout NoteCoverRandom) {
        let colors = style.colors
        linear([color(colors[0]), color(colors[1])], in: context,
               from: CGPoint(x: 0, y: bounds.minY), to: CGPoint(x: bounds.width, y: bounds.maxY))
        let step = 30 * scale
        context.setStrokeColor(color(colors[2], 0.12))
        context.setLineWidth(max(0.5, scale))
        var x: CGFloat = 0
        while x <= bounds.maxX { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: bounds.maxY)); x += step * 4 }
        var y: CGFloat = 0
        while y <= bounds.maxY { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: bounds.maxX, y: y)); y += step * 4 }
        context.strokePath()
        context.setFillColor(color(colors[2], 0.45))
        let dot = max(1, 2.4 * scale)
        y = step / 2
        while y < bounds.maxY {
            x = step / 2
            while x < bounds.maxX {
                context.fillEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                x += step
            }
            y += step
        }
        context.setStrokeColor(color(colors[2], 0.5))
        context.setLineWidth(max(1, 2 * scale))
        for _ in 0..<3 {
            let radius = random.between(60, 160) * scale
            let center = CGPoint(x: bounds.width * random.between(0.1, 0.9), y: bounds.height * random.between(0.2, 0.8))
            context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private static func drawRipples(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, random: inout NoteCoverRandom) {
        let colors = style.colors
        context.setFillColor(color(colors[0]))
        context.fill(bounds)
        let center = CGPoint(x: bounds.width * random.between(0.6, 0.8), y: bounds.height * random.between(0.2, 0.45))
        let maximum = hypot(bounds.width, bounds.height)
        let rings = 14
        for ring in (0..<rings).reversed() {
            let radius = maximum * CGFloat(ring + 1) / CGFloat(rings)
            let hex = colors[ring % (colors.count - 1) + 1]
            context.setFillColor(color(hex, 0.18 + 0.05 * CGFloat(rings - ring) / CGFloat(rings)))
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        glow(colors[0], alpha: 0.55, at: center, radius: maximum * 0.18, in: context)
    }

    private static func drawPaper(_ style: NoteCoverStyle, in context: CGContext, bounds: CGRect, sand: CGImage?) {
        let colors = style.colors
        linear([color(colors[0]), color(colors[1])], in: context,
               from: CGPoint(x: 0, y: bounds.maxY), to: CGPoint(x: bounds.width, y: bounds.minY))
        if let sand {
            context.saveGState()
            context.setBlendMode(.multiply)
            context.setAlpha(0.18)
            context.draw(sand, in: CGRect(x: 0, y: 0, width: sand.width * 2, height: sand.height * 2), byTiling: true)
            context.restoreGState()
        }
        glow(colors[2], alpha: 0.25, at: CGPoint(x: bounds.width * 0.1, y: bounds.height * 0.9), radius: bounds.width * 0.4, in: context)
        glow(0xFFFFFF, alpha: 0.45, at: CGPoint(x: bounds.width * 0.75, y: bounds.height * 0.35), radius: bounds.width * 0.35, in: context)
    }
}
