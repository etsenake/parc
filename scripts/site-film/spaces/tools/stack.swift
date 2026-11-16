import AppKit
let paths = Array(CommandLine.arguments.dropFirst().dropLast())
let images = paths.compactMap { NSImage(contentsOfFile: $0) }
let width = images.map { $0.size.width }.max() ?? 0, height = images.reduce(0) { $0 + $1.size.height + 6 }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.black.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
var y = height
for image in images { y -= image.size.height + 6; image.draw(in: NSRect(x: 0, y: y, width: image.size.width, height: image.size.height)) }
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments.last!))
