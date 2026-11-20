import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum NoteCustomEmojiImages {
    nonisolated static let maximumPixels = 280
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ name: String, in library: NoteEmojiLibrary?) -> NSImage? {
        guard let library, let entry = library.emoji(named: name) else { return nil }
        return image(for: entry, in: library)
    }

    static func image(for entry: NoteCustomEmoji, in library: NoteEmojiLibrary) -> NSImage? {
        let url = library.imageURL(for: entry)
        let key = "\(library.revision)|\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let image = NSImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let image = NSImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func image(forReference value: String, in library: NoteEmojiLibrary?) -> NSImage? {
        NoteCustomEmojiName.name(inReference: value).flatMap { image($0, in: library) }
    }

    nonisolated static func preparedPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0, image.height > 0 else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    nonisolated static func preparedPNG(contentsOf url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= NotePageImageLoader.maximumBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return preparedPNG(from: data)
    }

    nonisolated static func suggestedName(for url: URL) -> String {
        NoteCustomEmojiName.normalized(url.deletingPathExtension().lastPathComponent) ?? "emoji"
    }

    static func pasteboardImage(_ pasteboard: NSPasteboard) -> (data: Data, name: String)? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                             .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first,
           let data = preparedPNG(contentsOf: url) {
            return (data, suggestedName(for: url))
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] {
            if let raw = pasteboard.data(forType: type), let data = preparedPNG(from: raw) { return (data, "") }
        }
        return nil
    }

    nonisolated static func draw(_ image: NSImage, fittingIn rect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        let target = NSRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }
}

extension NoteIcon {
    @MainActor
    static func note(_ icon: String?, at note: URL?) -> NoteIcon {
        guard let icon, !icon.isEmpty else { return .symbol("doc.text") }
        if NoteTabIcon.emoji(icon) != nil { return .emoji(icon) }
        guard let note, NoteCustomEmojiName.isReference(icon) || NotePageImageLoader.isImageSource(icon),
              let url = NoteFileEnvironment(documentURL: note, isPlainText: false).resolve(icon), url.isFileURL,
              NoteCustomEmojiImages.image(at: url) != nil else { return .symbol("doc.text") }
        return .image(url)
    }
}
