import AppKit

///
/// asset catalogs into `Resources/Library` (provenance in its README). Each
/// image is put together the way the catalog's NSImage is: the compiled 1× and
/// 2× bitmap renditions plus the vector rendition (PDF or SVG), at the 1×
/// rendition's point size, as a template.
@MainActor enum LibraryArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Library", isDirectory: true)
    private static var cache: [String: NSImage] = [:]

    ///
    static func boxOfThings(_ name: String) -> NSImage? { image(name, vector: "pdf") }
    ///
    static var emptyFavicon: NSImage? { image("EmptyFavicon", vector: "svg") }

    static func image(_ name: String, vector: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        base.size = size
        let image = NSImage(size: size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = NSSize(width: CGFloat(double.pixelsWide) / 2, height: CGFloat(double.pixelsHigh) / 2)
            image.addRepresentation(double)
        }
        // The vector rendition, when this system decodes it (SVG needs a
        // newer AppKit than PDF); the bitmaps alone cover the drawn sizes.
        if let vectorImage = NSImage(contentsOf: directory.appendingPathComponent(name + "." + vector)) {
            for representation in vectorImage.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}
