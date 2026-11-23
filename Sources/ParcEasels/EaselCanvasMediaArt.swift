import AppKit
import PDFKit
import ParcCore
import ParcNotes

@MainActor
enum EaselMediaArt {
    private static let pages = NSCache<NSString, NSImage>()
    private static let sizes = NSCache<NSString, NSString>()

    static func byteSize(_ data: Data) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    static func detail(for item: EaselItem, data: () -> Data?) -> String? {
        guard item.kind == .file || item.kind == .pdf, let id = item.assetID else { return nil }
        let key = id as NSString
        if let cached = sizes.object(forKey: key) { return cached as String }
        guard let bytes = data() else { return nil }
        let text = byteSize(bytes)
        sizes.setObject(text as NSString, forKey: key)
        return text
    }

    static func firstPage(_ id: String, size: NSSize, scale: CGFloat, data: () -> Data?) -> NSImage? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        let density = min(max(scale, 1), 4)
        let pixel = NSSize(width: min(size.width * density, 4096), height: min(size.height * density, 4096))
        let key = (id + "@" + String(Int(pixel.width)) + "x" + String(Int(pixel.height))) as NSString
        if let cached = pages.object(forKey: key) { return cached }
        guard let bytes = data(), let page = PDFDocument(data: bytes)?.page(at: 0) else { return nil }
        let image = page.thumbnail(of: pixel, for: .mediaBox)
        pages.setObject(image, forKey: key)
        return image
    }

    static func png(_ image: NSImage) -> EaselVectorImage? {
        guard let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return EaselVectorImage(data: data, mimeType: "image/png")
    }
}

extension EaselCanvasView {
    func drawMediaObject(_ item: EaselItem, in r: NSRect) {
        switch item.kind {
        case .pdf:
            if !drawPDFFirstPage(item, in: r) { drawMediaCard(item, in: r) }
        case .audio, .file:
            drawMediaCard(item, in: r)
        default:
            break
        }
    }

    func drawsLinkedVideoCard(_ item: EaselItem) -> Bool {
        item.kind == .video && item.poster == nil && item.assetID == nil && item.url != nil
    }

    func drawMediaCredit(_ item: EaselItem, in r: NSRect) {
        guard let sentence = EaselVectorExport.mediaCredit(item)?.sentence, !EaselRotation.mirrorsHorizontally(item),
              !EaselRotation.mirrorsVertically(item) else { return }
        let font = NoteTheme.nunitoRegular(CGFloat(EaselVectorExport.creditFontSize))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let box = NSRect(x: r.minX, y: r.maxY + CGFloat(EaselVectorExport.creditGap), width: r.width, height: CGFloat(EaselVectorExport.creditHeight))
        (sentence as NSString).draw(in: box, withAttributes: [.font: font, .foregroundColor: EaselAppearance.secondaryText, .paragraphStyle: style])
    }

    private func mediaData(_ id: String) -> Data? { try? session.assetData(id) }

    private func drawPDFFirstPage(_ item: EaselItem, in r: NSRect) -> Bool {
        guard let id = item.assetID,
              let page = EaselMediaArt.firstPage(id, size: r.size, scale: window?.backingScaleFactor ?? 2, data: { mediaData(id) }) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).addClip()
        EaselPictureRenderer.draw(page, asset: nil, in: r)
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    func drawMediaCard(_ item: EaselItem, in r: NSRect) {
        let frame = EaselRect(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
        let layout = EaselVectorExport.mediaCardLayout(frame)
        let card = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        EaselAppearance.cardFill.setFill()
        card.fill()
        EaselAppearance.cardStroke.setStroke()
        card.stroke()
        let tile = NSRect(x: layout.tile.x, y: layout.tile.y, width: layout.tile.width, height: layout.tile.height)
        EaselAppearance.cardStroke.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 8, yRadius: 8).fill()
        EaselAppearance.text.setFill()
        for shape in EaselVectorExport.mediaGlyph(item.kind, in: layout.tile) {
            guard let first = shape.first else { continue }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: first.x, y: first.y))
            for point in shape.dropFirst() { path.line(to: NSPoint(x: point.x, y: point.y)) }
            path.close()
            path.fill()
        }
        let detail = EaselMediaArt.detail(for: item) { item.assetID.flatMap { mediaData($0) } }
        let width = CGFloat(layout.textWidth)
        drawMediaLine(EaselVectorExport.mediaTitle(item), font: NoteTheme.nunitoBold(15), color: EaselAppearance.text,
                      x: CGFloat(layout.textX), baseline: CGFloat(layout.titleBaseline), width: width)
        if let baseline = layout.subtitleBaseline {
            drawMediaLine(EaselVectorExport.mediaSubtitle(item, detail: detail), font: NoteTheme.nunitoRegular(12),
                          color: EaselAppearance.secondaryText, x: CGFloat(layout.textX), baseline: CGFloat(baseline), width: width)
        }
    }

    private func drawMediaLine(_ text: String, font: NSFont, color: NSColor, x: CGFloat, baseline: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let box = NSRect(x: x, y: baseline - font.ascender, width: width, height: ceil(font.ascender - font.descender + font.leading))
        (text as NSString).draw(in: box, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
}
