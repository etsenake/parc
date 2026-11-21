import AppKit

@MainActor
enum EaselStampArtwork {
    private static var symbols: [String: NSImage] = [:]
    private static let missingSymbol = "questionmark.square.dashed"

    static func draw(_ item: EaselItem, in rect: NSRect, ink: NSColor) {
        guard let face = EaselStampFace(item: item) else { return }
        draw(face, in: rect, ink: ink)
    }

    static func draw(_ face: EaselStampFace, in rect: NSRect, ink: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        switch face {
        case .design(let design): drawDesign(design, in: rect)
        case .emoji(let character): drawEmoji(character, in: rect)
        case .icon(let name): drawIcon(name, in: rect, color: ink)
        }
    }

    static func bezierPath(_ path: EaselStampPath, in rect: NSRect) -> NSBezierPath {
        let sx = rect.width / EaselStampArt.box, sy = rect.height / EaselStampArt.box
        func point(_ value: EaselPoint) -> NSPoint { NSPoint(x: rect.minX + value.x * sx, y: rect.minY + value.y * sy) }
        let result = NSBezierPath()
        for element in path.elements {
            switch element {
            case .move(let value): result.move(to: point(value))
            case .line(let value): result.line(to: point(value))
            case .curve(let a, let b, let value): result.curve(to: point(value), controlPoint1: point(a), controlPoint2: point(b))
            case .close: result.close()
            }
        }
        return result
    }

    private static func drawDesign(_ design: EaselStampDesign, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(rect.width, rect.height) / EaselStampArt.box
        for layer in EaselStampArt.layers(design) {
            let shape = bezierPath(layer.path, in: rect)
            shape.lineJoinStyle = .round
            shape.lineCapStyle = .round
            if let width = layer.outline { shape.lineWidth = width * scale }
            let color = EaselInk.fixed(EaselStampArt.hex(layer.tone, for: design))
            let grouped = layer.opacity < 1 && layer.filled && layer.outline != nil
            context.saveGState()
            if grouped {
                context.setAlpha(layer.opacity)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            let paint = grouped ? color : color.withAlphaComponent(layer.opacity)
            if layer.filled { paint.setFill(); shape.fill() }
            if layer.outline != nil { paint.setStroke(); shape.stroke() }
            if grouped { context.endTransparencyLayer() }
            context.restoreGState()
        }
    }

    private static func drawEmoji(_ character: String, in rect: NSRect) {
        let side = min(rect.width, rect.height) * EaselStamps.emojiScale
        let font = NSFont(name: "AppleColorEmoji", size: side) ?? .systemFont(ofSize: side)
        let text = NSAttributedString(string: character, attributes: [.font: font])
        let measured = text.size()
        text.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
    }

    static func symbol(_ name: String) -> NSImage? {
        if let cached = symbols[name] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return name == missingSymbol ? nil : symbol(missingSymbol)
        }
        symbols[name] = image
        return image
    }

    static func iconRect(for image: NSImage, in rect: NSRect) -> NSRect {
        let inset = CGFloat(EaselStamps.iconInset)
        let box = rect.insetBy(dx: rect.width * inset, dy: rect.height * inset)
        let size = image.size
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    private static func drawIcon(_ name: String, in rect: NSRect, color: NSColor) {
        guard let image = symbol(name), let context = NSGraphicsContext.current?.cgContext else { return }
        let target = iconRect(for: image, in: rect)
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        color.setFill()
        target.fill(using: .sourceIn)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func iconMask(_ name: String, size: NSSize, scale: CGFloat) -> EaselVectorImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, scale.isFinite, scale > 0 else { return nil }
        let factor = min(scale, 2048 / max(size.width, size.height))
        let width = max(1, Int((size.width * factor).rounded())), height = max(1, Int((size.height * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: factor, y: -factor)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawIcon(name, in: NSRect(origin: .zero, size: size), color: .white)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return EaselVectorImage(data: data, mimeType: "image/png")
    }

    static func accessibilityLabel(_ item: EaselItem) -> String {
        guard let face = EaselStampFace(item: item) else { return "Stamp" }
        return face.accessibilityLabel(emojiName: emojiName(face))
    }

    static func title(_ face: EaselStampFace) -> String { face.title(emojiName: emojiName(face)) }

    private static func emojiName(_ face: EaselStampFace) -> String? {
        guard case .emoji(let character) = face else { return nil }
        return NoteEmojiCatalog.shared.entry(for: character)?.displayName
    }
}
