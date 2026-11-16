import AppKit
let args = Array(CommandLine.arguments.dropFirst())
let images = args.dropFirst().map { NSImage(contentsOfFile: $0)! }
let w = images.reduce(0) { $0 + $1.size.width + 8 }, h = images.map(\.size.height).max()!
let out = NSImage(size: NSSize(width: w, height: h))
out.lockFocus()
NSColor.darkGray.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
var x = 0.0
for image in images { image.draw(in: NSRect(x: x, y: 0, width: image.size.width, height: image.size.height)); x += image.size.width + 8 }
out.unlockFocus()
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[0]))
