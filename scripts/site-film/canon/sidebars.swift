import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
let output = args[0]
let crop = CGRect(x: 160, y: 36, width: 470, height: 1300)
var tiles: [(String, CGImage)] = []
for item in args.dropFirst() {
    let parts = item.split(separator: "@")
    let path = String(parts[0]), time = Double(parts[1])!
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
    generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
    let duration = CMTimeGetSeconds(AVURLAsset(url: URL(fileURLWithPath: path)).duration)
    let at = time < 0 ? duration + time : time
    let image = try generator.copyCGImage(at: CMTime(seconds: at, preferredTimescale: 600), actualTime: nil)
    let label = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent + String(format: " %.2f", at)
    tiles.append((label, image.cropping(to: crop)!))
}
let scale = 0.5, gap = 12.0, labelHeight = 36.0
let w = Int(Double(tiles.count) * (crop.width * scale + gap)), h = Int(crop.height * scale + labelHeight)
let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(gray: 0.15, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
for (index, tile) in tiles.enumerated() {
    let x = Double(index) * (crop.width * scale + gap)
    context.draw(tile.1, in: CGRect(x: x, y: 0, width: crop.width * scale, height: crop.height * scale))
    (tile.0 as NSString).draw(at: NSPoint(x: x + 4, y: crop.height * scale + 8),
                              withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white])
}
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil); CGImageDestinationFinalize(destination)
print("wrote", output, w, h)
