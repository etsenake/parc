import AppKit
import ParcCore

struct EaselSnapshotTileKey: Hashable {
    let asset: String
    let level: Int
    let column: Int
    let row: Int
}

struct EaselSnapshotTileCover: Equatable {
    var fallback: [EaselSnapshotTileKey]
    var uncovered: [CGRect]
}

struct EaselSnapshotTileQueue {
    let limit: Int
    private(set) var keys: [EaselSnapshotTileKey] = []

    init(limit: Int = 48) { self.limit = limit }

    @discardableResult
    mutating func push(_ key: EaselSnapshotTileKey) -> [EaselSnapshotTileKey] {
        keys.removeAll { $0 == key }
        keys.append(key)
        guard keys.count > limit else { return [] }
        let dropped = Array(keys.prefix(keys.count - limit))
        keys.removeFirst(keys.count - limit)
        return dropped
    }

    mutating func next() -> EaselSnapshotTileKey? { keys.popLast() }

    func contains(_ key: EaselSnapshotTileKey) -> Bool { keys.contains(key) }
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

    static func cover(_ missing: [EaselSnapshotTileKey], page: CGSize, sharperThan floor: CGFloat,
                      cached: (EaselSnapshotTileKey) -> Bool) -> EaselSnapshotTileCover {
        var fallback: Set<EaselSnapshotTileKey> = [], uncovered: [CGRect] = []
        for key in missing {
            let area = region(column: key.column, row: key.row, level: key.level, page: page)
            guard !area.isNull, area.width > 0, area.height > 0 else { continue }
            var found: [EaselSnapshotTileKey]?
            for level in reuseOrder(from: key.level) {
                if level < key.level, scale(of: level) <= floor { continue }
                let keys = covering(area, level: level, page: page, asset: key.asset)
                if !keys.isEmpty, keys.allSatisfy(cached) { found = keys; break }
            }
            if let found { fallback.formUnion(found) } else { uncovered.append(area) }
        }
        let ordered = fallback.sorted { ($0.level, $0.row, $0.column) < ($1.level, $1.row, $1.column) }
        return EaselSnapshotTileCover(fallback: ordered, uncovered: uncovered)
    }

    static func reuseOrder(from level: Int) -> [Int] {
        var order: [Int] = []
        for distance in 1...4 {
            if distance <= 2, levels.contains(level + distance) { order.append(level + distance) }
            if levels.contains(level - distance) { order.append(level - distance) }
        }
        return order
    }

    static func covering(_ area: CGRect, level: Int, page: CGSize, asset: String) -> [EaselSnapshotTileKey] {
        let side = tileSide(level: level)
        let columns = Int(ceil(page.width / side)), rows = Int(ceil(page.height / side))
        let first = (max(0, Int(floor(area.minX / side + 1e-9))), max(0, Int(floor(area.minY / side + 1e-9))))
        let last = (min(columns - 1, Int(ceil(area.maxX / side - 1e-9)) - 1), min(rows - 1, Int(ceil(area.maxY / side - 1e-9)) - 1))
        guard first.0 <= last.0, first.1 <= last.1, (last.0 - first.0 + 1) * (last.1 - first.1 + 1) <= 16 else { return [] }
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
    private var queued = EaselSnapshotTileQueue()
    private var sources: [EaselSnapshotTileKey: CaptureSnapshotPDF] = [:]
    private var rendering: EaselSnapshotTileKey?
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

    func contains(_ key: EaselSnapshotTileKey) -> Bool { tiles[key] != nil }

    func request(_ key: EaselSnapshotTileKey, from snapshot: CaptureSnapshotPDF) {
        guard tiles[key] == nil, rendering != key else { return }
        sources[key] = snapshot
        for dropped in queued.push(key) { sources.removeValue(forKey: dropped) }
        pump()
    }

    private func pump() {
        guard rendering == nil, let key = queued.next(), let snapshot = sources.removeValue(forKey: key) else { return }
        rendering = key
        queue.async { [weak self] in
            let image = EaselSnapshotTiling.render(snapshot, key: key)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rendering = nil
                    if let image {
                        self.store(image, for: key)
                        let region = EaselSnapshotTiling.region(column: key.column, row: key.row, level: key.level, page: snapshot.size)
                        NotificationCenter.default.post(name: Self.tileReady, object: key.asset,
                                                        userInfo: ["region": NSValue(rect: region), "page": NSValue(size: snapshot.size)])
                    }
                    self.pump()
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
        var fallback: [(EaselSnapshotTileKey, CGImage)] = []
        if keys.isEmpty {
            if let picture { EaselPictureRenderer.draw(picture, asset: pictureAsset, in: rect) }
        } else if ready.count < keys.count {
            let missing = keys.filter { !tiles.contains($0) }
            let floor = native.map { CGFloat($0.width) / snapshot.size.width } ?? 0
            let cover = EaselSnapshotTiling.cover(missing, page: snapshot.size, sharperThan: floor, cached: tiles.contains)
            if let picture, !cover.uncovered.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                let path = NSBezierPath()
                for area in cover.uncovered {
                    path.appendRect(EaselSnapshotTiling.canvasRect(of: area, card: rect, page: snapshot.size).insetBy(dx: -0.5, dy: -0.5))
                }
                path.addClip()
                EaselPictureRenderer.draw(picture, asset: pictureAsset, in: rect)
                NSGraphicsContext.restoreGraphicsState()
            }
            fallback = cover.fallback.compactMap { key in tiles.tile(key).map { (key, $0) } }
            for key in missing.reversed() { tiles.request(key, from: snapshot) }
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: rect).addClip()
        graphics.imageInterpolation = .high
        context.setShouldAntialias(false)
        for (key, image) in fallback + ready {
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
            }
        }
    }
}
