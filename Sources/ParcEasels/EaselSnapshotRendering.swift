import AppKit
import ParcCore

struct EaselSnapshotTileKey: Hashable {
    let asset: String
    let level: Int
    let column: Int
    let row: Int
}

enum EaselSnapshotTiling {
    static let tilePixels: CGFloat = 512
    static let levels = -8...6

    static func level(pixelsPerPoint: CGFloat) -> Int? {
        guard pixelsPerPoint.isFinite, pixelsPerPoint > 0 else { return nil }
        let level = Int(ceil(log2(Double(pixelsPerPoint)) - 1e-9))
        return min(max(level, levels.lowerBound), levels.upperBound)
    }

    static func scale(of level: Int) -> CGFloat { CGFloat(pow(2, Double(level))) }

    static func tileSide(level: Int) -> CGFloat { tilePixels / scale(of: level) }

    static func region(column: Int, row: Int, level: Int, page: CGSize) -> CGRect {
        let side = tileSide(level: level)
        return CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)
            .intersection(CGRect(origin: .zero, size: page))
    }

    static func tiles(visible: CGRect, card: CGRect, page: CGSize, level: Int, asset: String) -> [EaselSnapshotTileKey] {
        guard card.width > 0, card.height > 0, page.width > 0, page.height > 0 else { return [] }
        let shown = visible.intersection(card)
        guard !shown.isNull, shown.width > 0, shown.height > 0 else { return [] }
        let sx = page.width / card.width, sy = page.height / card.height
        let pageRect = CGRect(x: (shown.minX - card.minX) * sx, y: (shown.minY - card.minY) * sy,
                              width: shown.width * sx, height: shown.height * sy)
        let side = tileSide(level: level)
        let columns = Int(ceil(page.width / side)), rows = Int(ceil(page.height / side))
        let first = (max(0, Int(floor(pageRect.minX / side))), max(0, Int(floor(pageRect.minY / side))))
        let last = (min(columns - 1, Int(ceil(pageRect.maxX / side)) - 1), min(rows - 1, Int(ceil(pageRect.maxY / side)) - 1))
        guard first.0 <= last.0, first.1 <= last.1, (last.0 - first.0 + 1) * (last.1 - first.1 + 1) <= 4096 else { return [] }
        var keys: [EaselSnapshotTileKey] = []
        for row in first.1...last.1 {
            for column in first.0...last.0 { keys.append(EaselSnapshotTileKey(asset: asset, level: level, column: column, row: row)) }
        }
        return keys
    }

    static func canvasRect(of region: CGRect, card: CGRect, page: CGSize) -> CGRect {
        let sx = card.width / page.width, sy = card.height / page.height
        return CGRect(x: card.minX + region.minX * sx, y: card.minY + region.minY * sy, width: region.width * sx, height: region.height * sy)
    }

    static func render(_ snapshot: CaptureSnapshotPDF, key: EaselSnapshotTileKey) -> CGImage? {
        let page = snapshot.size
        let region = region(column: key.column, row: key.row, level: key.level, page: page)
        guard !region.isNull, region.width > 0, region.height > 0 else { return nil }
        return snapshot.render(region: region, in: CGRect(origin: .zero, size: page), pixelScale: scale(of: key.level), flipped: true)
    }
}

@MainActor
final class EaselSnapshotTiles {
    static let shared = EaselSnapshotTiles()
    static let tileReady = Notification.Name("ParcEaselSnapshotTileReady")

    let pixelBudget: Int
    private var tiles: [EaselSnapshotTileKey: CGImage] = [:]
    private var order: [EaselSnapshotTileKey] = []
    private(set) var pixelTotal = 0
    private var pending: Set<EaselSnapshotTileKey> = []
    private var documents: [String: CaptureSnapshotPDF] = [:]
    private var documentOrder: [String] = []
    private var unreadable: Set<String> = []
    private let queue = DispatchQueue(label: "org.parc.easel-snapshot", qos: .userInitiated)

    init(pixelBudget: Int = 32_000_000) {
        self.pixelBudget = pixelBudget
    }

    func snapshot(_ asset: String, data: () -> Data?) -> CaptureSnapshotPDF? {
        if let found = documents[asset] {
            if let index = documentOrder.firstIndex(of: asset) { documentOrder.remove(at: index) }
            documentOrder.append(asset)
            return found
        }
        guard !unreadable.contains(asset) else { return nil }
        guard let bytes = data(), let loaded = CaptureSnapshotPDF(data: bytes) else { unreadable.insert(asset); return nil }
        documents[asset] = loaded
        documentOrder.append(asset)
        while documentOrder.count > 6 { documents.removeValue(forKey: documentOrder.removeFirst()) }
        return loaded
    }

