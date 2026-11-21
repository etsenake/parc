import CoreGraphics
import Foundation

extension EaselImageMask {
    var noteMask: NoteImageMask { NoteImageMask(rawValue: rawValue) ?? .rounded }
    var title: String { noteMask.title }
    var isSquare: Bool { noteMask.isSquare }
    func path(in rect: CGRect) -> CGPath { noteMask.path(in: rect) }
}

enum EaselImageFraming {
    static func turns(_ value: Int) -> Int { ((value % 4) + 4) % 4 }

    static func turnedSize(_ natural: CGSize, turns value: Int) -> CGSize {
        turns(value) % 2 == 0 ? natural : CGSize(width: natural.height, height: natural.width)
    }

    static func turnedCrop(_ crop: EaselRect?, turns value: Int) -> NoteImageCrop {
        guard let crop else { return .full }
        let x = crop.x, y = crop.y, w = crop.width, h = crop.height
        switch turns(value) {
        case 1: return NoteImageCrop(x: 1 - y - h, y: x, width: h, height: w)
        case 2: return NoteImageCrop(x: 1 - x - w, y: 1 - y - h, width: w, height: h)
        case 3: return NoteImageCrop(x: y, y: 1 - x - w, width: h, height: w)
        default: return NoteImageCrop(x: x, y: y, width: w, height: h)
        }
    }

    static func sourceCrop(_ turned: NoteImageCrop, turns value: Int) -> EaselRect? {
        let crop = turned.normalized
        guard !crop.isFull else { return nil }
        let x = crop.x, y = crop.y, w = crop.width, h = crop.height
        let source: NoteImageCrop
        switch turns(value) {
        case 1: source = NoteImageCrop(x: y, y: 1 - x - w, width: h, height: w)
        case 2: source = NoteImageCrop(x: 1 - x - w, y: 1 - y - h, width: w, height: h)
        case 3: source = NoteImageCrop(x: 1 - y - h, y: x, width: h, height: w)
        default: source = crop
        }
        let normalized = source.normalized
        return EaselRect(x: normalized.x, y: normalized.y, width: normalized.width, height: normalized.height)
    }

