import AppKit
import UniformTypeIdentifiers

@MainActor
enum EaselDocumentExport {
    static func vectorText(_ item: EaselItem) -> EaselVectorText {
        let box = EaselTextPlacement.box(for: item)
        let source = item.kind == .sticky ? EaselStickyText.presented(item, adaptive: false)
            : EaselTextPresentation.displayed(EaselRichTextCodec.attributed(item), for: item)
        let layout = EaselTextLayout.Layout(source, width: box.width, height: box.height, scale: EaselTextLayout.scale(for: item))
        let manager = layout.manager, storage = layout.storage, container = layout.container
        let shown = manager.characterRange(forGlyphRange: manager.glyphRange(for: container), actualGlyphRange: nil)
        let placed = EaselTextPlacement.origin(for: item, textHeight: Double(layout.height),
                                               overflowing: EaselTextPlacement.clipsOverflow(item) && NSMaxRange(shown) < storage.length)
        let inset = NSSize(width: layout.inset.width + placed.x - item.frame.x, height: layout.inset.height + placed.y - item.frame.y)
        let hugging = item.resolvedTextStyle.resolvedFill == .contentHugging
        var result = EaselVectorText()
        if hugging {
            let rects = EaselTextLayout.lineRects(manager: manager, container: container)
            var shift = CGAffineTransform(translationX: inset.width, y: inset.height)
            let path = EaselTextLayout.fillPath(rects: rects, radius: EaselTextLayout.radius(item.resolvedTextStyle))
            if let moved = path.copy(using: &shift) { result.fillPath = svgPath(moved) }
        }
        let text = storage.string as NSString
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: characters) { attributes, range, _ in
                var value = text.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
                while let last = value.last, last.isNewline { value.removeLast() }
                guard !value.isEmpty else { return }
                let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let location = manager.location(forGlyphAt: glyphRange.location)
                let font = attributes[.font] as? NSFont ?? EaselTextAppearance.font(item.resolvedTextStyle)
                let traits = font.fontDescriptor.symbolicTraits
                var run = EaselVectorTextRun(x: Double(inset.width + rect.minX + location.x), y: Double(inset.height + rect.minY + location.y),
                                             text: value, fontFamily: cssFamily(font), fontSize: Double(font.pointSize),
                                             weight: cssWeight(font), italic: traits.contains(.italic))
                run.color = hugging ? "#FFFFFF" : (attributes[.foregroundColor] as? NSColor).flatMap(hex)
                run.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                run.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                if let link = attributes[.link] as? URL { run.link = link.absoluteString } else { run.link = attributes[.link] as? String }
                result.runs.append(run)
            }
        }
        return result
    }

    static func svgPath(_ path: CGPath) -> String {
        var data = ""
        let n = EaselVectorExport.number
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: data += "M" + n(points[0].x) + " " + n(points[0].y)
            case .addLineToPoint: data += "L" + n(points[0].x) + " " + n(points[0].y)
            case .addQuadCurveToPoint: data += "Q" + [points[0], points[1]].map { n($0.x) + " " + n($0.y) }.joined(separator: " ")
            case .addCurveToPoint: data += "C" + [points[0], points[1], points[2]].map { n($0.x) + " " + n($0.y) }.joined(separator: " ")
            case .closeSubpath: data += "Z"
            @unknown default: break
            }
        }
        return data
    }

    static func cssFamily(_ font: NSFont) -> String {
        let family = font.familyName ?? ""
        let sans = "-apple-system,BlinkMacSystemFont,\"SF Pro Text\",\"Helvetica Neue\",Arial,sans-serif"
        if family.isEmpty || family.hasPrefix(".") { return sans }
        let quoted = "\"" + family.replacingOccurrences(of: "\"", with: "") + "\","
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return quoted + "ui-monospace,Menlo,monospace" }
        if family.localizedCaseInsensitiveContains("Garamond") { return quoted + "\"Iowan Old Style\",Georgia,serif" }
        return quoted + sans
    }

    static func cssWeight(_ font: NSFont) -> Int {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        guard let weight = traits?[.weight] as? CGFloat else {
            return font.fontDescriptor.symbolicTraits.contains(.bold) ? 700 : 400
        }
        let steps: [(CGFloat, Int)] = [(-0.7, 100), (-0.5, 200), (-0.2, 300), (0.1, 400), (0.27, 500), (0.35, 600), (0.48, 700), (0.59, 800)]
        return steps.first { weight < $0.0 }?.1 ?? 900
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    static func css(_ color: NSColor, in appearance: NSAppearance) -> String {
        var value = "#000000"
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { String(Int(($0 * 255).rounded())) }
            value = rgb.alphaComponent >= 0.999 ? hex(rgb) ?? value
                : "rgba(" + channels.joined(separator: ",") + "," + EaselVectorExport.number(Double(rgb.alphaComponent)) + ")"
        }
        return value
    }

    static var palette: EaselVectorPalette {
        func swatch(_ name: NSAppearance.Name) -> EaselVectorPalette.Swatch {
            let appearance = NSAppearance(named: name) ?? NSAppearance.currentDrawing()
            return .init(ink: css(NoteTheme.ink, in: appearance), card: css(EaselAppearance.cardFill, in: appearance),
                         cardLine: css(EaselAppearance.cardStroke, in: appearance), muted: css(EaselAppearance.secondaryText, in: appearance))
        }
        return EaselVectorPalette(light: swatch(.aqua), dark: swatch(.darkAqua), code: EaselCodeBlockStyle.palette())
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func webImage(_ data: Data) -> EaselVectorImage? {
        if let type = EaselVectorExport.imageMimeType(data) { return EaselVectorImage(data: data, mimeType: type) }
        guard let converted = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
        return EaselVectorImage(data: converted, mimeType: "image/png")
    }

    static func mediaArt(_ item: EaselItem, session: EaselSession, scale: CGFloat, into art: inout EaselVectorArt) {
        guard let id = item.assetID else { return }
        art.mediaDetails[item.id] = EaselMediaArt.detail(for: item) { try? session.assetData(id) }
        let size = NSSize(width: item.frame.width, height: item.frame.height)
        if let page = EaselMediaArt.firstPage(id, size: size, scale: max(2, scale), data: { try? session.assetData(id) }) {
            art.images[item.id] = EaselMediaArt.png(page)
        }
    }

    static func art(session: EaselSession, canvas: EaselCanvasView, pages: [UUID: EaselPageSnapshot]) -> EaselVectorArt {
        var art = EaselVectorArt()
        let scale = EaselImageExport.pixelDensity()
        let lookup = Dictionary(session.document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let pageItems = EaselPages.pageDocuments(session.document).map(\.items)
        let hidden = Set(pageItems.flatMap { EaselBoardObjects.hiddenIDs(in: $0) })
        var neighbours: [UUID: [EaselItem]] = [:]
        for items in pageItems { for item in items where item.kind == .section { neighbours[item.id] = items } }
        for item in session.document.items where !hidden.contains(item.id) {
            switch item.kind {
            case .text, .sticky:
                art.texts[item.id] = vectorText(item)
            case .section:
                art.sectionTitles[item.id] = EaselSectionArt.vectorTitle(item, in: neighbours[item.id] ?? session.document.items)
            case .code:
                art.texts[item.id] = EaselCodeLayout.vectorText(item)
            case .image:
                if let id = item.assetID, let data = try? session.assetData(id) { art.images[item.id] = webImage(data) }
            case .video:
                if let id = item.poster, let data = try? session.assetData(id) { art.images[item.id] = webImage(data) }
            case .webCard, .browser:
                if let page = pages[item.id] {
                    art.images[item.id] = canvas.exportObjectImage(item, page: page, backingScale: scale).flatMap(png)
                        .map { EaselVectorImage(data: $0, mimeType: "image/png") }
                } else if let id = item.assetID, let data = try? session.assetData(id) {
                    art.images[item.id] = webImage(data)
                }
            case .table:
                art.texts[item.id] = tableVectorText(item)
            case .stamp:
                if case .icon(let name)? = EaselStampFace(item: item) {
                    art.images[item.id] = EaselStampArtwork.iconMask(name, size: NSSize(width: item.frame.width, height: item.frame.height), scale: max(4, scale))
                }
            case .arrow:
                connectorArt(item, lookup: lookup, into: &art)
            case .rectangle, .circle:
                if !item.text.isEmpty { art.texts[item.id] = vectorText(item) }
            case .audio, .file:
                art.mediaDetails[item.id] = EaselMediaArt.detail(for: item) { item.assetID.flatMap { try? session.assetData($0) } }
            case .pdf:
                mediaArt(item, session: session, scale: scale, into: &art)
            case .freehand, .link, .equation:
                break
            }
        }
        return art
    }
}
