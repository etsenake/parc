import AppKit
import ImageIO
import PDFKit
import ParcCore

@MainActor
package struct EaselImageInput {
    package let pngData: Data
    package let sourceURL: URL?
    package let pageTitle: String
    package let valid: () -> Bool
    package var capturedPage = false
    package var captureLayout: EaselCaptureLayout?
    package var capturedAt: Date?
    package var snapshotPDF: Data?
    package init(pngData: Data, sourceURL: URL?, pageTitle: String, valid: @escaping () -> Bool, capturedPage: Bool = false, captureLayout: EaselCaptureLayout? = nil, capturedAt: Date? = nil, snapshotPDF: Data? = nil) {
        self.pngData = pngData
        self.sourceURL = EaselStore.webAddress(sourceURL)
        self.pageTitle = pageTitle
        self.valid = valid
        self.capturedPage = capturedPage
        self.captureLayout = captureLayout
        self.capturedAt = capturedAt
        self.snapshotPDF = snapshotPDF
    }
    package var isValid: Bool { valid() }
}

@MainActor
package enum EaselImagePlacement {
    @MainActor
    package struct Result {
        let session: EaselSession
        package let itemID: UUID
        package var id: UUID { session.document.id }
        package var title: String { session.document.title }
    }
    package nonisolated static let maximumSide = 16_384
    package nonisolated static let maximumPixels = 80_000_000

    static func pixelSize(_ data: Data) throws -> NSSize {
        guard data.count <= EaselStore.maximumAssetBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maximumSide, height <= maximumSide,
              Int64(width) * Int64(height) <= Int64(maximumPixels),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw EaselStoreError.invalidImage }
        return NSSize(width: width, height: height)
    }

    package nonisolated static let maximumPictureInputBytes = 512 * 1024 * 1024

    package static func fitted(_ data: Data) throws -> Data {
        if let size = try? pixelSize(data), EaselAssetType.sniff(data) == .png, size.width > 0 { return data }
        return try fittedPicture(data).data
    }

    package static func fittedPicture(_ data: Data) throws -> (data: Data, size: CGSize) {
        guard !data.isEmpty, data.count <= maximumPictureInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw EaselStoreError.invalidImage }
        let longest = Double(max(width, height))
        var scale = min(1, Double(maximumSide) / longest, (Double(maximumPixels) / (Double(width) * Double(height))).squareRoot())
        for _ in 0..<16 {
            let side = max(1, Int((longest * scale).rounded(.down)))
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceShouldCacheImmediately: true,
                                            kCGImageSourceThumbnailMaxPixelSize: side]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  image.width > 0, image.height > 0 else { throw EaselStoreError.invalidImage }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
                throw EaselStoreError.invalidImage
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw EaselStoreError.invalidImage }
            if output.length <= EaselStore.maximumAssetBytes, image.width <= maximumSide, image.height <= maximumSide,
               Int64(image.width) * Int64(image.height) <= Int64(maximumPixels) {
                return (output as Data, CGSize(width: image.width, height: image.height))
            }
            scale *= 0.85
        }
        throw EaselStoreError.assetImageTooLarge
    }

    package static func place(_ image: EaselImageInput, in store: EaselStore, destinationID: UUID?,
                      newTitle: String, page: UUID? = nil) throws -> Result {
        guard image.isValid else { throw CocoaError(.userCancelled) }
        let pngData = try fitted(image.pngData)
        let size = try pixelSize(pngData)
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
            let assetID = try session.importPNG(pngData)
            let card = image.capturedPage && image.sourceURL != nil
            let snapshot = card ? image.snapshotPDF.flatMap { importedSnapshot($0, into: session) } : nil
            let pageSize = snapshot == nil ? nil : image.snapshotPDF.flatMap { CaptureSnapshotPDF(data: $0)?.size }
            let cardSize = EaselMediaPlacement.capturedCardSize(picture: (Double(size.width), Double(size.height)), page: pageSize)
            let target = EaselPages.resolvedPage(page, in: session.document)
            let onPage = EaselPages.view(session.document, page: target).items
            let bottom = onPage.map { $0.frame.y + $0.frame.height }.max() ?? 0
            let item = EaselItem(kind: card ? .webCard : .image,
                frame: EaselRect(x: 40, y: max(40, bottom + 32), width: cardSize.width, height: cardSize.height),
                zIndex: (onPage.map(\.zIndex).max() ?? 0) + 1,
                text: card ? image.pageTitle : "", url: image.sourceURL?.absoluteString, assetID: assetID, capturedAt: image.capturedAt ?? Date(),
                captureLayout: card ? image.captureLayout : nil, page: target, snapshot: snapshot)
            try session.perform(card ? "Add captured webpage" : "Add webpage image") { $0.items.append(item) }
            return Result(session: session, itemID: item.id)
        } catch {
            if let createdID { try? store.delete(createdID) }
            throw error
        }
    }

    static func importedSnapshot(_ data: Data, into session: EaselSession) -> String? {
        guard data.count <= EaselStore.maximumAssetBytes, CaptureSnapshotPDF(data: data) != nil, PDFDocument(data: data) != nil else { return nil }
        return try? session.importAsset(data, type: .pdf)
    }
}
