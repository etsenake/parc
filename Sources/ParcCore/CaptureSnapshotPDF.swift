import CoreGraphics
import Foundation

package struct CaptureSnapshotPDF: @unchecked Sendable {
    package static let maximumSide: CGFloat = 1_000_000

    package let document: CGPDFDocument
    package let page: CGPDFPage
    package let box: CGRect

    package init?(document: CGPDFDocument) {
        guard !document.isEncrypted || document.isUnlocked, document.numberOfPages >= 1,
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox).standardized
        guard box.width.isFinite, box.height.isFinite, box.width >= 1, box.height >= 1,
              box.width <= Self.maximumSide, box.height <= Self.maximumSide else { return nil }
        self.document = document
        self.page = page
        self.box = box
    }

    package init?(data: Data) {
        guard data.starts(with: Array("%PDF-".utf8)), let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return nil }
        self.init(document: document)
    }

    package init?(url: URL) {
        guard url.isFileURL, let document = CGPDFDocument(url as CFURL) else { return nil }
        self.init(document: document)
    }

    package var size: CGSize { box.size }

    package func transform(into rect: CGRect, flipped: Bool) -> CGAffineTransform {
        let sx = rect.width / box.width, sy = rect.height / box.height
        if flipped {
            return CGAffineTransform(a: sx, b: 0, c: 0, d: -sy, tx: rect.minX - box.minX * sx, ty: rect.maxY + box.minY * sy)
        }
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX - box.minX * sx, ty: rect.minY - box.minY * sy)
    }

    package func draw(in context: CGContext, rect: CGRect, flipped: Bool) {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        context.concatenate(transform(into: rect, flipped: flipped))
        context.clip(to: box)
        context.interpolationQuality = .high
        context.drawPDFPage(page)
    }

    package func render(region: CGRect, in rect: CGRect, pixelScale: CGFloat, flipped: Bool) -> CGImage? {
        let width = Int((region.width * pixelScale).rounded(.up)), height = Int((region.height * pixelScale).rounded(.up))
        guard pixelScale.isFinite, pixelScale > 0, width > 0, height > 0, width <= 8192, height <= 8192,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if flipped {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: pixelScale, y: -pixelScale)
        } else {
            context.scaleBy(x: pixelScale, y: pixelScale)
        }
        context.translateBy(x: -region.minX, y: -region.minY)
        draw(in: context, rect: rect, flipped: flipped)
        return context.makeImage()
    }
}
