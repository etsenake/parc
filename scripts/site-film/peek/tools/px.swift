import AppKit
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
var args = Array(CommandLine.arguments.dropFirst(2))
while args.count >= 2 {
    let x = Int(args.removeFirst())!, y = Int(args.removeFirst())!
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    print(x, y, String(format: "%.3f %.3f %.3f a%.3f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent))
}
