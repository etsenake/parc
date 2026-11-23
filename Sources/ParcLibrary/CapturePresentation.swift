import AppKit

package enum CapturePresentation {
    static let paletteWidth: CGFloat = 273
    static let paletteInset: CGFloat = 10
    package static let cornerRadius: CGFloat = 7
    package static let imageBorder: CGFloat = 4

    static let cardSpacing: CGFloat = 16
    static let cardWidthShare: CGFloat = 0.64
    static let cardHeightShare: CGFloat = 0.72
    static let liftCoverage: CGFloat = 0.5

    package struct Layout {
        package var image: NSRect
        package var palette: NSRect
        package var captured: NSRect
        package var lifted: Bool { captured != image }
    }

    package static func layout(bounds: NSRect, pixels: NSSize, source: NSRect?, paletteHeight: CGFloat,
                       editing: Bool, editingFooterHeight: CGFloat = 110, fullPalette: Bool = false) -> Layout {
        guard bounds.width > 0, bounds.height > 0 else { return Layout(image: .zero, palette: .zero, captured: .zero) }
        let margin = min(paletteInset, bounds.width / 4, bounds.height / 4)
        let safe = bounds.insetBy(dx: margin, dy: margin)
        let paletteSize = NSSize(width: min(paletteWidth, safe.width), height: min(paletteHeight, safe.height))
        var imageArea = bounds.insetBy(dx: min(8, bounds.width / 4), dy: min(8, bounds.height / 4))
        if editing {
            imageArea.size.height = max(1, imageArea.height - min(editingFooterHeight, imageArea.height - 1))
        }
        let compact = !editing && bounds.width < 2 * paletteWidth + 30
        var menu = NSRect(origin: safe.origin, size: paletteSize)
        if compact {
            menu.size.height = fullPalette ? menu.height : min(menu.height, safe.height * 0.62)
            menu.origin.y = safe.maxY - menu.height
            menu.origin.x = safe.midX - menu.width / 2
            imageArea.size.height = max(1, menu.minY - imageArea.minY - margin)
        }
        let preferred = source.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? imageArea
        let fitArea = editing || compact ? imageArea : NSRect(origin: preferred.origin,
            size: NSSize(width: min(preferred.width, imageArea.width), height: min(preferred.height, imageArea.height)))
        let image = fitted(pixels, in: fitArea, constrainedTo: imageArea)
        guard !editing && !compact else { return Layout(image: image, palette: menu, captured: image) }
        let border = image.insetBy(dx: -imageBorder, dy: -imageBorder)
        let right = border.maxX + paletteInset
        menu.origin.x = border.maxX + paletteWidth < bounds.maxX ? right : border.minX - paletteInset - menu.width
        menu.origin.y = bounds.maxY - (border.minY - imageBorder + paletteWidth) < paletteInset
            ? border.maxY - menu.height : border.minY
        menu.origin.x = min(max(menu.minX, safe.minX), safe.maxX - menu.width)
        menu.origin.y = min(max(menu.minY, safe.minY), safe.maxY - menu.height)
        let covered = preferred.intersection(bounds)
        let coverage = covered.isNull ? 0 : covered.width * covered.height / (bounds.width * bounds.height)
        guard menu.intersects(border) || coverage > liftCoverage else {
            return Layout(image: image, palette: menu, captured: image)
        }
        return card(bounds: bounds, safe: safe, pixels: pixels, captured: image, palette: paletteSize)
    }

    private static func card(bounds: NSRect, safe: NSRect, pixels: NSSize, captured: NSRect, palette: NSSize) -> Layout {
        let shortest = min(bounds.width, bounds.height)
        let margin = min(max(24, shortest * 0.08), shortest / 6)
        let room = NSSize(width: min(bounds.width - 2 * margin - cardSpacing - palette.width, bounds.width * cardWidthShare) - 2 * imageBorder,
                          height: min(bounds.height - 2 * margin, bounds.height * cardHeightShare) - 2 * imageBorder)
        guard pixels.width > 0, pixels.height > 0, room.width > 0, room.height > 0 else {
            return Layout(image: captured, palette: NSRect(origin: safe.origin, size: palette), captured: captured)
        }
        let scale = min(room.width / pixels.width, room.height / pixels.height, captured.width / pixels.width)
        let size = NSSize(width: pixels.width * scale, height: pixels.height * scale)
        let group = size.width + 2 * imageBorder + cardSpacing + palette.width
        let image = NSRect(x: bounds.midX - group / 2 + imageBorder, y: bounds.midY - size.height / 2,
                           width: size.width, height: size.height)
        let border = image.insetBy(dx: -imageBorder, dy: -imageBorder)
        var menu = NSRect(x: border.maxX + cardSpacing, y: border.minY, width: palette.width, height: palette.height)
        menu.origin.y = min(max(menu.minY, safe.minY), safe.maxY - menu.height)
        return Layout(image: image, palette: menu, captured: captured)
    }

    private static func fitted(_ pixels: NSSize, in proposed: NSRect, constrainedTo limit: NSRect) -> NSRect {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = min(proposed.width / pixels.width, proposed.height / pixels.height)
        let size = NSSize(width: pixels.width * scale, height: pixels.height * scale)
        return NSRect(x: min(max(proposed.midX - size.width / 2, limit.minX), limit.maxX - size.width),
                      y: min(max(proposed.midY - size.height / 2, limit.minY), limit.maxY - size.height),
                      width: size.width, height: size.height)
    }

    package static func pixelCrop(_ selection: NSRect, imageRect: NSRect, pixels: NSSize) -> NSRect? {
        guard imageRect.width > 0, imageRect.height > 0, pixels.width > 0, pixels.height > 0 else { return nil }
        let clipped = selection.intersection(imageRect)
        guard !clipped.isEmpty, !clipped.isNull else { return nil }
        return NSRect(x: (clipped.minX - imageRect.minX) * pixels.width / imageRect.width,
                      y: (clipped.minY - imageRect.minY) * pixels.height / imageRect.height,
                      width: clipped.width * pixels.width / imageRect.width,
                      height: clipped.height * pixels.height / imageRect.height).integral
            .intersection(NSRect(origin: .zero, size: pixels))
    }
}

@MainActor package enum CaptureAppearance {
    package static func dark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    package static func imageBackground(_ dark: Bool) -> NSColor { dark ? rgb(21 / 255, 28 / 255, 48 / 255) : .white }
    static let hint = NSColor(displayP3Red: 0.204, green: 0.021, blue: 0.580, alpha: 0.8)
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

@MainActor package enum CaptureArtwork {
    nonisolated static let directory = Bundle.main.resourceURL?.appendingPathComponent("Capture", isDirectory: true)
    package static func image(_ name: String, in directory: URL? = directory) -> NSImage? {
        guard let directory, let image = NSImage(contentsOf: directory.appendingPathComponent(name + ".pdf")) else { return nil }
        for suffix in [".png", "@2x.png"] {
            if let bytes = try? Data(contentsOf: directory.appendingPathComponent(name + suffix)),
               let representation = NSBitmapImageRep(data: bytes) {
                representation.size = image.size; image.addRepresentation(representation)
            }
        }
        image.isTemplate = false
        return image
    }
}
