import AppKit

@MainActor
final class EaselPictureCache {
    static let shared = EaselPictureCache()

    struct Key: Hashable {
        let asset: String
        let width: Int
        let height: Int
    }

    let pixelBudget: Int
    private var entries: [Key: CGImage] = [:]
    private var order: [Key] = []
    private(set) var pixelTotal = 0

    init(pixelBudget: Int = 24_000_000) {
        self.pixelBudget = pixelBudget
    }

    func image(_ key: Key, make: () -> CGImage?) -> CGImage? {
        if let image = entries[key] {
            if let index = order.firstIndex(of: key) { order.remove(at: index) }
            order.append(key)
            return image
        }
        guard let image = make() else { return nil }
        entries[key] = image
        order.append(key)
        pixelTotal += image.width * image.height
        while pixelTotal > pixelBudget, order.count > 1 {
            let oldest = order.removeFirst()
            if let gone = entries.removeValue(forKey: oldest) { pixelTotal -= gone.width * gone.height }
        }
        return image
    }

    func pixelSizes(of asset: String) -> Set<EaselPixelSize> {
        Set(entries.keys.filter { $0.asset == asset }.map { EaselPixelSize(width: $0.width, height: $0.height) })
    }
}

struct EaselPixelSize: Hashable {
    let width: Int
    let height: Int
}

@MainActor
enum EaselPictureRenderer {
    static let levelsPerOctave: Double = 4

    static func draw(_ picture: NSImage, asset: String?, in rect: NSRect) {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite, let graphics = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        graphics.imageInterpolation = .high
        let source = asset.flatMap { reduced(picture, asset: $0, in: rect, graphics: graphics, cache: .shared) }
            .map { NSImage(cgImage: $0, size: rect.size) } ?? picture
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    static func level(native: EaselPixelSize, target: CGSize) -> EaselPixelSize? {
        guard native.width > 0, native.height > 0, target.width.isFinite, target.height.isFinite,
              target.width > 0, target.height > 0 else { return nil }
        let ratio = max(target.width / CGFloat(native.width), target.height / CGFloat(native.height))
        guard ratio < 1 else { return nil }
        let step = floor(-levelsPerOctave * log2(Double(ratio)))
        guard step >= 1 else { return nil }
        let scale = pow(2, -step / levelsPerOctave)
        return EaselPixelSize(width: max(1, Int((Double(native.width) * scale).rounded(.up))),
                              height: max(1, Int((Double(native.height) * scale).rounded(.up))))
    }

    static func downsample(_ image: CGImage, to size: EaselPixelSize) -> CGImage? {
        let spaces = [image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for space in spaces {
            guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return context.makeImage()
        }
        return nil
    }

    static func nativeSize(of picture: NSImage) -> EaselPixelSize? {
        if let rep = picture.representations.lazy.compactMap({ $0 as? NSBitmapImageRep }).first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return EaselPixelSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return fullImage(of: picture).map { EaselPixelSize(width: $0.width, height: $0.height) }
    }

    private static func fullImage(of picture: NSImage) -> CGImage? {
        if let image = picture.representations.lazy.compactMap({ ($0 as? NSBitmapImageRep)?.cgImage }).first { return image }
        return picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func reduced(_ picture: NSImage, asset: String, in rect: NSRect, graphics: NSGraphicsContext,
                                cache: EaselPictureCache) -> CGImage? {
        guard graphics.isDrawingToScreen, let native = nativeSize(of: picture) else { return nil }
        let ctm = graphics.cgContext.ctm
        let device = sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c))
        guard device.isFinite, device > 0,
              let size = level(native: native, target: CGSize(width: rect.width * device, height: rect.height * device)),
              size.width * size.height <= cache.pixelBudget / 4 else { return nil }
        return cache.image(EaselPictureCache.Key(asset: asset, width: size.width, height: size.height)) {
            fullImage(of: picture).flatMap { downsample($0, to: size) }
        }
    }
}
