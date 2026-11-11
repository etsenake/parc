import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class CapturedImage {
    let originalPixels: CGImage
    let originalPNG: Data
    let backingScale: CGFloat
    private(set) var sourcePixels: CGImage
    private(set) var sourcePNG: Data
    private var cropRect: CGRect?
    private(set) var unframedPixels: CGImage
    private(set) var unframedPNG: Data
    private(set) var pixels: CGImage
    private(set) var pngData: Data
    private(set) var frame: PortraitCaptureComposition?
    var isOriginalOutput: Bool { cropRect == nil && frame == nil && sourcePixels === originalPixels }

    init(pngData: Data, backingScale: CGFloat = 1) throws {
        guard backingScale.isFinite, backingScale >= 1, backingScale <= 4 else { throw PortraitCaptureError.encoding }
        self.backingScale = backingScale
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PortraitCaptureError.encoding }
        originalPixels = image; originalPNG = pngData
        sourcePixels = image; sourcePNG = pngData
        unframedPixels = image; unframedPNG = pngData; pixels = image; self.pngData = pngData
    }

    func applyFrame(_ composition: PortraitCaptureComposition) throws {
        let rendered = try composition.render(unframedPixels)
        let encoded = try Self.png(rendered, backingScale: composition.backingScale)
        frame = composition; pixels = rendered; pngData = encoded
    }

    func removeFrame() {
        frame = nil; pixels = unframedPixels; pngData = unframedPNG
    }

    func applyEditedOriginal(_ edited: CGImage) throws {
        guard edited.width == originalPixels.width, edited.height == originalPixels.height else { throw PortraitCaptureError.encoding }
        let sourceData = try Self.png(edited, backingScale: backingScale)
        let cropped: CGImage
        if let cropRect {
            guard let value = edited.cropping(to: cropRect) else { throw PortraitCaptureError.encoding }
            cropped = value
        } else { cropped = edited }
        let data = cropRect == nil ? sourceData : try Self.png(cropped, backingScale: backingScale)
        let rendered = try frame?.render(cropped) ?? cropped
        let encoded = frame == nil ? data : try Self.png(rendered, backingScale: frame?.backingScale ?? backingScale)
        sourcePixels = edited; sourcePNG = sourceData
        unframedPixels = cropped; unframedPNG = data; pixels = rendered; pngData = encoded
    }

    func crop(to rect: CGRect) throws {
        let bounds = CGRect(x: 0, y: 0, width: sourcePixels.width, height: sourcePixels.height)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { throw PortraitCaptureError.encoding }
        let crop = rect.integral.intersection(bounds)
        guard !crop.isEmpty, !crop.isNull,
              let image = sourcePixels.cropping(to: crop) else { throw PortraitCaptureError.encoding }
        let data = crop == bounds ? sourcePNG : try Self.png(image, backingScale: backingScale)
        let rendered = try frame?.render(image) ?? image
        let encoded = frame == nil ? data : try Self.png(rendered, backingScale: frame?.backingScale ?? backingScale)
        cropRect = crop == bounds ? nil : crop
        unframedPixels = image; unframedPNG = data; pixels = rendered; pngData = encoded
    }

    private static func png(_ image: CGImage, backingScale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw PortraitCaptureError.encoding
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * backingScale,
                                                        kCGImagePropertyDPIHeight: 72 * backingScale] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PortraitCaptureError.encoding }
        return data as Data
    }
}
