import AppKit
import ParcCore
import ParcKit

@MainActor
package final class NoteImageMaskPicker: NSView, NoteFloatingPanelContent {
    package var preferredSizeDidChange: (() -> Void)?
    package var onPick: ((NoteImageMask?) -> Void)?
    private let title: NSTextField
    private let plate = CALayer()
    private var tiles: [NoteImageMaskTile] = []
    private var highlighted: Int?
    static let columns = 3
    static let tileSide: CGFloat = 64
    static let gap: CGFloat = 4
    static let padding: CGFloat = 10
    static let header: CGFloat = 24

    package init(image: CGImage?, crop: NoteImageCrop, current: NoteImageMask?) {
        title = NoteMediaStyle.label("Shape", font: NoteTheme.chromeFont(12), color: NoteTheme.menuTertiaryInk)
        super.init(frame: .zero)
        wantsLayer = true
        plate.cornerRadius = NoteTheme.menuHighlightRadius
        plate.cornerCurve = .continuous
        plate.opacity = 0
        layer?.addSublayer(plate)
        addSubview(title)
        let thumbnail = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        let options: [NoteImageMask?] = [nil] + NoteImageMask.allCases.map { Optional($0) }
        for (index, mask) in options.enumerated() {
            let tile = NoteImageMaskTile(mask: mask, image: thumbnail, crop: crop)
            tile.isCurrent = mask == current
            tile.onPress = { [weak self] in self?.onPick?(mask) }
            tile.onHover = { [weak self] hovering in if hovering { self?.highlight(index, animated: true) } }
            tiles.append(tile)
            addSubview(tile)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Shapes")
        setFrameSize(intrinsicContentSize)
        highlighted = options.firstIndex { $0 == current }
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }

    package override var intrinsicContentSize: NSSize {
        let rows = CGFloat((tiles.count + Self.columns - 1) / Self.columns)
        let width = Self.padding * 2 + CGFloat(Self.columns) * Self.tileSide + CGFloat(Self.columns - 1) * Self.gap
        return NSSize(width: width, height: Self.header + Self.padding + rows * Self.tileSide + max(0, rows - 1) * Self.gap)
    }

    package override var fittingSize: NSSize { intrinsicContentSize }

    package override func layout() {
        super.layout()
        title.frame = NSRect(x: Self.padding + 2, y: 6, width: bounds.width - Self.padding * 2, height: 16)
        for (index, tile) in tiles.enumerated() {
            tile.frame = frame(ofTile: index)
        }
        if let highlighted { placePlate(at: highlighted, animated: false) }
        NoteMediaMotion.instant { plate.backgroundColor = NoteMediaStyle.cg(NoteTheme.hoverFill, in: self) }
    }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    private func frame(ofTile index: Int) -> NSRect {
        let row = index / Self.columns, column = index % Self.columns
        return NSRect(x: Self.padding + CGFloat(column) * (Self.tileSide + Self.gap), y: Self.header + CGFloat(row) * (Self.tileSide + Self.gap),
                      width: Self.tileSide, height: Self.tileSide)
    }

    private func highlight(_ index: Int, animated: Bool) {
        guard tiles.indices.contains(index) else { return }
        highlighted = index
        placePlate(at: index, animated: animated)
    }

    private func placePlate(at index: Int, animated: Bool) {
        let target = frame(ofTile: index)
        if animated, plate.opacity > 0 {
            NoteAnimation.spring(plate, "position", to: NSValue(point: CGPoint(x: target.midX, y: target.midY)), spring: .highlight)
            NoteAnimation.withoutAnimation { plate.bounds = CGRect(origin: .zero, size: target.size) }
        } else {
            NoteAnimation.withoutAnimation {
                plate.bounds = CGRect(origin: .zero, size: target.size)
                plate.position = CGPoint(x: target.midX, y: target.midY)
            }
        }
        if plate.opacity < 1 { NoteAnimation.fade(plate, to: 1, duration: animated ? 0.1 : 0) }
        NSAccessibility.post(element: tiles[index], notification: .focusedUIElementChanged)
    }

    package func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }
        let current = highlighted ?? -1
        switch event.keyCode {
        case 123: highlight(max(0, current - 1), animated: true); return true
        case 124: highlight(min(tiles.count - 1, current + 1), animated: true); return true
        case 126: highlight(current < 0 ? 0 : max(0, current - Self.columns), animated: true); return true
        case 125: highlight(current < 0 ? 0 : min(tiles.count - 1, current + Self.columns), animated: true); return true
        case 36, 76, 49:
            guard let highlighted, tiles.indices.contains(highlighted) else { return true }
            tiles[highlighted].onPress?()
            return true
        default: return false
        }
    }
}

@MainActor
final class NoteImageMaskTile: NoteMediaControl {
    let mask: NoteImageMask?
    var onHover: ((Bool) -> Void)?
    var isCurrent = false { didSet { setAccessibilityValue(isCurrent ? "selected" : nil); needsDisplay = true } }
    private let image: NSImage?
    private let crop: NoteImageCrop

    init(mask: NoteImageMask?, image: NSImage?, crop: NoteImageCrop) {
        self.mask = mask
        self.image = image
        self.crop = crop
        super.init(frame: NSRect(x: 0, y: 0, width: NoteImageMaskPicker.tileSide, height: NoteImageMaskPicker.tileSide))
        setAccessibilityLabel(mask?.title ?? NoteImageMask.noneTitle)
        parcTooltip = TooltipConfiguration(mask?.title ?? NoteImageMask.noneTitle, anchor: .bottom)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hoverDidChange() { onHover?(isHovered) }

    override func pressDidChange() {
        guard let layer else { return }
        NoteMediaMotion.press(layer, pressed: isPressed, in: self)
    }

    override func refresh() { needsDisplay = true }

    private func shape(in rect: NSRect) -> CGPath {
        if let mask { return mask.path(in: rect) }
        return CGPath(roundedRect: rect, cornerWidth: NoteMediaStyle.imageRadius, cornerHeight: NoteMediaStyle.imageRadius, transform: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let box = bounds.insetBy(dx: 10, dy: 10)
        let path = shape(in: box)
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let image {
            let size = image.size
            let region = NSRect(x: CGFloat(crop.x) * size.width, y: (1 - CGFloat(crop.y + crop.height)) * size.height,
                                width: CGFloat(crop.width) * size.width, height: CGFloat(crop.height) * size.height)
            let side = min(region.width, region.height)
            let square = NSRect(x: region.midX - side / 2, y: region.midY - side / 2, width: side, height: side)
            image.draw(in: box, from: square, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        } else {
            NoteTheme.menuTertiaryInk.withAlphaComponent(0.35).setFill()
            box.fill()
        }
        context.restoreGState()
        if isCurrent {
            context.saveGState()
            context.addPath(shape(in: box.insetBy(dx: -3.5, dy: -3.5)))
            context.setStrokeColor(NoteMediaStyle.cg(NoteTheme.accent, in: self))
            context.setLineWidth(2)
            context.strokePath()
            context.restoreGState()
        } else {
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(NoteMediaStyle.cg(NoteTheme.menuHairline, in: self))
            context.setLineWidth(1)
            context.strokePath()
            context.restoreGState()
        }
    }
}
