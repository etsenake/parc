import AppKit
let path = CommandLine.arguments[1]
let y0 = Int(CommandLine.arguments[2])!, y1 = Int(CommandLine.arguments[3])!
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path)))!
var boxes: [(Int, Int, Int, Int)] = []
for y in y0..<y1 {
    var x = 0
    while x < rep.pixelsWide {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        if c.blueComponent > 0.8 && c.redComponent < 0.45 && c.greenComponent < 0.6 {
            var e = x
            while e + 1 < rep.pixelsWide, let d = rep.colorAt(x: e + 1, y: y)?.usingColorSpace(.sRGB), d.blueComponent > 0.8 && d.redComponent < 0.45 { e += 1 }
            if e - x > 12 { print("underline-ish run y=\(y) x=\(x)...\(e)") }
            x = e + 1
        } else { x += 1 }
    }
}
