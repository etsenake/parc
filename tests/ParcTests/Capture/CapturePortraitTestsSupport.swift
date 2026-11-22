import AppKit
import ImageIO
import ParcTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ParcLibrary

enum CapturePortraitTestsSupport {
    @MainActor
    final class PortraitFixture {
        let defaults: UserDefaults
        var options: PortraitCaptureOptions
        let source: CGImage
        let original: Data
        let palette = PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor")
        let wallpaper = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { rect in
            NSColor.cyan.setFill()
            rect.fill()
            return true
        }

        init() throws {
            defaults = TestDefaults("ParcPortraitTests-")!
            options = PortraitCaptureOptions(defaults: defaults)
            let context = Self.context(width: 320, height: 160)
            context.setFillColor(NSColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            context.setFillColor(NSColor.blue.cgColor)
            context.fill(CGRect(x: 160, y: 0, width: 160, height: 160))
            source = context.makeImage()!
            original = try Self.png(source)
        }

        static func context(width: Int, height: Int, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGContext {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }

        static func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
            let pixel = context(width: 1, height: 1)
            pixel.interpolationQuality = .none
            pixel.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: pixel.data!.assumingMemoryBound(to: UInt8.self), count: 4))
        }

        static func png(_ image: CGImage) throws -> Data {
            let bytes = NSMutableData()
            let sink = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(sink, image, nil)
            #expect(CGImageDestinationFinalize(sink))
            return bytes as Data
        }

        func render(_ options: PortraitCaptureOptions? = nil, color: NSColor? = .green, desktop: NSImage? = nil,
                    backingScale: CGFloat = 1, source override: CGImage? = nil) throws -> CGImage {
            try PortraitCaptureRenderer.render(source: override ?? source, options: options ?? self.options, palette: palette,
                                               pageColor: color, desktop: desktop, backingScale: backingScale)
        }

        func composition(_ options: PortraitCaptureOptions? = nil, backingScale: CGFloat = 1, hasDesktop: Bool = true) -> PortraitCaptureComposition {
            var composition = PortraitCaptureComposition(options: options ?? self.options, palette: palette, pageColor: .green,
                                                         desktop: hasDesktop ? wallpaper : nil)
            composition.backingScale = backingScale
            return composition
        }

        func framed(_ background: PortraitCaptureOptions.Background = .page, backingScale: CGFloat = 1) throws -> (CapturedImage, PortraitCaptureComposition) {
            var options = self.options
            options.background = background
            let style = composition(options, backingScale: backingScale)
            let capture = try CapturedImage(pngData: original, backingScale: backingScale)
            try capture.applyFrame(style)
            return (capture, style)
        }
    }
}