    static func displayAspect(natural: CGSize, crop: EaselRect?, turns value: Int) -> CGFloat? {
        let turned = turnedSize(natural, turns: value)
        let size = turnedCrop(crop, turns: value).croppedSize(of: turned)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    static func pictureRect(frame: CGRect, crop: EaselRect?, turns value: Int) -> CGRect {
        turnedCrop(crop, turns: value).fullRect(forFrame: frame)
    }

    static func sourceRect(picture: CGRect, turns value: Int) -> CGRect {
        let size = turnedSize(picture.size, turns: value)
        return CGRect(x: picture.midX - size.width / 2, y: picture.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func angle(turns value: Int) -> CGFloat { CGFloat(turns(value)) * .pi / 2 }

    static func isFramed(_ item: EaselItem) -> Bool { item.crop != nil || item.mask != nil || item.resolvedQuarterTurns != 0 }

    static func rotatedClockwise(_ rect: CGRect, around center: CGPoint) -> CGRect {
        CGRect(x: center.x - (rect.maxY - center.y), y: center.y + (rect.minX - center.x), width: rect.height, height: rect.width)
    }

    static func replacing(_ item: EaselItem, natural: CGSize) -> EaselItem {
        var next = item
        next.crop = nil; next.quarterTurns = nil
        let f = item.frame
        guard natural.width > 0, natural.height > 0, f.width > 0, f.height > 0 else { return next }
        let bounds = CGRect(origin: .zero, size: natural)
        let cover = NoteImageCropGeometry.fitted(aspect: CGFloat(f.width / f.height), around: bounds, within: bounds)
        let crop = NoteImageCrop(cover, in: bounds)
        next.crop = crop.isFull ? nil : EaselRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        return next
    }

    static func masking(_ item: EaselItem, with mask: EaselImageMask?) -> EaselItem {
        var next = item
        next.mask = mask
        guard mask?.isSquare == true else { return next }
        let f = CGRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        guard abs(f.width - f.height) > 0.5 else { return next }
        let picture = pictureRect(frame: f, crop: item.crop, turns: item.resolvedQuarterTurns)
        let side = min(f.width, f.height)
        let square = CGRect(x: f.midX - side / 2, y: f.midY - side / 2, width: side, height: side)
        next.frame = EaselRect(x: square.minX, y: square.minY, width: square.width, height: square.height)
        next.crop = sourceCrop(NoteImageCrop(square, in: picture), turns: item.resolvedQuarterTurns)
        return next
    }
}

struct EaselImageCropDraft: Equatable {
    static let minimumSide: CGFloat = 20
    static let maximumZoom: CGFloat = 8

    var frame: CGRect
    var picture: CGRect
    var turns: Int
    var mask: EaselImageMask?
    var aspect: NoteImageCropAspect
    let natural: CGSize
    let original: CGRect

    init(item: EaselItem, natural: CGSize) {
        let f = CGRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        frame = f
        original = f
        turns = item.resolvedQuarterTurns
        picture = EaselImageFraming.pictureRect(frame: f, crop: item.crop, turns: turns)
        mask = item.mask
        aspect = item.mask?.isSquare == true ? .square : .free
        self.natural = natural
    }

    var turnedNatural: CGSize { EaselImageFraming.turnedSize(natural, turns: turns) }
    var ratio: CGFloat? { aspect.ratio(natural: turnedNatural) }
    var crop: NoteImageCrop { NoteImageCrop(frame, in: picture) }
    var isWhole: Bool { crop.isFull }

    private var coverFactor: CGFloat {
        guard picture.width > 0, picture.height > 0 else { return 1 }
        return max(frame.width / picture.width, frame.height / picture.height)
    }

    var zoom: CGFloat {
        let factor = coverFactor
        return factor > 0 ? min(Self.maximumZoom, max(1, 1 / factor)) : 1
    }

    mutating func move(by delta: CGSize) {
        let x = min(max(frame.maxX - picture.width, picture.minX + delta.width), frame.minX)
        let y = min(max(frame.maxY - picture.height, picture.minY + delta.height), frame.minY)
        picture.origin = CGPoint(x: x, y: y)
    }

    mutating func moveFrame(by delta: CGSize) {
        frame = NoteImageCropGeometry.move(frame, by: delta, within: picture)
    }

    mutating func resize(_ handle: NoteImageCropHandle, from start: CGRect, by delta: CGSize, lockingAspect: Bool) {
        let lock = ratio ?? (lockingAspect && start.height > 0 ? start.width / start.height : nil)
        frame = NoteImageCropGeometry.resize(start, handle: handle, by: delta, within: picture, minimum: Self.minimumSide, aspect: lock)
    }

    mutating func setZoom(_ value: CGFloat) {
        guard value.isFinite, picture.width > 0, picture.height > 0 else { return }
        let target = min(Self.maximumZoom, max(1, value))
        let factor = coverFactor * target
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let size = CGSize(width: picture.width * factor, height: picture.height * factor)
        picture = CGRect(x: center.x + (picture.minX - center.x) * factor, y: center.y + (picture.minY - center.y) * factor,
                         width: size.width, height: size.height)
        move(by: .zero)
    }

    mutating func rotate() {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        frame = EaselImageFraming.rotatedClockwise(frame, around: center)
        picture = EaselImageFraming.rotatedClockwise(picture, around: center)
        turns = EaselImageFraming.turns(turns + 1)
        switch aspect {
        case .landscape43: aspect = .portrait34
        case .portrait34: aspect = .landscape43
        case .wide169: aspect = .tall916
        case .tall916: aspect = .wide169
        default: break
        }
    }

    mutating func setAspect(_ next: NoteImageCropAspect) {
        aspect = next
        guard let ratio else { return }
        frame = NoteImageCropGeometry.fitted(aspect: ratio, around: frame, within: picture)
    }

    mutating func setMask(_ next: EaselImageMask?) {
        let previous = mask
        mask = next
        if next?.isSquare == true {
            aspect = .square
            frame = NoteImageCropGeometry.fitted(aspect: 1, around: frame, within: picture)
        } else if previous?.isSquare == true, aspect == .square {
            aspect = .free
        }
    }

    mutating func reset() {
        setZoom(1)
        let whole = picture
        if let ratio { frame = NoteImageCropGeometry.fitted(aspect: ratio, around: whole, within: whole) } else { frame = whole }
    }

    var result: (frame: EaselRect, crop: EaselRect?, turns: Int?, mask: EaselImageMask?) {
        let rect = EaselRect(x: Double(frame.minX), y: Double(frame.minY), width: Double(frame.width), height: Double(frame.height))
        return (rect, EaselImageFraming.sourceCrop(crop, turns: turns), turns == 0 ? nil : turns, mask)
    }

    func applying(to item: EaselItem) -> EaselItem {
        var next = item
        let value = result
        next.frame = value.frame; next.crop = value.crop; next.quarterTurns = value.turns; next.mask = value.mask
        return next
    }
}
