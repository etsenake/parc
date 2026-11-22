import AppKit
import ParcCore
import ParcNotes

@MainActor
enum EaselStampArtwork {
    struct Layer {
        let path: CGPath
        let fill: CGColor?
        let stroke: CGColor?
        let lineWidth: CGFloat
        let opacity: CGFloat

        var grouped: Bool { opacity < 1 && fill != nil && stroke != nil }
    }

    static let overhang = (EaselStampArt.rimWidth / 2 + 4.5) / EaselStampArt.box
    private static let missingSymbol = "questionmark.square.dashed"
    private static let emojiReference: CGFloat = 100
    private static let emojiCacheLimit = 512
    private static var designs: [EaselStampDesign: [Layer]] = [:]
    private static var symbols: [String: NSImage] = [:]
    private static var unavailableSymbols: Set<String> = []
    private static var emojiSizes: [String: NSSize] = [:]

    static func draw(_ item: EaselItem, in rect: NSRect, ink: NSColor, library: NoteEmojiLibrary? = nil) {
        guard let face = EaselStampFace(item: item) else { return }
        draw(face, in: rect, ink: ink, library: library)
    }

    static func draw(_ face: EaselStampFace, in rect: NSRect, ink: NSColor, library: NoteEmojiLibrary? = nil) {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return }
        switch face {
        case .design(let design): drawDesign(design, in: rect)
        case .emoji(let character):
            if let name = EaselStampFace.customName(in: character) { drawCustomEmoji(name, character, in: rect, library: library) } else { drawEmoji(character, in: rect) }
        case .icon(let name): drawIcon(name, in: rect, color: ink)
        }
    }

    static func visualBounds(_ rect: NSRect) -> NSRect {
        rect.insetBy(dx: -rect.width * CGFloat(overhang), dy: -rect.height * CGFloat(overhang))
    }

    static func cgPath(_ path: EaselStampPath) -> CGPath {
        let result = CGMutablePath()
        func point(_ value: EaselPoint) -> CGPoint { CGPoint(x: value.x, y: value.y) }
        for element in path.elements {
            switch element {
            case .move(let value): result.move(to: point(value))
            case .line(let value): result.addLine(to: point(value))
            case .curve(let a, let b, let value): result.addCurve(to: point(value), control1: point(a), control2: point(b))
            case .close: result.closeSubpath()
            }
        }
        return result
    }

    static func layers(_ design: EaselStampDesign) -> [Layer] {
        if let cached = designs[design] { return cached }
        let built = EaselStampArt.layers(design).map { layer -> Layer in
            let color = EaselInk.fixed(EaselStampArt.hex(layer.tone, for: design)).cgColor
            return Layer(path: cgPath(layer.path), fill: layer.filled ? color : nil, stroke: layer.outline == nil ? nil : color,
                         lineWidth: CGFloat(layer.outline ?? 0), opacity: CGFloat(layer.opacity))
        }
        designs[design] = built
        return built
    }

    private static func drawDesign(_ design: EaselStampDesign, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let box = CGFloat(EaselStampArt.box), margin = box * CGFloat(overhang)
        let area = CGRect(x: -margin, y: -margin, width: box + margin * 2, height: box + margin * 2)
        context.saveGState()
        context.clip(to: visualBounds(rect))
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / box, y: rect.height / box)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for layer in layers(design) {
            if layer.grouped {
                context.saveGState()
                context.setAlpha(layer.opacity)
                context.beginTransparencyLayer(in: area, auxiliaryInfo: nil)
                paint(layer, alpha: 1, in: context)
                context.endTransparencyLayer()
                context.restoreGState()
            } else {
                paint(layer, alpha: layer.opacity, in: context)
            }
        }
        context.restoreGState()
    }

    private static func paint(_ layer: Layer, alpha: CGFloat, in context: CGContext) {
        context.addPath(layer.path)
        if let fill = layer.fill { context.setFillColor(fill.copy(alpha: fill.alpha * alpha) ?? fill) }
        if let stroke = layer.stroke {
            context.setStrokeColor(stroke.copy(alpha: stroke.alpha * alpha) ?? stroke)
            context.setLineWidth(layer.lineWidth)
        }
        switch (layer.fill != nil, layer.stroke != nil) {
        case (true, true): context.drawPath(using: .fillStroke)
        case (true, false): context.fillPath()
        case (false, true): context.strokePath()
        case (false, false): context.beginPath()
        }
    }

    private static func emojiFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "AppleColorEmoji", size: size) ?? .systemFont(ofSize: size)
    }

    static func emojiSize(_ character: String, side: CGFloat) -> NSSize {
        let reference: NSSize
        if let cached = emojiSizes[character] {
            reference = cached
        } else {
            reference = NSAttributedString(string: character, attributes: [.font: emojiFont(emojiReference)]).size()
            if emojiSizes.count >= emojiCacheLimit { emojiSizes.removeAll() }
            emojiSizes[character] = reference
        }
        let factor = side / emojiReference
        return NSSize(width: reference.width * factor, height: reference.height * factor)
    }

    private static func drawEmoji(_ character: String, in rect: NSRect) {
        let side = min(rect.width, rect.height) * CGFloat(EaselStamps.emojiScale)
        guard side >= 1 else { return }
        let size = emojiSize(character, side: side)
        NSAttributedString(string: character, attributes: [.font: emojiFont(side)])
            .draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    static var customEmojiLibrary: NoteEmojiLibrary? {
        let libraries = NoteFolderPreferences.allFolders.map { NoteEmojiLibrary.library(root: $0) }
        return libraries.first { !$0.isEmpty } ?? libraries.first
    }

    static func customEmojiImage(_ name: String, library: NoteEmojiLibrary? = nil) -> NSImage? {
        NoteCustomEmojiImages.image(name, in: library ?? customEmojiLibrary)
    }

    private static func drawCustomEmoji(_ name: String, _ reference: String, in rect: NSRect, library: NoteEmojiLibrary?) {
        let side = min(rect.width, rect.height) * CGFloat(EaselStamps.emojiScale)
        guard side >= 1 else { return }
        let target = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        if let image = customEmojiImage(name, library: library), image.size.width > 0, image.size.height > 0 {
            let fit = min(side / image.size.width, side / image.size.height)
            let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
            image.draw(in: NSRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        let font = NSFont.systemFont(ofSize: max(1, min(side, side * 2.2 / CGFloat(max(reference.count, 1)))), weight: .semibold)
        let text = NSAttributedString(string: reference, attributes: [.font: font, .foregroundColor: NoteTheme.menuSecondaryInk])
        let size = text.size()
        text.draw(at: NSPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2))
    }

    static func symbol(_ name: String) -> NSImage? {
        if let cached = symbols[name] { return cached }
        guard !unavailableSymbols.contains(name) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
        let found = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        guard let image = found ?? (name == missingSymbol ? nil : symbol(missingSymbol)) else {
            unavailableSymbols.insert(name)
            return nil
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
        guard target.width > 0, target.height > 0 else { return }
        context.saveGState()
        context.beginTransparencyLayer(in: target, auxiliaryInfo: nil)
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
        return accessibilityLabel(face)
    }

    static func accessibilityLabel(_ face: EaselStampFace) -> String { face.accessibilityLabel(emojiName: emojiName(face)) }

    static func title(_ face: EaselStampFace) -> String { face.title(emojiName: emojiName(face)) }

    private static func emojiName(_ face: EaselStampFace) -> String? {
        guard case .emoji(let character) = face else { return nil }
        if let name = EaselStampFace.customName(in: character) { return name }
        return NoteEmojiCatalog.shared.entry(for: character)?.displayName
    }
}