    func tile(_ key: EaselSnapshotTileKey) -> CGImage? {
        guard let image = tiles[key] else { return nil }
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
        return image
    }

    func store(_ image: CGImage, for key: EaselSnapshotTileKey) {
        if let old = tiles.updateValue(image, forKey: key) {
            pixelTotal -= old.width * old.height
            order.removeAll { $0 == key }
        }
        order.append(key)
        pixelTotal += image.width * image.height
        while pixelTotal > pixelBudget, order.count > 1 {
            let oldest = order.removeFirst()
            if let gone = tiles.removeValue(forKey: oldest) { pixelTotal -= gone.width * gone.height }
        }
    }

    func request(_ key: EaselSnapshotTileKey, from snapshot: CaptureSnapshotPDF) {
        guard tiles[key] == nil, pending.insert(key).inserted else { return }
        queue.async { [weak self] in
            let image = EaselSnapshotTiling.render(snapshot, key: key)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pending.remove(key)
                    guard let image else { return }
                    self.store(image, for: key)
                    let region = EaselSnapshotTiling.region(column: key.column, row: key.row, level: key.level, page: snapshot.size)
                    NotificationCenter.default.post(name: Self.tileReady, object: key.asset,
                                                    userInfo: ["region": NSValue(rect: region), "page": NSValue(size: snapshot.size)])
                }
            }
        }
    }
}

@MainActor
enum EaselSnapshotRenderer {
    static func draw(_ snapshot: CaptureSnapshotPDF, asset: String, picture: NSImage?, pictureAsset: String?, in rect: NSRect,
                     live: Bool) {
        let tiles = EaselSnapshotTiles.shared
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite,
              let graphics = NSGraphicsContext.current else { return }
        let context = graphics.cgContext
        guard live else {
            snapshot.draw(in: context, rect: rect, flipped: graphics.isFlipped)
            return
        }
        let ctm = context.ctm
        let device = sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c))
        let native = picture.flatMap(EaselPictureRenderer.nativeSize(of:))
        if let picture, let native, device <= CGFloat(native.width) / rect.width {
            EaselPictureRenderer.draw(picture, asset: pictureAsset, in: rect)
            return
        }
        guard let level = EaselSnapshotTiling.level(pixelsPerPoint: device * rect.width / snapshot.size.width) else { return }
        let visible = context.boundingBoxOfClipPath
        let keys = EaselSnapshotTiling.tiles(visible: visible.isInfinite ? rect : visible, card: rect, page: snapshot.size,
                                             level: level, asset: asset)
        let ready = keys.compactMap { key in tiles.tile(key).map { (key, $0) } }
        if keys.isEmpty || ready.count < keys.count {
            if let picture { EaselPictureRenderer.draw(picture, asset: pictureAsset, in: rect) }
            for key in keys where tiles.tile(key) == nil { tiles.request(key, from: snapshot) }
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: rect).addClip()
        graphics.imageInterpolation = .high
        context.setShouldAntialias(false)
        for (key, image) in ready {
            let region = EaselSnapshotTiling.region(column: key.column, row: key.row, level: key.level, page: snapshot.size)
            let target = EaselSnapshotTiling.canvasRect(of: region, card: rect, page: snapshot.size)
            NSImage(cgImage: image, size: target.size).draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                                                             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }
}

extension EaselCanvasView {
    func drawCapturedPage(_ item: EaselItem, in r: NSRect) {
        guard let id = item.assetID else { return }
        let picture = image(id)
        if let asset = item.snapshot,
           let snapshot = EaselSnapshotTiles.shared.snapshot(asset, data: { try? session.assetData(asset) }) {
            EaselSnapshotRenderer.draw(snapshot, asset: asset, picture: picture, pictureAsset: id, in: r, live: paintsLiveFeedback)
            return
        }
        if let picture { EaselPictureRenderer.draw(picture, asset: id, in: r) }
    }

    @objc func snapshotTileReady(_ note: Notification) {
        guard let asset = note.object as? String, let region = (note.userInfo?["region"] as? NSValue)?.rectValue,
              let page = (note.userInfo?["page"] as? NSValue)?.sizeValue else { return }
        for item in items where item.snapshot == asset && item.kind == .webCard {
            let card = rect(item)
            let dirty = (item.rotation ?? 0) == 0 && item.flipHorizontal != true && item.flipVertical != true
                ? EaselSnapshotTiling.canvasRect(of: region, card: card, page: page).insetBy(dx: -1, dy: -1)
                : displayBounds(of: item)
            if let view = artwork[item.id] {
                view.setNeedsDisplay(dirty.offsetBy(dx: -view.frame.minX, dy: -view.frame.minY))
            } else if !usesObjectSurfaces {
                setNeedsDisplay(dirty)
            }
        }
    }
}
