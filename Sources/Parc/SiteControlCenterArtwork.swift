import AppKit
import Combine
import ParcCore
import SwiftUI

@MainActor enum SiteControlCenterArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SiteControlCenter", isDirectory: true)
    private static let bundled = Library(directory: directory)

    static var controlCenter: NSImage? { bundled.controlCenter }

    static func image(_ name: String) -> NSImage? { bundled.image(name) }

    @MainActor final class Library {
        let directory: URL?
        private var cache: [String: NSImage] = [:]

        init(directory: URL?) { self.directory = directory }

        var controlCenter: NSImage? { image("icon-control-center") }

        func image(_ name: String) -> NSImage? {
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
            if let vector = NSImage(contentsOf: directory.appendingPathComponent(name + ".pdf")) {
                for representation in vector.representations { image.addRepresentation(representation) }
            }
            image.isTemplate = true
            cache[name] = image
            return image
        }
    }
}
