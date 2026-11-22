import AppKit

@MainActor package final class LibraryArtwork {
    package static let directory = directory(in: .main)
    static func directory(in bundle: Bundle) -> URL? {
        bundle.resourceURL?.appendingPathComponent("Library", isDirectory: true)
    }
    package static let shared = LibraryArtwork(folder: directory)
    private let folder: URL?
    init(folder: URL?) { self.folder = folder }

    private var cache: [String: NSImage] = [:]

    package static func boxOfThings(_ name: String) -> NSImage? { shared.image(name, vector: "pdf") }
    package var emptyFavicon: NSImage? { image("EmptyFavicon", vector: "svg") }

    static func card(_ name: String, dark: Bool, side: CGFloat) -> NSImage? {
        let file = name + (dark ? "-dark" : "")
        guard let directory, let base = NSImage(contentsOf: directory.appendingPathComponent(file + ".png")) else { return nil }
        base.size = NSSize(width: side, height: side)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(file + "@2x.png")),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: side, height: side)
            base.addRepresentation(rep)
        }
        return base
    }

    private func image(_ name: String, vector: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let directory = folder,
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
        if let vectorImage = NSImage(contentsOf: directory.appendingPathComponent(name + "." + vector)) {
            for representation in vectorImage.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}
