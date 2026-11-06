import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Notes' original picker returns one NSImage from JPEG, PNG, PDF, BMP or TIFF.
/// Parc's local attributed carrier stores validated raster bytes. Existing raster
/// formats keep their bytes; BMP and the first PDF page become a bounded PNG.
@MainActor
enum NoteImageImport {
    private static let byteLimit = 4_194_304
    private static let pixelLimit = 16_777_216.0

    static func makePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .pdf, .bmp, .tiff]
        return panel
    }

    static func attachmentData(from url: URL) throws -> Data {
        guard url.isFileURL else { throw EaselStoreError.invalidImage }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let count = values.fileSize,
              count > 0, count <= byteLimit else { throw EaselStoreError.invalidImage }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: byteLimit + 1), data.count <= byteLimit else { throw EaselStoreError.tooLarge }
        return try attachmentData(data)
    }

    static func attachmentData(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= byteLimit else { throw EaselStoreError.invalidImage }
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as String?, type != UTType.pdf.identifier {
            if [UTType.jpeg.identifier, UTType.png.identifier, UTType.tiff.identifier].contains(type) {
                _ = try EaselTextAttachments.image(data: data)
                return data
            }
            guard type == UTType.bmp.identifier, CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  validSize(NSSize(width: width, height: height)),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let native = NSImage(data: data), validSize(native.size) else { throw EaselStoreError.invalidImage }
            let bitmap = NSBitmapImageRep(cgImage: image)
            bitmap.size = native.size
            return try png(bitmap)
        }
        // NSImage's PDF representation initially selects page zero. Rasterize
        // that page only, at one pixel per point, independently of screen scale.
        // This is a local storage adaptation, not a PDF document/page importer.
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), document.isUnlocked,
              document.numberOfPages > 0, let image = NSPDFImageRep(data: data) else { throw EaselStoreError.invalidImage }
        image.currentPage = 0
        let size = image.size
        guard validSize(size) else { throw EaselStoreError.invalidImage }
        let width = Int(ceil(size.width)), height = Int(ceil(size.height))
        guard Double(width) * Double(height) <= pixelLimit,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw EaselStoreError.invalidImage }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.cgContext.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        guard image.draw(in: NSRect(origin: .zero, size: size)) else { throw EaselStoreError.invalidImage }
        return try png(bitmap)
    }

    private static func validSize(_ size: NSSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && size.width <= 20_000 && size.height <= 20_000 && size.width * size.height <= pixelLimit
    }

    private static func png(_ bitmap: NSBitmapImageRep) throws -> Data {
        guard let data = bitmap.representation(using: .png, properties: [:]), data.count <= byteLimit else {
            throw EaselStoreError.tooLarge
        }
        _ = try EaselTextAttachments.image(data: data)
        return data
    }
}
