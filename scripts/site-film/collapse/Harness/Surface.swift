import AppKit
import CoreImage

func drawFlipped(_ image: CGImage, in rect: NSRect, _ context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    context.restoreGState()
}

@MainActor final class ReflowPage {
    let scale: CGFloat
    let width: Int, height: Int
    let headerHeight: Int
    let seam: Int
    let headerLeft: CGImage, headerRight: CGImage, headerSeam: CGImage, body: CGImage

    init?(path: String, restingWidth: CGFloat) {
        guard let rep = NSImage(contentsOfFile: path).flatMap({ $0.tiffRepresentation }).flatMap(NSBitmapImageRep.init(data:)),
              let image = rep.cgImage else { return nil }
        width = image.width; height = image.height
        scale = restingWidth / CGFloat(width)
        seam = width / 2
        var rule = 0
        for y in 0..<min(200, height) {
            guard let color = rep.colorAt(x: seam, y: y)?.usingColorSpace(.sRGB) else { continue }
            if color.redComponent < 0.97 || color.greenComponent < 0.97 || color.blueComponent < 0.97 { rule = y; break }
        }
        headerHeight = rule + 1
        headerLeft = image.cropping(to: CGRect(x: 0, y: 0, width: seam, height: headerHeight))!
        headerRight = image.cropping(to: CGRect(x: seam, y: 0, width: width - seam, height: headerHeight))!
        headerSeam = image.cropping(to: CGRect(x: seam, y: 0, width: 1, height: headerHeight))!
        body = image.cropping(to: CGRect(x: 0, y: headerHeight, width: width, height: height - headerHeight))!
        print("page", width, "x", height, "header rule row", rule, "scale", scale)
    }

    func draw(in card: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.white.setFill(); card.fill()
        let header = CGFloat(headerHeight) * scale
        let half = CGFloat(seam) * scale, rest = CGFloat(width - seam) * scale
        drawFlipped(headerSeam, in: NSRect(x: card.minX + half - 1, y: card.minY, width: card.width - half - rest + 2, height: header), context)
        drawFlipped(headerLeft, in: NSRect(x: card.minX, y: card.minY, width: half, height: header), context)
        drawFlipped(headerRight, in: NSRect(x: card.maxX - rest, y: card.minY, width: rest, height: header), context)
        let full = CGFloat(width) * scale
        drawFlipped(body, in: NSRect(x: card.minX + (card.width - full) / 2, y: card.minY + header,
                                     width: full, height: CGFloat(height - headerHeight) * scale), context)
    }
}

@MainActor final class FloatingSurfaceView: NSView {
    var theme: CGImage?
    var backdrop: CGImage?
    var content: CGImage?
    var dock: CGFloat = 0
    var surfaceRect = NSRect.zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let radius = FloatingSidebarSurface.cornerRadius
        context.saveGState()
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius, transform: nil))
        context.clip()
        if let shadow = FloatingSidebarSurface.shadowImage {
            let outset = FloatingSidebarSurface.shadowOutset
            shadow.draw(in: surfaceRect.insetBy(dx: -outset, dy: -outset), from: .zero, operation: .sourceOver,
                        fraction: FloatingSidebarSurface.shadowAlpha * (1 - dock), respectFlipped: true, hints: nil)
        }
        context.saveGState()
        context.addPath(CGPath(roundedRect: surfaceRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        if let backdrop, dock < 1 {
            context.saveGState(); context.setAlpha(1 - dock)
            drawFlipped(backdrop, in: bounds, context)
            context.restoreGState()
        }
        if dock > 0 {
            NSColor(white: CGFloat(ThemeRenderMath.lightMaterial.x), alpha: dock).setFill()
            surfaceRect.fill(using: .sourceOver)
        }
        if let theme { drawFlipped(theme, in: bounds, context) }
        if let content { drawFlipped(content, in: surfaceRect, context) }
        context.restoreGState()
        let border = CGPath(roundedRect: surfaceRect.insetBy(dx: FloatingSidebarSurface.borderWidth / 2, dy: FloatingSidebarSurface.borderWidth / 2),
                            cornerWidth: radius - FloatingSidebarSurface.borderWidth / 2, cornerHeight: radius - FloatingSidebarSurface.borderWidth / 2,
                            transform: nil)
        context.addPath(border)
        context.setStrokeColor(FloatingSidebarSurface.borderColor)
        context.setLineWidth(FloatingSidebarSurface.borderWidth)
        context.strokePath()
        context.restoreGState()
    }
}

enum PopoverMaterial {
    static let blurRadius: CGFloat = 30
    static let tint = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.97, alpha: 0.72)

    static func make(from window: CGImage) -> CGImage? {
        let input = CIImage(cgImage: window)
        let extent = input.extent
        guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input.clampedToExtent(),
                                                                         kCIInputRadiusKey: blurRadius * 2]),
              let blurred = blur.outputImage?.cropped(to: extent) else { return nil }
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        guard let soft = context.createCGImage(blurred, from: extent) else { return nil }
        guard let canvas = CGContext(data: nil, width: window.width, height: window.height, bitsPerComponent: 8, bytesPerRow: window.width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: window.width, height: window.height)
        canvas.setFillColor(NSColor.white.cgColor); canvas.fill(full)
        canvas.draw(soft, in: full)
        canvas.setFillColor(tint.cgColor); canvas.fill(full)
        return canvas.makeImage()
    }
}
