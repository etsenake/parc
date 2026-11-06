// Native, offline raster export. This changes framing, never the approved art.
import Foundation
import CoreGraphics
import CoreImage
import ImageIO

enum IconExportError: Error { case invalidSource, emptyArtwork, renderFailed }

func exportIcon(source: URL, directory: URL, mascot: Bool) throws {
    guard let decoder = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil),
          image.width == image.height, (1024...4096).contains(image.width),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let measure = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                  CGBitmapInfo.byteOrder32Big.rawValue) else { throw IconExportError.invalidSource }
    measure.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = measure.data?.assumingMemoryBound(to: UInt8.self) else { throw IconExportError.renderFailed }
    var left = image.width, top = image.height, right = 0, bottom = 0
    for y in 0..<image.height {
        for x in 0..<image.width where data[y * measure.bytesPerRow + x * 4 + 3] >= 128 {
            left = min(left, x); top = min(top, y)
            right = max(right, x + 1); bottom = max(bottom, y + 1)
        }
    }
    guard right > left, bottom > top else { throw IconExportError.emptyArtwork }
    //
    // The terminal mascot occupies 204 / 256, with its center 2 / 256 lower.
    // Preserve each approved Parc silhouette/aspect instead of stretching it.
    let extent = mascot ? 204.0 / 256.0 : 824.0 / 1024.0
    let centerY = mascot ? 130.0 / 256.0 : 0.5
    let sourceExtent = Double(max(right - left, bottom - top))
    let context = CIContext(options: [.useSoftwareRenderer: true,
                                      .workingColorSpace: space, .outputColorSpace: space])
    let original = CIImage(cgImage: image)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            // Snap the dominant opaque extent and center to the pixel grid.
            // The 16px result has a 13px body, 32px has 26px; high-density
            // representations are drawn independently from the full master.
            let body = (Double(pixels) * extent).rounded()
            let ratio = body / sourceExtent
            let targetX = ((Double(pixels) - body) / 2).rounded(.down) + body / 2
            let targetY = ((Double(pixels) * centerY - body / 2)).rounded(.down) + body / 2
            let x = targetX - Double(left + right) / 2 * ratio
            let yFromTop = targetY - Double(top + bottom) / 2 * ratio
            let height = Double(image.height) * ratio
            // Core Image's origin is lower-left; measured rows are top-first.
            // Explicit Lanczos downsampling keeps narrow neon/glass details
            // from being blurred by a context's implicit reduction stages.
            let scaled = original.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: ratio, kCIInputAspectRatioKey: 1.0
            ]).transformed(by: CGAffineTransform(translationX: x,
                                                 y: Double(pixels) - yFromTop - height))
            // Lanczos' outer lobe can reach the canvas edge at 16px even
            // though the opaque artwork is inset. Keep a transparent guard
            // pixel; this removes only the outer resampling fringe.
            let inset = scaled.cropped(to: CGRect(x: 1, y: 1, width: pixels - 2, height: pixels - 2))
            let suffix = scale == 2 ? "@2x" : ""
            let path = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
            guard let result = context.createCGImage(inset, from: CGRect(x: 0, y: 0, width: pixels, height: pixels),
                                                     format: .RGBA8, colorSpace: space),
                  let writer = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)
            else { throw IconExportError.renderFailed }
            CGImageDestinationAddImage(writer, result, nil)
            guard CGImageDestinationFinalize(writer) else { throw IconExportError.renderFailed }
        }
    }
}

do {
    guard CommandLine.arguments.count == 4, ["tile", "mascot"].contains(CommandLine.arguments[3])
    else { throw IconExportError.invalidSource }
    try exportIcon(source: URL(fileURLWithPath: CommandLine.arguments[1]),
                   directory: URL(fileURLWithPath: CommandLine.arguments[2]),
                   mascot: CommandLine.arguments[3] == "mascot")
} catch {
    FileHandle.standardError.write(Data("App icon export failed: \(error)\n".utf8))
    exit(1)
}
