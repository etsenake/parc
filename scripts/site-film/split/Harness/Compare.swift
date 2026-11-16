import AppKit

@MainActor enum Compare {
    static func pixels(_ rep: NSBitmapImageRep) -> (data: [UInt8], width: Int, height: Int) {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    static func report(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, regions: [(String, NSRect)], label: String) {
        let pa = pixels(a), pb = pixels(b)
        guard pa.width == pb.width, pa.height == pb.height else { print("size mismatch"); return }
        let scale = CGFloat(pa.width) / 1440
        for (name, rect) in regions {
            var total = 0.0, count = 0, differing = 0
            let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale), y0 = Int(rect.minY * scale), y1 = Int(rect.maxY * scale)
            for y in stride(from: y0, to: y1, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) {
                    let i = (y * pa.width + x) * 4
                    var worst = 0
                    for c in 0..<4 { worst = max(worst, abs(Int(pa.data[i + c]) - Int(pb.data[i + c]))) }
                    total += Double(worst); count += 1
                    if worst > 24 { differing += 1 }
                }
            }
            print("\(label) \(name): mean max-channel diff \(String(format: "%.2f", total / Double(max(1, count)))), pixels differing >24: \(String(format: "%.2f", 100 * Double(differing) / Double(max(1, count))))%")
        }
    }
}
