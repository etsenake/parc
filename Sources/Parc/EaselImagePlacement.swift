import AppKit
import ImageIO
import ParcCore

@MainActor
struct EaselImageInput {
    let pngData: Data
    let sourceURL: URL?
    let pageTitle: String
    let valid: () -> Bool
    var capturedPage = false
    var captureLayout: EaselCaptureLayout?
    var capturedAt: Date?
    var isValid: Bool { valid() }
}

@MainActor
enum EaselImagePlacement {
    @MainActor
    struct Result {
        let session: EaselSession
        var id: UUID { session.document.id }
        var title: String { session.document.title }
    }
    static func pixelSize(_ data: Data) throws -> NSSize {
        guard data.count <= EaselStore.maximumAssetBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384,
              Int64(width) * Int64(height) <= 80_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw EaselStoreError.invalidImage }
        return NSSize(width: width, height: height)
    }

    static func place(_ image: EaselImageInput, in store: EaselStore, destinationID: UUID?,
                      newTitle: String) throws -> Result {
        guard image.isValid else { throw CocoaError(.userCancelled) }
        let size = try pixelSize(image.pngData)
        let session: EaselSession
        var createdID: UUID?
        do {
            if let destinationID {
                session = try store.load(destinationID)
            } else {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                session = try store.create(title: title.isEmpty ? "Untitled Easel" : title)
                createdID = session.document.id
            }
            guard image.isValid else { throw CocoaError(.userCancelled) }
            let assetID = try session.importPNG(image.pngData)
            let width = min(480, Double(size.width))
            let pageOne = EaselPages.view(session.document, page: nil).items
            let bottom = pageOne.map { $0.frame.y + $0.frame.height }.max() ?? 0
            let card = image.capturedPage && image.sourceURL != nil
            let item = EaselItem(kind: card ? .webCard : .image,
                frame: EaselRect(x: 40, y: max(40, bottom + 32), width: width,
                                 height: max(1, width * Double(size.height) / Double(size.width))),
                zIndex: (pageOne.map(\.zIndex).max() ?? 0) + 1,
                text: card ? image.pageTitle : "", url: image.sourceURL?.absoluteString, assetID: assetID, capturedAt: image.capturedAt ?? Date(),
                captureLayout: card ? image.captureLayout : nil, page: EaselPages.resolvedPage(nil, in: session.document))
            try session.perform(card ? "Add captured webpage" : "Add webpage image") { $0.items.append(item) }
            return Result(session: session)
        } catch {
            if let createdID { try? store.delete(createdID) }
            throw error
        }
    }
}
