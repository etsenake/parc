import AppKit
import ParcCore

@MainActor package enum SidebarPlusMenuArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SidebarPlusMenu", isDirectory: true)
    private static var cache: [String: NSImage] = [:]

    package static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let image = image(name, in: directory) else { return nil }
        cache[name] = image
        return image
    }

    static func image(_ name: String, in directory: URL?) -> NSImage? {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        base.size = size
        let image = NSImage(size: size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = size
            image.addRepresentation(double)
        }
        if let vector = NSImage(contentsOf: directory.appendingPathComponent(name + ".pdf")) {
            for representation in vector.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        return image
    }
}
