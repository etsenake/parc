import AppKit
import ImageIO
import ParcCore
import UniformTypeIdentifiers
import ParcNotes

@MainActor
protocol EaselImageChromeHosting: AnyObject {
    func showCropBar(on canvas: EaselCanvasView, draft: EaselImageCropDraft)
    func hideCropBar(on canvas: EaselCanvasView)
    func editAltText(on canvas: EaselCanvasView, text: String, anchor: NSRect, commit: @escaping (String) -> Void)
    func pickMask(on canvas: EaselCanvasView, current: EaselImageMask?, preview: CGImage?, anchor: NSRect,
                  pick: @escaping (EaselImageMask?) -> Void)
}

@MainActor
final class EaselImageEditing {
    struct Crop {
        enum Drag {
            case pan(origin: NSPoint, picture: CGRect)
            case resize(NoteImageCropHandle, origin: NSPoint, frame: CGRect)
        }
        let item: EaselItem
        var draft: EaselImageCropDraft
        var drag: Drag?
    }

    var chrome: EaselImageChromeHosting?
    fileprivate(set) var crop: Crop?
    fileprivate var shownOverlay = NSRect.null
    fileprivate var gif: EaselGIFPlayer?
    fileprivate var animatedAssets: [String: Bool] = [:]
    fileprivate var zoomCheck = 0
}

final class EaselGIFDecoder: @unchecked Sendable {
    static let maximumAnimatedPixels = 2048 * 2048
    static let maximumFrames = 5_000
    let count: Int
    let maxPixel: Int
    let fullPixel: Int
    private let source: CGImageSource

    init?(data: Data, maxPixel: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1, count <= Self.maximumFrames,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width * height <= Self.maximumAnimatedPixels else { return nil }
        self.source = source
        self.count = count
        fullPixel = max(width, height)
        self.maxPixel = max(16, min(maxPixel, fullPixel))
    }

    func frame(at index: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                        kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    func delay(at index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let value = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return value.isFinite && value >= 0.02 ? min(value, 10) : 0.1
    }
}

private final class EaselGIFFrameBox: @unchecked Sendable {
    let image: CGImage?
    let delay: TimeInterval
    init(image: CGImage?, delay: TimeInterval) { self.image = image; self.delay = delay }
}

@MainActor
final class EaselGIFPlayer {
    let itemID: UUID
    let assetID: String
    private let decoder: EaselGIFDecoder
    private let size: NSSize
    private let queue = DispatchQueue(label: "org.parc.easel-gif", qos: .userInitiated)
    private var index = 0
    private var running = false
    private var generation = 0
    private var timer: Timer?
    private var tick: (() -> Void)?
    private(set) var frame: NSImage?

    init?(itemID: UUID, assetID: String, data: Data, size: NSSize, maxPixel: Int) {
        guard let decoder = EaselGIFDecoder(data: data, maxPixel: maxPixel) else { return nil }
        self.itemID = itemID
        self.assetID = assetID
        self.decoder = decoder
        self.size = size
    }

    var decodedPixel: Int { decoder.maxPixel }
    var fullPixel: Int { decoder.fullPixel }

    func start(_ tick: @escaping () -> Void) {
        timer?.invalidate()
        generation &+= 1
        self.tick = tick
        running = true
        load(0, generation: generation)
    }

    func stop() {
        generation &+= 1
        running = false
        timer?.invalidate()
        timer = nil
        tick = nil
        frame = nil
    }

