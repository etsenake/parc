import AppKit
func load(_ path: String) -> (data: [UInt8], width: Int, height: Int) {
    let image = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let width = image.width, height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (data, width, height)
}
let a = load(CommandLine.arguments[1]), b = load(CommandLine.arguments[2])
var worst = 0, differing = 0, minX = Int.max, minY = Int.max, maxX = 0, maxY = 0
for i in stride(from: 0, to: a.data.count, by: 4) {
    var m = 0
    for c in 0..<4 { m = max(m, abs(Int(a.data[i + c]) - Int(b.data[i + c]))) }
    worst = max(worst, m); if m > 8 { differing += 1; let p = i / 4; minX = min(minX, p % a.width); maxX = max(maxX, p % a.width); minY = min(minY, p / a.width); maxY = max(maxY, p / a.width) }
}
print("size", a.width, a.height, "max diff", worst, "pixels >8:", differing, "bbox", minX, minY, maxX, maxY, "corner alpha a", a.data[3], "b", b.data[3])
