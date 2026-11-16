import Foundation
import CoreGraphics
import CoreText
import CoreImage

public enum Fonts {
    public static func register(_ dir: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for u in urls where u.pathExtension.lowercased() == "ttf" || u.pathExtension.lowercased() == "otf" {
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(u as CFURL, .process, &err) {
                let e = err?.takeRetainedValue()
                if let e, CFErrorGetCode(e) != 105 { FileHandle.standardError.write("font \(u.lastPathComponent): \(e)\n".data(using: .utf8)!) }
            }
        }
    }

    public static func font(_ name: String, _ size: Double, weight: Double? = nil) -> CTFont {
        var attrs: [CFString: Any] = [kCTFontNameAttribute: name]
        if let weight {
            attrs[kCTFontVariationAttribute] = [0x77676874: weight]
        }
        let d = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }
}

public struct TextImage {
    public let image: CIImage
    public let size: CGSize
    public let baseline: Double
    public let pad: Double

    public static func make(_ string: String, font: CTFont, color: CGColor, tracking: Double = 0, scale: Double, pad: Double = 24) -> TextImage {
        let kern = tracking / 1000 * Double(CTFontGetSize(font))
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: kern]
        let astr = CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(astr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading) - kern
        let w = Double(width) + pad * 2
        let h = Double(ascent + descent) + pad * 2
        let pw = Int(ceil(w * scale)), ph = Int(ceil(h * scale))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsAntialiasing(true)
        ctx.textPosition = CGPoint(x: pad, y: pad + Double(descent))
        CTLineDraw(line, ctx)
        let img = CIImage(cgImage: ctx.makeImage()!)
        return TextImage(image: img, size: CGSize(width: w, height: h), baseline: pad + Double(ascent), pad: pad)
    }

    public static func wordOffsets(_ string: String, font: CTFont, tracking: Double) -> [(String, Double)] {
        let kern = tracking / 1000 * Double(CTFontGetSize(font))
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTKernAttributeName: kern]
        let astr = CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(astr)
        var out: [(String, Double)] = []
        let ns = string as NSString
        var idx = 0
        for word in string.split(separator: " ", omittingEmptySubsequences: true) {
            let r = ns.range(of: String(word), range: NSRange(location: idx, length: ns.length - idx))
            let x = Double(CTLineGetOffsetForStringIndex(line, r.location, nil))
            out.append((String(word), x))
            idx = r.location + r.length
        }
        return out
    }

    public static func lineWidth(_ string: String, font: CTFont, tracking: Double) -> Double {
        let kern = tracking / 1000 * Double(CTFontGetSize(font))
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTKernAttributeName: kern]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary)!)
        return CTLineGetTypographicBounds(line, nil, nil, nil) - kern
    }
}

public struct TitleStyle {
    public var font: CTFont
    public var color: CGColor
    public var tracking: Double = 0
    public var stagger = 0.075
    public var rise = 0.28
    public var fadeIn = 0.9
    public var blurIn = 9.0
    public var fadeOut = 0.45
    public var pixelScale = 4.0
    public init(font: CTFont, color: CGColor, tracking: Double = 0) {
        self.font = font; self.color = color; self.tracking = tracking
    }
}

public enum Titles {
    public static func words(_ text: String, style: TitleStyle, center: Vec3, space: LayerSpace = .world, appear: Double, leave: Double?) -> [Layer] {
        let size = Double(CTFontGetSize(style.font))
        let total = TextImage.lineWidth(text, font: style.font, tracking: style.tracking)
        let offsets = TextImage.wordOffsets(text, font: style.font, tracking: style.tracking)
        var layers: [Layer] = []
        for (i, (word, x)) in offsets.enumerated() {
            let ti = TextImage.make(word, font: style.font, color: style.color, tracking: style.tracking, scale: style.pixelScale)
            let wordW = Double(ti.size.width) - ti.pad * 2
            let cx = center.x - total / 2 + x + wordW / 2
            let cy = center.y
            let start = appear + Double(i) * style.stagger
            let l = Layer("title:\(word)", space: space, size: ti.size, at: Vec3(cx, cy + size * style.rise, center.z), image: ti.image)
            l.depthOfField = space == .world
            l.position = Track(Vec3(cx, cy + size * style.rise, center.z))
                .holding(until: start)
                .keyed(start + style.fadeIn * 1.5, Vec3(cx, cy, center.z), .spring(response: 1.1, damping: 1))
            l.opacity = Track(0).holding(until: start).keyed(start + style.fadeIn, 1, .bezier(0.33, 0, 0.2, 1))
            l.blur = Track(style.blurIn).holding(until: start).keyed(start + style.fadeIn * 0.9, 0, .out)
            if let leave {
                let ls = leave + Double(i) * style.stagger * 0.5
                l.opacity = l.opacity.holding(until: ls).keyed(ls + style.fadeOut, 0, .gentle)
                l.blur = l.blur.holding(until: ls).keyed(ls + style.fadeOut, style.blurIn * 0.6, .gentle)
                l.position = l.position.holding(until: ls).keyed(ls + style.fadeOut, Vec3(cx, cy - size * 0.08, center.z), .gentle)
            }
            layers.append(l)
        }
        return layers
    }
}
