import AppKit
func load(_ p: String) -> (Int, Int, [UInt8]) {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: p)))!
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var d = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, d)
}
let a = load(CommandLine.arguments[1]), b = load(CommandLine.arguments[2])
for (x, y, name) in [(20, 20, "corner"), (1440, 1790, "below window shadow"), (1440, 1760, "shadow near edge"), (150, 900, "left shadow"), (1440, 900, "page"), (400, 400, "sidebar"), (2000, 150, "toast area")] {
    let i = (y * a.0 + x) * 4
    print(name, "movie", Array(a.2[i..<i+4]), "still", Array(b.2[i..<i+4]))
}
var total = 0.0, n = 0, worst = 0
for y in stride(from: 0, to: a.1, by: 3) { for x in stride(from: 0, to: a.0, by: 3) {
    let i = (y * a.0 + x) * 4
    var m = 0; for c in 0..<4 { m = max(m, abs(Int(a.2[i+c]) - Int(b.2[i+c]))) }
    total += Double(m); n += 1; worst = max(worst, m)
} }
print("mean max-channel diff", total / Double(n), "worst", worst)
