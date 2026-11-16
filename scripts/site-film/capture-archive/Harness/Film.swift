import AppKit
import CoreImage
import SwiftUI

@MainActor enum PageArt {
    static func draw(_ image: NSImage, in card: NSRect, fill: NSColor = .white, fitWidth: CGFloat? = nil, scroll: CGFloat = 0) {
        fill.setFill(); card.fill()
        let width = fitWidth ?? card.width
        let scale = width / image.size.width
        image.draw(in: NSRect(x: card.midX - width / 2, y: card.minY - scroll, width: width, height: image.size.height * scale),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    static func desaturated(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }

    static func bitmap(size: NSSize, scale: CGFloat, _ body: (NSRect) -> Void) -> CGImage {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        body(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return cg.makeImage()!
    }

    static func png(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }
}

@MainActor final class ToastSprite: NSView {
    let image: CGImage
    let card: NSRect
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var cornerTarget = NSPoint.zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(content: ParcToastContent, theme: SpaceTheme, frame: NSRect) {
        let state = ParcToastState(content: content, theme: theme)
        state.showing = true
        let actions = ParcToastActions(tap: nil, accessory: nil, dismiss: {}, share: { _ in }, frames: { _ in }, retry: nil)
        let view = ParcToastCard(state: state, actions: actions)
            .frame(width: 560, height: 120)
            .padding(30)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        image = renderer.cgImage!
        card = ToastSprite.opaqueBounds(image, scale: 2)
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func opaqueBounds(_ image: CGImage, scale: CGFloat) -> NSRect {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height { for x in 0..<width where data[(y * width + x) * 4 + 3] >= 250 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return NSRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale, width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard progress > 0.001, let context = NSGraphicsContext.current?.cgContext else { return }
        let size = NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        let origin = NSPoint(x: cornerTarget.x - card.maxX, y: cornerTarget.y - card.minY)
        let anchor = NSPoint(x: origin.x + card.midX, y: origin.y + card.minY - 8 + 0.1 * (card.height + 8))
        let scale = CGFloat(max(0, progress))
        context.saveGState()
        context.setAlpha(CGFloat(min(1, max(0, progress))))
        context.translateBy(x: anchor.x, y: anchor.y); context.scaleBy(x: scale, y: scale); context.translateBy(x: -anchor.x, y: -anchor.y)
        context.translateBy(x: origin.x, y: origin.y + size.height); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }
}

struct Beat: Codable {
    let t: Double
    let name: String
    let detail: String
}

@MainActor final class FilmRecorder {
    let scene: BrowserScene
    let name: String
    let out: String
    var beats: [Beat] = []
    init(scene: BrowserScene, name: String, out: String) { self.scene = scene; self.name = name; self.out = out }

    func beat(_ t: Double, _ name: String, _ detail: String) { beats.append(Beat(t: t, name: name, detail: detail)) }

    func record(duration: Double, fps: Int = 60, keyTimes: [Double] = [], onlyStills: Bool = false, step: (Double, Int) -> Void) {
        let frames = Int((duration * Double(fps)).rounded())
        let writer = onlyStills ? nil : try! VideoWriter(path: "\(out)/\(name).mov", width: 2880, height: 1800, fps: Int32(fps))
        let stripFrames = Set((0..<12).map { Int((Double($0) + 0.5) / 12 * Double(frames)) })
        let keyFrames = Set(keyTimes.map { Int(($0 * Double(fps)).rounded()) })
        var strip: [(Int, CGImage)] = []
        let started = Date()
        for frame in 0..<frames {
            let t = Double(frame) / Double(fps)
            if onlyStills && !stripFrames.contains(frame) && !keyFrames.contains(frame) { continue }
            autoreleasepool {
                step(t, frame)
                let image = scene.renderFrame()
                writer?.append(image)
                if stripFrames.contains(frame) { strip.append((frame, image.copy()!)) }
                if keyFrames.contains(frame) {
                    Render.writePNG(NSBitmapImageRep(cgImage: image), String(format: "%@/%@-key-%.2fs.png", out, name, t))
                }
            }
            if frame % 60 == 0 { print(name, "frame", frame, "of", frames, String(format: "%.1fs", Date().timeIntervalSince(started))) }
            Render.requireNoWindows("during \(name) frame \(frame)")
        }
        if let writer {
            let result = writer.finish()
            print("wrote \(out)/\(name).mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        writeStrip(strip.map(\.1), times: strip.map { Double($0.0) / Double(fps) })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try! encoder.encode(["fps": AnyEncodable(fps), "duration": AnyEncodable(duration), "frames": AnyEncodable(frames),
                             "size": AnyEncodable([2880, 1800]), "beats": AnyEncodable(beats)])
            .write(to: URL(fileURLWithPath: "\(out)/\(name)-beats.json"))
    }

    func writeStrip(_ images: [CGImage], times: [Double]) {
        let cell = NSSize(width: 720, height: 450), columns = 4
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let sheet = PageArt.bitmap(size: NSSize(width: cell.width * CGFloat(columns), height: (cell.height + 24) * CGFloat(rows)), scale: 1) { bounds in
            NSColor(white: 0.55, alpha: 1).setFill(); bounds.fill()
            for (index, image) in images.enumerated() {
                let x = CGFloat(index % columns) * cell.width, y = CGFloat(index / columns) * (cell.height + 24)
                NSImage(cgImage: image, size: cell).draw(in: NSRect(x: x, y: y + 24, width: cell.width, height: cell.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSAttributedString(string: String(format: "%.2fs", times[index]),
                                   attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white])
                    .draw(at: NSPoint(x: x + 8, y: y + 3))
            }
        }
        Render.writePNG(NSBitmapImageRep(cgImage: sheet), "\(out)/\(name)-strip.png")
    }
}

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
