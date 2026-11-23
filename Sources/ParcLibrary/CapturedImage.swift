import AppKit
import ImageIO
import ParcCore
import UniformTypeIdentifiers

@MainActor
package final class CapturedImage {
    package let originalPixels: CGImage
    package let originalPNG: Data
    package let backingScale: CGFloat
    package private(set) var sourcePixels: CGImage
    private(set) var sourcePNG: Data
    private var cropRect: CGRect?
    package private(set) var unframedPixels: CGImage
    private(set) var unframedPNG: Data
    package private(set) var pixels: CGImage
    package private(set) var pngData: Data
    package private(set) var frame: PortraitCaptureComposition?
    package var isOriginalOutput: Bool { cropRect == nil && frame == nil && sourcePixels === originalPixels }

    package init(pngData: Data, backingScale: CGFloat = 1) throws {
        guard backingScale.isFinite, backingScale >= 1, backingScale <= 4 else { throw PortraitCaptureError.encoding }
        self.backingScale = backingScale
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PortraitCaptureError.encoding }
        let pngData = Self.declaringDensity(pngData, backingScale: backingScale)
        originalPixels = image; originalPNG = pngData
        sourcePixels = image; sourcePNG = pngData
        unframedPixels = image; unframedPNG = pngData; pixels = image; self.pngData = pngData
    }

    package func applyFrame(_ composition: PortraitCaptureComposition) throws {
        let (rendered, encoded) = try Self.framed(unframedPixels, composition)
        frame = composition; pixels = rendered; pngData = encoded
    }

    static func framed(_ source: CGImage, _ composition: PortraitCaptureComposition,
                       maximumBytes: Int = EaselStore.maximumAssetBytes) throws -> (CGImage, Data) {
        var reduction: CGFloat = 1
        var attempt = 0
        while true {
            let (image, density) = try composition.render(source, reduction: reduction)
            let data = try png(image, backingScale: density)
            attempt += 1
            guard data.count > maximumBytes, attempt < 8, image.width > 1 || image.height > 1 else { return (image, data) }
            reduction *= min(0.95, sqrt(CGFloat(maximumBytes) / CGFloat(data.count)) * 0.97)
        }
    }

    package func removeFrame() {
        frame = nil; pixels = unframedPixels; pngData = unframedPNG
    }

    package func applyEditedOriginal(_ edited: CGImage) throws {
        guard edited.width == originalPixels.width, edited.height == originalPixels.height else { throw PortraitCaptureError.encoding }
        let sourceData = try Self.png(edited, backingScale: backingScale)
        let cropped: CGImage
        if let cropRect {
            guard let value = edited.cropping(to: cropRect) else { throw PortraitCaptureError.encoding }
            cropped = value
        } else { cropped = edited }
        let data = cropRect == nil ? sourceData : try Self.png(cropped, backingScale: backingScale)
        let (rendered, encoded) = try frame.map { try Self.framed(cropped, $0) } ?? (cropped, data)
        sourcePixels = edited; sourcePNG = sourceData
        unframedPixels = cropped; unframedPNG = data; pixels = rendered; pngData = encoded
    }

    package func crop(to rect: CGRect) throws {
        let bounds = CGRect(x: 0, y: 0, width: sourcePixels.width, height: sourcePixels.height)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { throw PortraitCaptureError.encoding }
        let crop = rect.integral.intersection(bounds)
        guard !crop.isEmpty, !crop.isNull,
              let image = sourcePixels.cropping(to: crop) else { throw PortraitCaptureError.encoding }
        let data = crop == bounds ? sourcePNG : try Self.png(image, backingScale: backingScale)
        let (rendered, encoded) = try frame.map { try Self.framed(image, $0) } ?? (image, data)
        cropRect = crop == bounds ? nil : crop
        unframedPixels = image; unframedPNG = data; pixels = rendered; pngData = encoded
    }

    package static func declaringDensity(_ png: Data, backingScale: CGFloat) -> Data {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let bytes = [UInt8](png)
        guard backingScale > 1, bytes.count > 33, Array(bytes[0..<8]) == signature else { return png }
        func length(at offset: Int) -> Int {
            bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        func type(at offset: Int) -> String { String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self) }
        let perMetre = UInt32((72 * backingScale / 0.0254).rounded())
        let wanted = withUnsafeBytes(of: perMetre.bigEndian, Array.init) + withUnsafeBytes(of: perMetre.bigEndian, Array.init) + [1]
        var output = Array(bytes[0..<8])
        var offset = 8, inserted = false
        while offset + 12 <= bytes.count {
            let size = length(at: offset), name = type(at: offset)
            let end = offset + 12 + size
            guard end <= bytes.count else { return png }
            if name == "pHYs" {
                if size == 9 && Array(bytes[offset + 8..<offset + 17]) == wanted { return png }
            } else {
                output += bytes[offset..<end]
                if name == "IHDR" { output += chunk("pHYs", wanted); inserted = true }
            }
            offset = end
        }
        return inserted && offset == bytes.count ? Data(output) : png
    }

    private static func chunk(_ name: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(name.utf8) + body
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in typed {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        crc ^= 0xFFFF_FFFF
        return withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init) + typed + withUnsafeBytes(of: crc.bigEndian, Array.init)
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
