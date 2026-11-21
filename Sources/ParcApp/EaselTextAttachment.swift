import AppKit
import ImageIO

@MainActor
final class EaselImageAttachment: NSTextAttachment {
    let source: EaselRichText.Image
    init(source: EaselRichText.Image) {
        self.source = source
        super.init(data: source.data, ofType: source.fileType)
        attachmentCell = EaselImageAttachmentCell(source: source)
    }
    required init?(coder: NSCoder) { return nil }
}

@MainActor
final class EaselImageAttachmentCell: NSTextAttachmentCell {
    weak var textContainer: NSTextContainer?
    var canvasWidth: CGFloat?
    private let originalSize: NSSize
    init(source: EaselRichText.Image) {
        originalSize = .init(width: source.width, height: source.height)
        super.init(imageCell: NSImage(data: source.data))
    }
    required init(coder: NSCoder) { fatalError("Attachment cells are restored from validated image bytes") }
    override func cellSize() -> NSSize {
        MainActor.assumeIsolated { ownedCellSize() }
    }
    private func ownedCellSize() -> NSSize {
        guard let width = textContainer?.size.width ?? canvasWidth, width.isFinite, width > 0 else { return originalSize }
        let available = max(1, width - 60)
        let scale = min(1, available / originalSize.width, available / originalSize.height)
        let size = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        if image?.size != size { image?.size = size }
        return .init(width: width, height: size.height + 60)
    }
}

@MainActor
enum EaselTextAttachments {
    static func image(data: Data) throws -> EaselRichText.Image {
        guard data.count <= 4_194_304, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1, let rawType = CGImageSourceGetType(source) else {
            throw EaselStoreError.invalidImage
        }
        let type = rawType as String
        guard ["public.png", "public.jpeg", "public.tiff"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0, w <= 20_000, h <= 20_000, w * h <= 16_777_216,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              let image = NSImage(data: data) else { throw EaselStoreError.invalidImage }
        let value = EaselRichText.Image(data: data, fileType: type, width: image.size.width, height: image.size.height)
        try value.validate(); return value
    }
    static func pastedImageData(from board: NSPasteboard) throws -> Data? {
        if let raw = board.string(forType: .fileURL) {
            guard let url = URL(string: raw), url.isFileURL,
                  board.pasteboardItems?.filter({ $0.availableType(from: [.fileURL]) != nil }).count == 1 else {
                throw EaselStoreError.invalidImage
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 4_194_304 else { throw EaselStoreError.invalidImage }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 4_194_305), data.count <= 4_194_304 else { throw EaselStoreError.tooLarge }
            _ = try attachmentImage(data)
            return data
        }
        return board.data(forType: .png) ?? board.data(forType: .tiff)
    }
    static func source(_ attachment: NSTextAttachment) throws -> EaselRichText.Image {
        if let own = attachment as? EaselImageAttachment { try own.source.validate(); return own.source }
        if let wrapper = attachment.fileWrapper {
            guard wrapper.isRegularFile, let data = wrapper.regularFileContents else { throw EaselTextClipboardError.unsupportedAttachment }
            return try attachmentImage(data)
        }
        if let data = attachment.contents { return try attachmentImage(data) }
        guard let image = attachment.image ?? (attachment.attachmentCell as? NSTextAttachmentCell)?.image,
              let data = image.tiffRepresentation else { throw EaselTextClipboardError.unsupportedAttachment }
        return try self.image(data: data)
    }
    private static func attachmentImage(_ data: Data) throws -> EaselRichText.Image {
        do { return try image(data: data) }
        catch EaselStoreError.invalidImage { throw EaselTextClipboardError.unsupportedAttachment }
    }
    static func bind(_ value: NSAttributedString, container: NSTextContainer? = nil, width: CGFloat? = nil) {
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { object, _, _ in
            guard let cell = (object as? EaselImageAttachment)?.attachmentCell as? EaselImageAttachmentCell else { return }
            cell.textContainer = container; cell.canvasWidth = width
        }
    }
    static func normalized(_ value: NSAttributedString) throws -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        var failure: Error?
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { object, range, stop in
            guard let object, !(object is EaselInlineAttachment) else { return }
            do {
                guard let attachment = object as? NSTextAttachment, range.length == 1,
                      (value.string as NSString).substring(with: range) == "\u{FFFC}" else {
                    throw EaselTextClipboardError.unsupportedFormatting
                }
                result.addAttribute(.attachment, value: EaselImageAttachment(source: try source(attachment)), range: range)
            } catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
        _ = try EaselRichTextCodec.snapshot(result)
        return result
    }
    static func character(_ image: EaselRichText.Image, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attrs = attributes
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        attrs[.paragraphStyle] = paragraph; attrs[.attachment] = EaselImageAttachment(source: image)
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }
    static func hasImages(_ value: NSAttributedString) -> Bool {
        var found = false
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { object, _, stop in
            if object != nil, !(object is EaselInlineAttachment) { found = true; stop.pointee = true }
        }
        return found
    }
    static func plainString(_ value: String) -> String { value.replacingOccurrences(of: "\u{FFFC}", with: "") }
}

@MainActor
enum EaselClipboardURL {
    static func read(from board: NSPasteboard) throws -> URL? {
        guard board.availableType(from: [EaselStyledText.pasteboardType,
            EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType]) == nil,
              board.availableType(from: [.fileURL]) == nil,
              let raw = board.string(forType: .URL) ?? board.string(forType: .string) else { return nil }
        guard raw.utf8.count <= 1_048_576 else { throw EaselStoreError.tooLarge }
        guard raw.utf8.count <= 16_384, !raw.contains(where: { $0.isWhitespace }),
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func isSelfLabelled(_ selection: NSAttributedString) -> Bool {
        guard selection.length > 0, let label = URL(string: selection.string) else { return false }
        let value = selection.attribute(.link, at: 0, effectiveRange: nil)
        let link = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        return link == label
    }
}
