import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct BrandMarkChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard let color = ParcBrandMark.image(.borderless),
              let mono = ParcBrandMark.image(.monochrome) else {
            preconditionFailure("Both production brand marks must be packaged")
        }
        precondition(!color.isTemplate && mono.isTemplate)
        precondition(color.size == mono.size && color.size.height > color.size.width)
        precondition(ParcBrandMark.image(.borderless, resources: nil) == nil)
        precondition(ParcBrandMark.image(.monochrome, resources: URL(fileURLWithPath: "/missing-parc-resources")) == nil)

        func pixels(_ image: NSImage) -> [UInt8] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width),
                pixelsHigh: Int(image.size.height), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: Int(image.size.width) * 4, bitsPerPixel: 32)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            return Array(UnsafeBufferPointer(start: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
        }
        let colored = pixels(color), template = pixels(mono)
        precondition(colored.count == template.count)
        var visible = 0, transparent = 0
        for offset in stride(from: 0, to: colored.count, by: 4) {
            precondition(colored[offset + 3] == template[offset + 3], "Color and template silhouettes must agree exactly")
            if template[offset + 3] > 0 { visible += 1 }
            else { transparent += 1 }
        }
        precondition(visible > 10_000 && transparent > 10_000, "The mark must retain its open bowl and transparent exterior")

        for (name, background, ink) in [("light", NSColor.white, NSColor.black),
                                         ("dark", NSColor.black, NSColor.white)] {
            let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(background.cgColor); context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            ParcBrandMark.drawMonochrome(mono, in: CGRect(x: 32, y: 16, width: 64, height: 96), color: ink, context: context)
            let raw = context.data!.assumingMemoryBound(to: UInt8.self)
            let expectedBackground: UInt8 = name == "light" ? 255 : 0
            var changed = 0
            for y in 0..<128 {
                for x in 0..<128 {
                    let offset = y * 512 + x * 4
                    precondition(raw[offset] == raw[offset + 1] && raw[offset] == raw[offset + 2], "The monochrome mark may not leak original red or blue")
                    precondition(raw[offset + 3] == 255)
                    if x < 32 || x >= 96 || y < 16 || y >= 112 { precondition(raw[offset] == expectedBackground) }
                    if raw[offset] != expectedBackground { changed += 1 }
                }
            }
            precondition(changed > 1000 && changed < 64 * 96, "The real mask must paint ink and preserve its negative space")
            if CommandLine.arguments.count > 1 {
                let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("mark-\(name).png")
                let sink = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(sink, context.makeImage()!, nil)
                precondition(CGImageDestinationFinalize(sink))
            }
        }
        print("Bundled brand-mark identity, alpha, missing-resource, monochrome tint and light/dark drawing checks passed.")
    }
}