    private func load(_ next: Int, generation: Int) {
        let decoder = self.decoder
        queue.async { [weak self] in
            let box = EaselGIFFrameBox(image: decoder.frame(at: next), delay: decoder.delay(at: next))
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.show(box, at: next, generation: generation) }
            }
        }
    }

    private func show(_ box: EaselGIFFrameBox, at next: Int, generation: Int) {
        guard running, generation == self.generation else { return }
        index = next
        if let image = box.image { frame = NSImage(cgImage: image, size: size) }
        tick?()
        let timer = Timer(timeInterval: box.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running, self.generation == generation else { return }
                self.load((self.index + 1) % self.decoder.count, generation: generation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension EaselCanvasView {
    var selectedImage: EaselItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return session.document.items.first { $0.id == id && $0.kind == .image }
    }

    var selectedMedia: EaselItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return session.document.items.first { $0.id == id && ($0.kind == .image || $0.kind == .video) }
    }

    @discardableResult
    func openMedia(_ item: EaselItem) -> Bool {
        if item.isEmptyPlaceholder { return performHostedAction(.upload, on: item.id) }
        if item.kind == .video { return playVideo(item.id) }
        if item.kind == .pdf { return performHostedAction(.fullScreen, on: item.id) }
        if item.kind == .audio || item.kind == .file { return performHostedAction(.quickLook, on: item.id) }
        if selection != [item.id] { selection = [item.id] }
        return beginImageCrop()
    }

    var canEditSelectedImage: Bool {
        guard let item = selectedImage else { return false }
        return !item.isLocked && !session.isClosed && !session.isDeleted && naturalImageSize(of: item) != nil
    }

    var isCroppingImage: Bool { imageEditing.crop != nil }
    var hasImageChrome: Bool { imageEditing.chrome != nil }
    var imageCropDraft: EaselImageCropDraft? { imageEditing.crop?.draft }

    private func frameRect(_ item: EaselItem) -> NSRect {
        NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
    }

    private func turnedBounds(_ rect: NSRect) -> NSRect {
        let half = hypot(rect.width, rect.height) / 2
        return NSRect(x: rect.midX - half, y: rect.midY - half, width: half * 2, height: half * 2)
    }

    func naturalImageSize(of item: EaselItem) -> CGSize? {
        guard let id = item.assetID, let size = image(id)?.size, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return size
    }

    func imageAspect(_ item: EaselItem) -> Double? {
        guard let natural = naturalImageSize(of: item),
              let aspect = EaselImageFraming.displayAspect(natural: natural, crop: item.crop, turns: item.resolvedQuarterTurns) else { return nil }
        return Double(aspect)
    }

    func isAnimatedImage(_ item: EaselItem) -> Bool {
        guard item.kind == .image, let id = item.assetID, EaselAssetType.of(assetID: id) == .gif else { return false }
        if let known = imageEditing.animatedAssets[id] { return known }
        var animated = false
        if let data = try? session.assetData(id), let source = CGImageSourceCreateWithData(data as CFData, nil) {
            animated = CGImageSourceGetCount(source) > 1
        }
        imageEditing.animatedAssets[id] = animated
        return animated
    }

    func drawImageObject(_ item: EaselItem, in r: NSRect) {
        guard imageEditing.crop?.item.id != item.id, let picture = displayedPicture(for: item) else { return }
        guard EaselImageFraming.isFramed(item) else {
            picture.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(item.mask?.path(in: r) ?? CGPath(rect: r, transform: nil))
        context.clip()
        let turns = item.resolvedQuarterTurns
        drawPicture(picture, in: EaselImageFraming.pictureRect(frame: r, crop: item.crop, turns: turns), turns: turns)
    }

    private func displayedPicture(for item: EaselItem) -> NSImage? {
        guard let id = item.assetID else { return nil }
        if let player = imageEditing.gif, player.itemID == item.id, player.assetID == id, let frame = player.frame { return frame }
        return image(id)
    }

    private func drawPicture(_ picture: NSImage, in rect: CGRect, turns: Int) {
        let value = EaselImageFraming.turns(turns)
        guard value != 0, let context = NSGraphicsContext.current?.cgContext else {
            picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: EaselImageFraming.angle(turns: value))
        let size = EaselImageFraming.turnedSize(rect.size, turns: value)
        picture.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    func renderImageThumbnail(_ item: EaselItem, side: CGFloat = 160) -> CGImage? {
        guard let picture = image(item.assetID ?? ""), item.frame.width > 0, item.frame.height > 0 else { return nil }
        let scale = side / CGFloat(max(item.frame.width, item.frame.height))
        let width = max(1, Int((CGFloat(item.frame.width) * scale).rounded())), height = max(1, Int((CGFloat(item.frame.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let turns = item.resolvedQuarterTurns
        drawPicture(picture, in: EaselImageFraming.pictureRect(frame: frame, crop: item.crop, turns: turns), turns: turns)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    static let gifPasteboardType = NSPasteboard.PasteboardType("com.compuserve.gif")

    func drawImageDecorations(in dirtyRect: NSRect) -> Bool {
        if let crop = imageEditing.crop {
            drawCropOverlay(crop)
            return true
        }
        for item in items where item.kind == .image {
            let r = frameRect(item)
            if displayedSelection == [item.id], let box = imageCreditRect(item), box.intersects(dirtyRect) {
                drawMediaCredit(item, in: creditAnchor(item))
            }
            guard r.insetBy(dx: -4, dy: -4).intersects(dirtyRect) else { continue }
            if imageEditing.gif?.itemID != item.id, isAnimatedImage(item), let badge = imageBadgeRect("GIF", in: r, bottom: false) {
                drawImageBadge("GIF", in: badge)
            }
            if item.id == hoveredObjectID, let alt = item.altText, !alt.isEmpty, let badge = imageBadgeRect("ALT", in: r, bottom: true) {
                drawImageBadge("ALT", in: badge)
            }
        }
        return false
    }

    private static let badgeFontSize: CGFloat = 10

    private func creditAnchor(_ item: EaselItem) -> NSRect {
        let bounds = EaselRotation.bounds(of: item)
        return NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
    }

    func imageCreditRect(_ item: EaselItem) -> NSRect? {
        guard item.kind == .image, item.credit != nil else { return nil }
        let anchor = creditAnchor(item)
        return NSRect(x: anchor.minX, y: anchor.maxY + CGFloat(EaselVectorExport.creditGap), width: anchor.width,
                      height: CGFloat(EaselVectorExport.creditHeight))
    }

    private func creditTarget(at point: NSPoint) -> URL? {
        guard selection.count == 1, let id = selection.first, let item = items.first(where: { $0.id == id }),
              let box = imageCreditRect(item), box.contains(point), let credit = EaselVectorExport.mediaCredit(item) else { return nil }
        return credit.profileURL ?? credit.provider?.url
    }

    private func imageBadgeRect(_ text: String, in frame: NSRect, bottom: Bool) -> NSRect? {
        let scale = CGFloat(canvasScale)
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.nunitoExtraBold(Self.badgeFontSize), .kern: 0.6]
        let width = (ceil((text as NSString).size(withAttributes: attributes).width) + 12) / scale, height = 18 / scale
        let inset = 8 / scale
        guard frame.width > width + inset * 2, frame.height > height + inset * 2 else { return nil }
        return NSRect(x: frame.minX + inset, y: bottom ? frame.maxY - inset - height : frame.minY + inset, width: width, height: height)
    }

    private func drawImageBadge(_ text: String, in rect: NSRect) {
        let scale = CGFloat(canvasScale)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5 / scale, yRadius: 5 / scale)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NoteTheme.menuShadow
        shadow.shadowBlurRadius = 4 / scale
        shadow.shadowOffset = NSSize(width: 0, height: -1 / scale)
        shadow.set()
        NoteTheme.menuFill.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NoteTheme.menuHairline.setStroke()
        shape.lineWidth = 0.5 / scale
        shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.nunitoExtraBold(Self.badgeFontSize / scale),
                                                         .foregroundColor: NoteTheme.menuInk, .kern: 0.6 / scale]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    private func altBadgeTarget(at point: NSPoint) -> EaselItem? {
        guard imageEditing.crop == nil, let id = hoveredObjectID,
              let item = session.document.items.first(where: { $0.id == id && $0.kind == .image && !$0.isLocked }),
              let alt = item.altText, !alt.isEmpty, let badge = imageBadgeRect("ALT", in: frameRect(item), bottom: true),
              badge.contains(point) else { return nil }
        return item
    }

    private func drawCropOverlay(_ crop: EaselImageEditing.Crop) {
        guard cropIsCurrent(crop) else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let current = self.imageEditing.crop, current.item == crop.item, !self.cropIsCurrent(current) else { return }
                    self.finishImageCrop(save: false)
                }
            }
            return
        }
        guard let picture = image(crop.item.assetID ?? ""), let context = NSGraphicsContext.current?.cgContext else { return }
        let draft = crop.draft, frame = draft.frame, scale = CGFloat(canvasScale)
        drawPicture(picture, in: draft.picture, turns: draft.turns)
        context.saveGState()
        defer { context.restoreGState() }
        let dim = CGMutablePath()
        dim.addRect(draft.picture)
        dim.addPath(draft.mask?.path(in: frame) ?? CGPath(rect: frame, transform: nil))
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(NSColor.white.withAlphaComponent(draft.mask == nil ? 0.9 : 0.45).cgColor)
        context.setLineWidth(1 / scale)
        context.stroke(frame.insetBy(dx: 0.5 / scale, dy: 0.5 / scale))
        if let mask = draft.mask {
            context.saveGState()
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5 / scale)
            context.setLineDash(phase: 0, lengths: [5 / scale, 4 / scale])
            context.addPath(mask.path(in: frame))
            context.strokePath()
            context.restoreGState()
        }
        if crop.drag != nil {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(1 / scale)
            for step in 1...2 {
                let x = frame.minX + frame.width * CGFloat(step) / 3, y = frame.minY + frame.height * CGFloat(step) / 3
                context.move(to: CGPoint(x: x, y: frame.minY)); context.addLine(to: CGPoint(x: x, y: frame.maxY))
                context.move(to: CGPoint(x: frame.minX, y: y)); context.addLine(to: CGPoint(x: frame.maxX, y: y))
            }
            context.strokePath()
        }
        context.setShadow(offset: .zero, blur: 2 / scale, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(3 / scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(cropHandlePath(for: frame, scale: scale))
        context.strokePath()
    }

    private func cropHandlePath(for rect: CGRect, scale: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let arm = min(16 / scale, rect.width / 3, rect.height / 3)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [(CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
                                                      (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1), (CGPoint(x: rect.minX, y: rect.maxY), 1, -1)]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        let bar = min(18 / scale, rect.width / 4, rect.height / 4)
        if rect.width > 3 * arm + bar {
            for y in [rect.minY, rect.maxY] {
                path.move(to: CGPoint(x: rect.midX - bar / 2, y: y)); path.addLine(to: CGPoint(x: rect.midX + bar / 2, y: y))
            }
        }
        if rect.height > 3 * arm + bar {
            for x in [rect.minX, rect.maxX] {
                path.move(to: CGPoint(x: x, y: rect.midY - bar / 2)); path.addLine(to: CGPoint(x: x, y: rect.midY + bar / 2))
            }
        }
        return path
    }

    private func cropHandleRect(_ handle: NoteImageCropHandle, in rect: CGRect) -> CGRect {
        let reach = 12 / CGFloat(canvasScale)
        let x = handle.movesLeft ? rect.minX : handle.movesRight ? rect.maxX : rect.midX
        let y = handle.movesTop ? rect.minY : handle.movesBottom ? rect.maxY : rect.midY
        if handle.isCorner { return CGRect(x: x - reach, y: y - reach, width: reach * 2, height: reach * 2) }
        if handle.movesLeft || handle.movesRight {
            return CGRect(x: x - reach, y: rect.minY + reach, width: reach * 2, height: max(0, rect.height - reach * 2))
        }
        return CGRect(x: rect.minX + reach, y: y - reach, width: max(0, rect.width - reach * 2), height: reach * 2)
    }

    private func cropHandle(at point: NSPoint, in rect: CGRect) -> NoteImageCropHandle? {
        for handle in NoteImageCropHandle.allCases where handle.isCorner && cropHandleRect(handle, in: rect).contains(point) { return handle }
        for handle in NoteImageCropHandle.allCases where !handle.isCorner && cropHandleRect(handle, in: rect).contains(point) { return handle }
        return nil
    }

    private static func cropCursor(for handle: NoteImageCropHandle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if handle.isCorner { return .crosshair }
        return handle.movesTop || handle.movesBottom ? .resizeUpDown : .resizeLeftRight
    }

    func addImageBadgeCursorRects() {
        guard imageEditing.crop == nil else { return }
        if selection.count == 1, let id = selection.first, let item = items.first(where: { $0.id == id }), let box = imageCreditRect(item) {
            addCursorRect(box, cursor: .pointingHand)
        }
        for item in session.document.items where item.kind == .image && !(item.altText ?? "").isEmpty {
            if let badge = imageBadgeRect("ALT", in: frameRect(item), bottom: true) { addCursorRect(badge, cursor: .pointingHand) }
        }
        let playing = playingHostedVideo
        for item in session.document.items where item.kind == .video && item.id != playing {
            if let disc = videoPlayRect(in: frameRect(item)) { addCursorRect(disc, cursor: .pointingHand) }
        }
    }

    func addImageCropCursorRects() -> Bool {
        guard let crop = imageEditing.crop else { return false }
        addCursorRect(bounds, cursor: .arrow)
        addCursorRect(crop.draft.picture, cursor: crop.drag == nil ? .openHand : .closedHand)
        for handle in NoteImageCropHandle.allCases.reversed() {
            addCursorRect(cropHandleRect(handle, in: crop.draft.frame), cursor: Self.cropCursor(for: handle))
        }
        return true
    }

    private func cropIsCurrent(_ crop: EaselImageEditing.Crop) -> Bool {
        !session.isClosed && !session.isDeleted && window != nil && session.document.items.contains { $0 == crop.item }
    }

    private func cropChanged() {
        let pad = 24 / CGFloat(canvasScale)
        let shown = imageEditing.crop.map { $0.draft.picture.union($0.draft.frame).union(frameRect($0.item)).insetBy(dx: -pad, dy: -pad) } ?? .null
        let dirty = imageEditing.shownOverlay.union(shown)
        if !dirty.isNull, dirty.width.isFinite, dirty.height.isFinite { setOverlayNeedsDisplay(dirty) }
        imageEditing.shownOverlay = shown
        if let crop = imageEditing.crop { imageEditing.chrome?.showCropBar(on: self, draft: crop.draft) }
        window?.invalidateCursorRects(for: self)
    }

    private func updateCrop(_ change: (inout EaselImageEditing.Crop) -> Void) {
        guard var crop = imageEditing.crop else { return }
        guard cropIsCurrent(crop) else { finishImageCrop(save: false); return }
        change(&crop)
        imageEditing.crop = crop
        cropChanged()
    }

    @discardableResult
    func beginImageCrop() -> Bool {
        guard imageEditing.crop == nil, canEditSelectedImage, let item = selectedImage, let natural = naturalImageSize(of: item),
              window != nil else { return false }
        cancelPointerInteraction()
        guard finishEditing(), session.document.items.contains(where: { $0 == item }) else { return false }
        if drawing { drawing = false }
        stopImagePlayback()
        imageEditing.crop = EaselImageEditing.Crop(item: item, draft: EaselImageCropDraft(item: item, natural: natural), drag: nil)
        artwork[item.id]?.needsDisplay = true
        window?.makeFirstResponder(self)
        cropChanged()
        refreshDecorations()
        invalidateIncrementalDisplay(layout: true)
        refreshTextControls()
        NSAccessibility.post(element: self, notification: .layoutChanged)
        return true
    }

    func finishImageCrop(save: Bool) {
        guard let crop = imageEditing.crop else { return }
        imageEditing.crop = nil
        imageEditing.chrome?.hideCropBar(on: self)
        cropChanged()
        refreshDecorations()
        artwork[crop.item.id]?.needsDisplay = true
        if save, let current = session.document.items.first(where: { $0.id == crop.item.id }), current == crop.item {
            let next = crop.draft.applying(to: current)
            if next != current {
                commit("Crop image") { document in
                    guard let index = document.items.firstIndex(where: { $0.id == current.id }) else { return }
                    let previous = document
                    document.items[index] = next
                    document = EaselDependents.settle(document, previous: previous, moved: [current.id])
                }
            }
        }
        invalidateIncrementalDisplay(layout: true)
        refreshTextControls()
        refreshImagePlayback()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func setCropAspect(_ aspect: NoteImageCropAspect) { updateCrop { $0.draft.setAspect(aspect) } }
    func setCropMask(_ mask: EaselImageMask?) { updateCrop { $0.draft.setMask(mask) } }
    func setCropZoom(_ zoom: CGFloat) { updateCrop { $0.draft.setZoom(zoom) } }
    func zoomImageCrop(by factor: CGFloat) { updateCrop { $0.draft.setZoom($0.draft.zoom * factor) } }
    func rotateImageCrop() { updateCrop { $0.draft.rotate() } }
    func resetImageCrop() { updateCrop { $0.draft.reset() } }
    func panImageCrop(dx: CGFloat, dy: CGFloat) { updateCrop { $0.draft.move(by: CGSize(width: dx, height: dy)) } }

    func presentCropMaskPicker(anchor: NSRect) {
        guard let crop = imageEditing.crop, let chrome = imageEditing.chrome else { return }
        chrome.pickMask(on: self, current: crop.draft.mask, preview: renderImageThumbnail(crop.draft.applying(to: crop.item)),
                        anchor: anchor) { [weak self] mask in self?.setCropMask(mask) }
    }

    func showImageMaskPicker(anchor: NSRect? = nil) {
        guard canEditSelectedImage, let item = selectedImage, let chrome = imageEditing.chrome else { return }
        chrome.pickMask(on: self, current: item.mask, preview: renderImageThumbnail(item), anchor: anchor ?? frameRect(item)) { [weak self] mask in
            self?.setImageMask(mask)
        }
    }

    func imageMouseDown(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        guard var crop = imageEditing.crop else {
            if event.clickCount == 1, let url = creditTarget(at: point) {
                onOpenURL?(url)
                return true
            }
            if event.clickCount == 1, let video = videoPlayTarget(at: point) {
                window?.makeFirstResponder(self)
                playVideo(video.id)
                return true
            }
            if event.clickCount == 1, let item = altBadgeTarget(at: point) {
                selection = [item.id]
                editImageAltText(for: item)
                return true
            }
            return false
        }
        guard cropIsCurrent(crop) else { finishImageCrop(save: false); return false }
        if let handle = cropHandle(at: point, in: crop.draft.frame) {
            crop.drag = .resize(handle, origin: point, frame: crop.draft.frame)
        } else if crop.draft.picture.contains(point) {
            crop.drag = .pan(origin: point, picture: crop.draft.picture)
        } else {
            finishImageCrop(save: true)
            return false
        }
        imageEditing.crop = crop
        window?.makeFirstResponder(self)
        cropChanged()
        return true
    }

    func imageMouseDragged(_ event: NSEvent) -> Bool {
        guard let crop = imageEditing.crop else { return false }
        guard let drag = crop.drag else { return true }
        let point = convert(event.locationInWindow, from: nil)
        updateCrop { crop in
            switch drag {
            case .pan(let origin, let picture):
                crop.draft.picture = picture
                crop.draft.move(by: CGSize(width: point.x - origin.x, height: point.y - origin.y))
            case .resize(let handle, let origin, let frame):
                crop.draft.resize(handle, from: frame, by: CGSize(width: point.x - origin.x, height: point.y - origin.y),
                                  lockingAspect: event.modifierFlags.contains(.shift))
            }
        }
        autoscroll(with: event)
        return true
    }

    func imageMouseUp(_ event: NSEvent) -> Bool {
        guard imageEditing.crop != nil else { return false }
        updateCrop { $0.drag = nil }
        return true
    }

    func imageKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, playingHostedVideo != nil {
            pauseVideo()
            return true
        }
        guard imageEditing.crop != nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 36, 76: finishImageCrop(save: true)
        case 53: finishImageCrop(save: false)
        case 123: panImageCrop(dx: -step, dy: 0)
        case 124: panImageCrop(dx: step, dy: 0)
        case 125: panImageCrop(dx: 0, dy: step)
        case 126: panImageCrop(dx: 0, dy: -step)
        case 24, 69: zoomImageCrop(by: 1.25)
        case 27, 78: zoomImageCrop(by: 0.8)
        case 48: return false
        default: break
        }
        return true
    }

    func cancelImageCrop() -> Bool {
        guard imageEditing.crop != nil else { return false }
        finishImageCrop(save: false)
        return true
    }

    func setImageMask(_ mask: EaselImageMask?) {
        if imageEditing.crop != nil { setCropMask(mask); return }
        let targets = Set(session.document.items.filter { selection.contains($0.id) && $0.kind == .image && !$0.isLocked }.map(\.id))
        guard !targets.isEmpty else { return }
        cancelPointerInteraction()
        guard finishEditing() else { return }
        commit(mask == nil ? "Remove mask" : "Mask image") { document in
            let previous = document
            for index in document.items.indices where targets.contains(document.items[index].id) {
                document.items[index] = EaselImageFraming.masking(document.items[index], with: mask)
            }
            document = EaselDependents.settle(document, previous: previous, moved: targets)
        }
    }

    func editImageAltText() {
        guard let item = selectedMedia else { return }
        editImageAltText(for: item)
    }

    private func editImageAltText(for item: EaselItem) {
        guard !item.isLocked, !session.isClosed, !session.isDeleted, let chrome = imageEditing.chrome else { return }
        chrome.editAltText(on: self, text: item.altText ?? "", anchor: frameRect(item)) { [weak self] text in
            self?.setImageAltText(text, for: item.id)
        }
    }

    func setImageAltText(_ text: String, for id: UUID) {
        let value = EaselTableData.clipped(text.trimmingCharacters(in: .whitespacesAndNewlines), bytes: 4096)
        let alt: String? = value.isEmpty ? nil : value
        guard let item = session.document.items.first(where: { $0.id == id && ($0.kind == .image || $0.kind == .video) }), !item.isLocked,
              item.altText != alt else { return }
        commit(alt == nil ? "Remove alt text" : "Alt text") { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
            document.items[index].altText = alt
        }
    }

    func chooseReplacementImage() {
        guard canEditSelectedImage, let item = selectedImage, let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Pick a picture to swap in. It keeps this one’s size and spot."
        panel.beginSheetModal(for: window) { [weak self, weak window] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                guard let self, let window, self.window === window else { return }
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size <= EaselStore.maximumAssetBytes else { throw EaselStoreError.assetImageTooLarge }
                    try self.replaceImage(id: item.id, data: Data(contentsOf: url, options: .mappedIfSafe))
                } catch { self.onError?(error) }
            }
        }
    }

    func replaceImage(id: UUID, data: Data) throws {
        guard let current = session.document.items.first(where: { $0.id == id && $0.kind == .image }), !current.isLocked else {
            throw EaselStoreError.invalidImage
        }
        let asset = try preparedImageAsset(data)
        if imageEditing.crop?.item.id == id { finishImageCrop(save: false) }
        cancelPointerInteraction()
        guard finishEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        let assetID = try session.importAsset(asset.data, type: asset.type)
        var next = EaselImageFraming.replacing(current, natural: asset.pixelSize)
        next.assetID = assetID
        try session.perform("Replace image") { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }), document.items[index] == current else {
                throw EaselStoreError.invalidDocument("the image changed while it was being replaced")
            }
            document.items[index] = next
        }
        selection = [id]
        invalidateIncrementalDisplay(layout: true)
        refreshImagePlayback()
    }

    func replaceSelectedImageFromPasteboard(_ pasteboard: NSPasteboard) -> Bool? {
        guard canEditSelectedImage, let item = selectedImage, let data = pastedImageData(pasteboard) else { return nil }
        do {
            try replaceImage(id: item.id, data: data)
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    func replaceImage(fromDrop sender: NSDraggingInfo) -> Bool? {
        guard let item = selectedImage, frameRect(item).contains(convert(sender.draggingLocation, from: nil)) else { return nil }
        return replaceSelectedImageFromPasteboard(sender.draggingPasteboard)
    }

    func pastedImageData(_ pasteboard: NSPasteboard, _ reading: NoteClipboard.Reading? = nil) -> Data? {
        let reading = reading ?? NoteClipboard.read(pasteboard)
        guard reading.files.isEmpty else {
            guard reading.files.count == 1, let url = reading.files.first,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey]), values.isRegularFile == true,
                  values.contentType?.conforms(to: .image) == true, let size = values.fileSize, size <= EaselStore.maximumAssetBytes else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
        return pasteboard.data(forType: Self.gifPasteboardType) ?? reading.image
    }

    func preparedImageAsset(_ data: Data) throws -> (data: Data, type: EaselAssetType, pixelSize: CGSize) {
        guard data.count <= EaselStore.maximumAssetBytes else { throw EaselStoreError.assetImageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, Int64(width) * Int64(height) <= 80_000_000 else {
            throw EaselStoreError.invalidImage
        }
        let frames = CGImageSourceGetCount(source)
        if EaselAssetType.sniff(data) == .gif, frames > 1, frames <= EaselGIFDecoder.maximumFrames, width * height <= EaselGIFDecoder.maximumAnimatedPixels {
            guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw EaselStoreError.invalidImage }
            return (data, .gif, CGSize(width: width, height: height))
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        let output = NSMutableData()
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), oriented.width > 0, oriented.height > 0,
              let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw EaselStoreError.invalidImage
        }
        CGImageDestinationAddImage(destination, oriented, nil)
        guard CGImageDestinationFinalize(destination) else { throw EaselStoreError.invalidImage }
        return (output as Data, .png, CGSize(width: oriented.width, height: oriented.height))
    }

    func insertImageData(_ data: Data, at point: NSPoint? = nil) throws {
        let asset = try preparedImageAsset(data)
        cancelPointerInteraction()
        guard finishEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        if drawing { drawing = false }
        let natural = (width: Double(asset.pixelSize.width), height: Double(asset.pixelSize.height))
        let visible = fixedCanvasSize == nil ? uncoveredVisibleRect : visibleRect
        let centre = point ?? NSPoint(x: visible.midX, y: visible.midY)
        let frame: EaselRect
        if fixedCanvasSize == nil {
            let fitted = EaselMediaPlacement.filledSize(for: .image, natural: natural)
            guard let placed = EaselMediaPlacement.row(of: [fitted], centredAt: EaselPoint(x: Double(centre.x), y: Double(centre.y))).first else {
                throw EaselStoreError.invalidImage
            }
            frame = placed
        } else {
            let width = min(480.0, natural.width)
            frame = EaselRect(x: 0, y: 0, width: width, height: max(1, width * natural.height / natural.width))
        }
        let assetID = try session.importAsset(asset.data, type: asset.type)
        var item = EaselItem(kind: .image, frame: frame, zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1, assetID: assetID)
        if let size = fixedCanvasSize {
            let ratio = min(1, size.width / item.frame.width, size.height / item.frame.height)
            item.frame.width *= ratio; item.frame.height *= ratio
            item.frame.x = max(0, min(visible.midX - item.frame.width / 2, size.width - item.frame.width))
            item.frame.y = max(0, min(visible.midY - item.frame.height / 2, size.height - item.frame.height))
        }
        try session.perform("Add image") { $0.items.append(item) }
        selection = [item.id]
    }

    func refreshImagePlayback() {
        if let video = playingHostedVideo, selection != [video] { stopVideoPlayback() }
        if let crop = imageEditing.crop, selection != [crop.item.id] { finishImageCrop(save: true) }
        guard imageEditing.crop == nil, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let item = selectedImage, let asset = item.assetID, isAnimatedImage(item) else {
            stopImagePlayback()
            return
        }
        let maxPixel = gifPixelSize(for: item)
        if let player = imageEditing.gif, player.itemID == item.id, player.assetID == asset,
           maxPixel <= player.decodedPixel || player.decodedPixel >= player.fullPixel { return }
        stopImagePlayback()
        guard let data = try? session.assetData(asset), let size = image(asset)?.size,
              let player = EaselGIFPlayer(itemID: item.id, assetID: asset, data: data, size: size, maxPixel: maxPixel) else { return }
        imageEditing.gif = player
        player.start { [weak self] in self?.imagePlaybackAdvanced() }
        imagePlaybackAdvanced()
    }

    func imageZoomChanged() {
        guard imageEditing.gif != nil else { return }
        imageEditing.zoomCheck &+= 1
        let check = imageEditing.zoomCheck
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.imageEditing.zoomCheck == check else { return }
            self.refreshImagePlayback()
        }
    }

    private func gifPixelSize(for item: EaselItem) -> Int {
        let crop = item.crop.map { max(1 / max($0.width, 0.0001), 1 / max($0.height, 0.0001)) } ?? 1
        let side = CGFloat(max(item.frame.width, item.frame.height)) * CGFloat(max(1, crop))
        let needed = side * CGFloat(canvasScale) * (window?.backingScaleFactor ?? 2)
        guard needed.isFinite else { return 4096 }
        return Int(min(4096, max(1, needed)).rounded(.up))
    }

    func imageDocumentChanged() {
        if let crop = imageEditing.crop, !cropIsCurrent(crop) { finishImageCrop(save: false) }
        if let player = imageEditing.gif,
           session.document.items.first(where: { $0.id == player.itemID })?.assetID != player.assetID { stopImagePlayback() }
    }

    func stopImagePlayback() {
        guard let player = imageEditing.gif else { return }
        imageEditing.gif = nil
        player.stop()
        if let item = session.document.items.first(where: { $0.id == player.itemID }) {
            setOverlayNeedsDisplay(turnedBounds(frameRect(item)))
            artwork[item.id]?.needsDisplay = true
        }
    }

    private func imagePlaybackAdvanced() {
        guard let player = imageEditing.gif else { return }
        guard window != nil, selection == [player.itemID],
              let item = session.document.items.first(where: { $0.id == player.itemID }), item.assetID == player.assetID else {
            stopImagePlayback()
            return
        }
        setOverlayNeedsDisplay(turnedBounds(frameRect(item)))
        artwork[item.id]?.needsDisplay = true
    }

    func addImageMenuItems(to menu: NSMenu, target: Any) {
        if let video = selectedMedia, video.kind == .video, !video.isLocked {
            menu.addItem(.separator())
            let playing = isPlayingVideo(video.id)
            let play = NSMenuItem(title: playing ? "Pause Video" : "Play Video", action: #selector(playVideoFromMenu(_:)), keyEquivalent: "")
            play.target = self; play.representedObject = target; menu.addItem(play)
            let alt = NSMenuItem(title: "Alt Text…", action: #selector(editAltTextFromMenu(_:)), keyEquivalent: "")
            alt.target = self; alt.representedObject = target; menu.addItem(alt)
            return
        }
        guard let item = selectedImage, !item.isLocked else { return }
        menu.addItem(.separator())
        let crop = NSMenuItem(title: "Crop Image", action: #selector(cropImageFromMenu(_:)), keyEquivalent: "")
        crop.target = self; crop.representedObject = target; menu.addItem(crop)
        let mask = NSMenuItem(title: "Mask", action: nil, keyEquivalent: "")
        let shapes = NSMenu(title: "Mask")
        let options: [EaselImageMask?] = [nil] + EaselImageMask.allCases.map(Optional.some)
        for (index, option) in options.enumerated() {
            let row = NSMenuItem(title: option?.title ?? NoteImageMask.noneTitle, action: #selector(maskImageFromMenu(_:)), keyEquivalent: "")
            row.target = self; row.representedObject = target; row.tag = index
            row.state = item.mask == option ? .on : .off
            shapes.addItem(row)
            if option == nil { shapes.addItem(.separator()) }
        }
        mask.submenu = shapes
        menu.addItem(mask)
        for (title, action) in [("Alt Text…", #selector(editAltTextFromMenu(_:))), ("Replace Image…", #selector(replaceImageFromMenu(_:)))] {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self; row.representedObject = target; menu.addItem(row)
        }
    }

    func imageCropMenu() -> NSMenu? {
        guard let crop = imageEditing.crop else { return nil }
        let menu = NSMenu()
        let aspect = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        let ratios = NSMenu(title: "Aspect Ratio")
        for (index, option) in NoteImageCropAspect.allCases.enumerated() {
            let row = NSMenuItem(title: option.title, action: #selector(cropAspectFromMenu(_:)), keyEquivalent: "")
            row.target = self; row.tag = index
            row.state = crop.draft.aspect == option && crop.draft.mask != .circle ? .on : .off
            row.isEnabled = crop.draft.mask?.isSquare != true || option == .square
            ratios.addItem(row)
        }
        let circle = NSMenuItem(title: "Circle", action: #selector(cropCircleFromMenu(_:)), keyEquivalent: "")
        circle.target = self; circle.state = crop.draft.mask == .circle ? .on : .off
        ratios.addItem(circle)
        ratios.autoenablesItems = false
        aspect.submenu = ratios
        menu.addItem(aspect)
        let rows: [(String, Selector)] = [("Rotate 90°", #selector(rotateCropFromMenu(_:))), ("Zoom In", #selector(zoomInCropFromMenu(_:))),
                                          ("Zoom Out", #selector(zoomOutCropFromMenu(_:))), ("Show Whole Picture", #selector(resetCropFromMenu(_:)))]
        for (title, action) in rows {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: ""); row.target = self; menu.addItem(row)
        }
        menu.addItem(.separator())
        for (title, action) in [("Done", #selector(saveCropFromMenu(_:))), ("Cancel", #selector(cancelCropFromMenu(_:)))] {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: ""); row.target = self; menu.addItem(row)
        }
        return menu
    }

    func validateImageMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(playVideoFromMenu(_:)):
            guard let command = command(for: menuItem), command.ids == selection else { return false }
            return selectedMedia?.kind == .video
        case #selector(editAltTextFromMenu(_:)):
            guard let command = command(for: menuItem), command.ids == selection, imageEditing.crop == nil else { return false }
            return selectedMedia.map { $0.kind == .video ? !$0.isLocked && hasImageChrome : canEditSelectedImage && hasImageChrome } ?? false
        case #selector(cropImageFromMenu(_:)), #selector(maskImageFromMenu(_:)), #selector(replaceImageFromMenu(_:)):
            guard let command = command(for: menuItem), command.ids == selection, imageEditing.crop == nil else { return false }
            return canEditSelectedImage
        case #selector(cropAspectFromMenu(_:)):
            return imageEditing.crop.map { $0.draft.mask?.isSquare != true || menuItem.tag == NoteImageCropAspect.allCases.firstIndex(of: .square) } ?? false
        case #selector(cropCircleFromMenu(_:)), #selector(rotateCropFromMenu(_:)), #selector(zoomInCropFromMenu(_:)), #selector(zoomOutCropFromMenu(_:)),
             #selector(resetCropFromMenu(_:)), #selector(saveCropFromMenu(_:)), #selector(cancelCropFromMenu(_:)):
            return imageEditing.crop != nil
        default:
            return nil
        }
    }

    private func menuImage(_ sender: Any?) -> EaselItem? {
        guard let command = command(for: sender), command.ids == selection, imageEditing.crop == nil, canEditSelectedImage else { return nil }
        return selectedImage
    }

    @objc private func cropImageFromMenu(_ sender: Any?) { if menuImage(sender) != nil { beginImageCrop() } }
    @objc private func editAltTextFromMenu(_ sender: Any?) {
        guard let command = command(for: sender), command.ids == selection, imageEditing.crop == nil, let item = selectedMedia else { return }
        editImageAltText(for: item)
    }
    @objc private func playVideoFromMenu(_ sender: Any?) {
        guard let command = command(for: sender), command.ids == selection, let video = selectedMedia, video.kind == .video else { return }
        if isPlayingVideo(video.id) { pauseVideo() } else { playVideo(video.id) }
    }
    @objc private func replaceImageFromMenu(_ sender: Any?) { if menuImage(sender) != nil { chooseReplacementImage() } }
    @objc private func maskImageFromMenu(_ sender: Any?) {
        guard menuImage(sender) != nil, let row = sender as? NSMenuItem else { return }
        let options: [EaselImageMask?] = [nil] + EaselImageMask.allCases.map(Optional.some)
        guard options.indices.contains(row.tag) else { return }
        setImageMask(options[row.tag])
    }
    @objc private func cropAspectFromMenu(_ sender: Any?) {
        guard let row = sender as? NSMenuItem, NoteImageCropAspect.allCases.indices.contains(row.tag) else { return }
        let option = NoteImageCropAspect.allCases[row.tag]
        if imageEditing.crop?.draft.mask == .circle { setCropMask(nil) }
        setCropAspect(option)
    }
    @objc private func cropCircleFromMenu(_ sender: Any?) { setCropMask(.circle) }
    @objc private func rotateCropFromMenu(_ sender: Any?) { rotateImageCrop() }
    @objc private func zoomInCropFromMenu(_ sender: Any?) { zoomImageCrop(by: 1.25) }
    @objc private func zoomOutCropFromMenu(_ sender: Any?) { zoomImageCrop(by: 0.8) }
    @objc private func resetCropFromMenu(_ sender: Any?) { resetImageCrop() }
    @objc private func saveCropFromMenu(_ sender: Any?) { finishImageCrop(save: true) }
    @objc private func cancelCropFromMenu(_ sender: Any?) { finishImageCrop(save: false) }

    func mediaMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target == .object, context.items.count == 1, let item = context.items.first, !item.isLocked,
              imageEditing.crop == nil else { return [] }
        if item.isEmptyPlaceholder || item.kind == .audio || item.kind == .file || item.kind == .pdf {
            return mediaActionRows(item, separated: false)
        }
        if item.kind == .video {
            let playing = isPlayingVideo(item.id)
            return [
                EaselMenuRow(id: "video-play", title: playing ? "Pause Video" : "Play Video", symbol: playing ? "pause.fill" : "play.fill",
                             shortcut: "↩", perform: guardedMenuAction { canvas in
                    if playing { canvas.pauseVideo() } else { canvas.playVideo(item.id) }
                }),
                EaselMenuRow(id: "video-alt", title: "Alt Text…", symbol: "text.bubble", isEnabled: hasImageChrome,
                             perform: guardedMenuAction { $0.editImageAltText() }),
            ] + mediaActionRows(item, separated: true)
        }
        guard item.kind == .image else { return [] }
        let options: [EaselImageMask?] = [nil] + EaselImageMask.allCases.map(Optional.some)
        let masks = options.enumerated().map { index, option in
            EaselMenuRow(id: "image-mask-" + (option?.rawValue ?? "none"), title: option?.title ?? NoteImageMask.noneTitle,
                         isChecked: item.mask == option, separatorBefore: index == 1, perform: guardedMenuAction { $0.setImageMask(option) })
        }
        return [
            EaselMenuRow(id: "image-crop", title: "Crop Image", symbol: "crop", shortcut: "↩", isEnabled: canEditSelectedImage,
                         perform: guardedMenuAction { _ = $0.beginImageCrop() }),
            EaselMenuRow(id: "image-mask", title: "Mask", symbol: "square.on.circle", children: masks),
            EaselMenuRow(id: "image-alt", title: "Alt Text…", symbol: "text.bubble", isEnabled: hasImageChrome,
                         perform: guardedMenuAction { $0.editImageAltText() }),
        ] + (canPerformHostedAction(.replace, on: item) ? [] : [
            EaselMenuRow(id: "image-replace", title: "Replace Image…", symbol: "photo.on.rectangle",
                         perform: guardedMenuAction { $0.chooseReplacementImage() }),
        ]) + mediaActionRows(item, separated: true)
    }

    func modeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]? {
        guard let crop = imageEditing.crop else { return nil }
        let draft = crop.draft
        let squareOnly = draft.mask?.isSquare == true && draft.mask != .circle
        var ratios = NoteImageCropAspect.allCases.map { option in
            EaselMenuRow(id: "crop-aspect-" + option.id, title: option.title, isEnabled: !squareOnly || option == .square,
                         isChecked: draft.aspect == option && draft.mask != .circle, perform: guardedMenuAction { canvas in
                if canvas.imageCropDraft?.mask == .circle { canvas.setCropMask(nil) }
                canvas.setCropAspect(option)
            })
        }
        ratios.append(EaselMenuRow(id: "crop-aspect-circle", title: "Circle", isChecked: draft.mask == .circle, separatorBefore: true,
                                   perform: guardedMenuAction { $0.setCropMask(.circle) }))
        let options: [EaselImageMask?] = [nil] + EaselImageMask.allCases.map(Optional.some)
        let masks = options.enumerated().map { index, option in
            EaselMenuRow(id: "crop-mask-" + (option?.rawValue ?? "none"), title: option?.title ?? NoteImageMask.noneTitle,
                         isChecked: draft.mask == option, separatorBefore: index == 1, perform: guardedMenuAction { $0.setCropMask(option) })
        }
        return [
            EaselMenuRow(id: "crop-aspect", title: "Aspect Ratio", symbol: "aspectratio", children: ratios),
            EaselMenuRow(id: "crop-mask", title: "Mask", symbol: "square.on.circle", children: masks),
            EaselMenuRow(id: "crop-rotate", title: "Rotate 90°", symbol: "rotate.right", perform: guardedMenuAction { $0.rotateImageCrop() }),
            EaselMenuRow(id: "crop-zoom-in", title: "Zoom In", symbol: "plus.magnifyingglass", shortcut: "=",
                         isEnabled: draft.zoom < draft.zoomLimit - 0.001, perform: guardedMenuAction { $0.zoomImageCrop(by: 1.25) }),
            EaselMenuRow(id: "crop-zoom-out", title: "Zoom Out", symbol: "minus.magnifyingglass", shortcut: "-",
                         isEnabled: draft.zoom > 1.001, perform: guardedMenuAction { $0.zoomImageCrop(by: 0.8) }),
            EaselMenuRow(id: "crop-reset", title: "Show Whole Picture", symbol: "arrow.counterclockwise", perform: guardedMenuAction { $0.resetImageCrop() }),
            EaselMenuRow(id: "crop-save", title: "Save", symbol: "checkmark", shortcut: "↩", separatorBefore: true,
                         perform: guardedMenuAction { $0.finishImageCrop(save: true) }),
            EaselMenuRow(id: "crop-cancel", title: "Cancel", symbol: "xmark", shortcut: "⎋", perform: guardedMenuAction { $0.finishImageCrop(save: false) }),
        ]
    }

    func imageAccessibilityActions(for item: EaselItem, owner: NSWindow) -> [NSAccessibilityCustomAction] {
        guard item.kind.isMedia, !item.isLocked else { return [] }
        var actions: [(String, (EaselCanvasView) -> Bool)]
        if item.isEmptyPlaceholder || item.kind == .audio || item.kind == .file || item.kind == .pdf {
            actions = []
        } else if item.kind == .video {
            actions = [
                ("Play video", { $0.playVideo(item.id) }),
                ("Pause video", { canvas in
                    guard canvas.isPlayingVideo(item.id) else { return false }
                    canvas.pauseVideo()
                    return true
                }),
                ("Edit alt text", { canvas in canvas.selection = [item.id]; canvas.editImageAltText(); return canvas.hasImageChrome }),
            ]
        } else if imageEditing.crop?.item.id == item.id {
            actions = [
                ("Move picture left", { $0.panImageCrop(dx: -10, dy: 0); return true }),
                ("Move picture right", { $0.panImageCrop(dx: 10, dy: 0); return true }),
                ("Move picture up", { $0.panImageCrop(dx: 0, dy: -10); return true }),
                ("Move picture down", { $0.panImageCrop(dx: 0, dy: 10); return true }),
                ("Zoom in", { $0.zoomImageCrop(by: 1.25); return true }), ("Zoom out", { $0.zoomImageCrop(by: 0.8); return true }),
                ("Rotate 90 degrees", { $0.rotateImageCrop(); return true }), ("Show whole picture", { $0.resetImageCrop(); return true }),
                ("Done cropping", { $0.finishImageCrop(save: true); return true }), ("Cancel cropping", { $0.finishImageCrop(save: false); return true }),
            ]
        } else {
            actions = [
                ("Crop image", { canvas in canvas.selection = [item.id]; return canvas.beginImageCrop() }),
                ("Edit alt text", { canvas in canvas.selection = [item.id]; canvas.editImageAltText(); return canvas.imageEditing.chrome != nil }),
                ("Replace image", { canvas in canvas.selection = [item.id]; canvas.chooseReplacementImage(); return true }),
            ]
        }
        if imageEditing.crop?.item.id != item.id {
            for action in mediaActions(for: item) where action.action != .replace || item.kind != .image {
                actions.append((action.title.replacingOccurrences(of: "…", with: ""), { canvas in
                    canvas.selection = [item.id]
                    return canvas.performHostedAction(action.action, on: item.id)
                }))
            }
        }
        return actions.map { name, perform in
            NSAccessibilityCustomAction(name: name) { [weak self, weak owner] in
                guard let self, let owner, self.window === owner, self.session.document.items.contains(where: { $0.id == item.id }) else { return false }
                return perform(self)
            }
        }
    }
}
