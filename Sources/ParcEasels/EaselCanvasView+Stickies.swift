import AppKit
import ParcCore
import ParcNotes

@MainActor
final class EaselBoardState {
    var stickyLayouts: [UUID: (key: EaselStickyLayoutKey, layout: EaselTextLayout.Layout)] = [:]
    var pendingSectionClick: UUID?
    var marqueeSections = Set<UUID>()
    var titleField: EaselSectionTitleField?
    private var displayedMemo: (input: [EaselItem], output: [EaselItem])?

    func displayed(_ items: [EaselItem]) -> [EaselItem] {
        if let memo = displayedMemo, memo.input == items { return memo.output }
        let output = EaselBoardObjects.displayed(items)
        displayedMemo = (items, output)
        return output
    }
}

struct EaselStickyLayoutKey: Equatable {
    let text: String
    let rich: EaselRichText?
    let style: EaselTextStyle?
    let color: String
    let width: Double
    let adapts: Bool
}

@MainActor
final class EaselPaperCache {
    struct Key: Hashable {
        let width: Int, height: Int, color: UInt32, scale: Int, dark: Bool, pixels: Int
    }
    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    private var pixelTotal = 0
    private let pixelBudget = 8_000_000

    func image(_ key: Key, make: () -> CGImage?) -> CGImage? {
        if let image = images[key] {
            if let index = order.firstIndex(of: key) { order.remove(at: index) }
            order.append(key)
            return image
        }
        guard let image = make() else { return nil }
        images[key] = image; order.append(key); pixelTotal += image.width * image.height
        while pixelTotal > pixelBudget, order.count > 1 {
            let oldest = order.removeFirst()
            if let gone = images.removeValue(forKey: oldest) { pixelTotal -= gone.width * gone.height }
        }
        return image
    }
}

@MainActor
enum EaselStickyArt {
    static let cache = EaselPaperCache()

    static func cornerRadius(scale: Double) -> CGFloat { CGFloat(max(1.5, 4 * scale)) }

    static func overhang(_ item: EaselItem) -> CGFloat { reach(scale: EaselBoardObjects.textScale(item)) }

    static func reach(scale: Double) -> CGFloat { CGFloat(30 * scale) + 2 }

    static func drawPaper(_ paper: NSColor?, in frame: NSRect, scale: Double, dark: Bool, cacheable: Bool) {
        guard let paper, frame.width > 0, frame.height > 0, let graphics = NSGraphicsContext.current else { return }
        let context = graphics.cgContext, ctm = context.ctm
        let device = sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c))
        let outer = frame.insetBy(dx: -reach(scale: scale), dy: -reach(scale: scale))
        let pixels = outer.width * outer.height * device * device
        if cacheable, graphics.isDrawingToScreen, device > 0, device <= 4, pixels <= 1_500_000,
           let rgb = paper.usingColorSpace(.sRGB) {
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
                .map { UInt32(max(0, min(255, ($0 * 255).rounded()))) }
            let key = EaselPaperCache.Key(width: Int((frame.width * 4).rounded()), height: Int((frame.height * 4).rounded()),
                                          color: channels[0] << 24 | channels[1] << 16 | channels[2] << 8 | channels[3],
                                          scale: Int((scale * 1000).rounded()), dark: dark, pixels: Int((device * 4).rounded()))
            let local = NSRect(x: reach(scale: scale), y: reach(scale: scale), width: frame.width, height: frame.height)
            let size = NSSize(width: outer.width, height: outer.height)
            if let image = cache.image(key, make: { render(paper, in: local, canvas: size, scale: scale, dark: dark, device: device) }) {
                context.saveGState()
                context.translateBy(x: outer.minX, y: outer.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: outer.width, height: outer.height))
                context.restoreGState()
                return
            }
        }
        drawSheet(paper, in: frame, scale: scale, dark: dark)
    }

    private static func render(_ paper: NSColor, in frame: NSRect, canvas: NSSize, scale: Double, dark: Bool, device: CGFloat) -> CGImage? {
        let width = Int((canvas.width * device).rounded(.up)), height = Int((canvas.height * device).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: device, y: -device)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawSheet(paper, in: frame, scale: scale, dark: dark)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    static func drawSheet(_ paper: NSColor, in frame: NSRect, scale: Double, dark: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let unit = CGFloat(scale), radius = cornerRadius(scale: scale)
        let sheet = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        let liftHeight = min(frame.height * 0.45, 72 * unit)
        let lift = NSBezierPath(roundedRect: NSRect(x: frame.minX + 6 * unit, y: frame.maxY - liftHeight,
                                                    width: max(1, frame.width - 12 * unit), height: liftHeight),
                                xRadius: radius, yRadius: radius)
        let caster = paper.withAlphaComponent(1)
        NSGraphicsContext.saveGraphicsState()
        let outside = NSBezierPath(rect: frame.insetBy(dx: -reach(scale: scale) - 8, dy: -reach(scale: scale) - 8))
        outside.append(sheet); outside.windingRule = .evenOdd; outside.addClip()
        context.saveGState()
        shadow(context, drop: 6 * unit, blur: 12 * unit, alpha: dark ? 0.55 : 0.2)
        caster.setFill(); lift.fill()
        context.restoreGState()
        context.saveGState()
        shadow(context, drop: unit, blur: 2.5 * unit, alpha: dark ? 0.5 : 0.18)
        caster.setFill(); sheet.fill()
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        paper.setFill(); sheet.fill()
        NSGraphicsContext.saveGraphicsState()
        sheet.addClip()
        let finish = NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(dark ? 0.05 : 0.16), 0),
                                (NSColor.white.withAlphaComponent(0), 0.35),
                                (NSColor.black.withAlphaComponent(dark ? 0.14 : 0.05), 1))
        finish?.draw(from: NSPoint(x: frame.midX, y: frame.minY), to: NSPoint(x: frame.midX, y: frame.maxY), options: [])
        NSGraphicsContext.restoreGraphicsState()
        let edge = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.06)).setStroke()
        edge.stroke()
    }

    static func shadow(_ context: CGContext, drop: CGFloat, blur: CGFloat, alpha: CGFloat) {
        let ctm = context.ctm
        let offset = CGSize(width: drop * ctm.c, height: drop * ctm.d)
        let scale = sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c))
        context.setShadow(offset: offset, blur: blur * scale, color: NSColor.black.withAlphaComponent(alpha).cgColor)
    }
}

extension EaselCanvasView {
    var nextZIndex: Int {
        let top = session.document.items.map(\.zIndex).max() ?? 0
        return top < Int.max ? top + 1 : top
    }

    func drawSticky(_ item: EaselItem, showsEditor: Bool) {
        var frame = rect(item)
        if showsEditor, paintsLiveFeedback, canvasFeedback.growths[item.id] != nil { frame.size.height = CGFloat(presentedStickyHeight(item)) }
        let dark = adaptsInk && NoteTheme.isDark(NSAppearance.currentDrawing())
        EaselStickyArt.drawPaper(EaselPaint(item, adaptive: adaptsInk).fillColor, in: frame,
                                 scale: EaselBoardObjects.textScale(item), dark: dark, cacheable: showsEditor)
        guard !(showsEditor && editingID == item.id && editor != nil), !item.text.isEmpty else { return }
        let box = EaselBoardObjects.stickyTextBox(item)
        let radius = EaselStickyArt.cornerRadius(scale: EaselBoardObjects.textScale(item))
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
        stickyLayout(item, width: box.width).draw(at: NSPoint(x: box.x, y: box.y), style: item.resolvedTextStyle)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func stickyLayout(_ item: EaselItem, width: Double) -> EaselTextLayout.Layout {
        let key = EaselStickyLayoutKey(text: item.text, rich: item.richText, style: item.textStyle, color: item.color,
                                       width: width, adapts: adaptsInk)
        if let cached = boardState.stickyLayouts[item.id], cached.key == key { return cached.layout }
        let layout = EaselStickyText.layout(EaselStickyText.presented(item, adaptive: adaptsInk), for: item, width: width)
        boardState.stickyLayouts[item.id] = (key, layout)
        if boardState.stickyLayouts.count > max(64, session.document.items.count * 2) {
            let live = Set(session.document.items.map(\.id))
            boardState.stickyLayouts = boardState.stickyLayouts.filter { live.contains($0.key) }
        }
        return layout
    }

    func boardOverhang(_ item: EaselItem) -> CGFloat {
        switch item.kind {
        case .sticky: return EaselStickyArt.overhang(item)
        case .section: return sectionOverhang(item)
        default: return 0
        }
    }

    func allowsFrameHandle(_ handle: EaselResizeHandle) -> Bool {
        guard handle == .top || handle == .bottom else { return true }
        let selected = session.document.items.filter { selection.contains($0.id) }
        return selected.isEmpty || !selected.allSatisfy { $0.kind == .sticky }
    }

    func fittedBoardGeometry(_ proposal: [EaselItem], edit: EaselGeometryEdit, handle: EaselResizeHandle?) -> [EaselItem] {
        guard let handle, edit.originals.contains(where: { $0.kind == .sticky }) else { return proposal }
        var originals: [UUID: EaselItem] = [:]
        for item in edit.originals where originals[item.id] == nil { originals[item.id] = item }
        let alone = edit.originals.count == 1
        return proposal.map { item in
            guard item.kind == .sticky, let original = originals[item.id] else { return item }
            return EaselBoardObjects.resizedSticky(original, proposed: item, handle: handle, alone: alone, textHeight: EaselStickyText.height)
        }
    }

    @discardableResult
    func insertSticky(at point: NSPoint, wide: Bool = false) -> Bool {
        insertSticky(EaselBoardObjects.sticky(centeredAt: EaselPoint(x: point.x, y: point.y), wide: wide, zIndex: nextZIndex), remembered: true)
    }

    @discardableResult
    func insertSticky(origin: NSPoint, like source: EaselItem) -> Bool {
        insertSticky(EaselBoardObjects.sticky(origin: EaselPoint(x: origin.x, y: origin.y), like: source, zIndex: nextZIndex), remembered: false)
    }

    private func insertSticky(_ proposed: EaselItem, remembered: Bool) -> Bool {
        guard !session.isClosed, !session.isDeleted else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        var item = proposed
        if remembered { stampRememberedStyle(on: &item) }
        if let size = fixedCanvasSize {
            item.frame = EaselToolGeometry.constrained(item.frame, to: EaselRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        guard withObjectMotion(.appear, { commit("Add sticky note", { $0.items.append(item) }) }) else { return false }
        selection = [item.id]; window?.makeFirstResponder(self)
        beginEditing(item)
        return true
    }

    var isStickyWide: Bool {
        let stickies = session.document.items.filter { selection.contains($0.id) && $0.kind == .sticky }
        return !stickies.isEmpty && stickies.allSatisfy(EaselBoardObjects.isWide)
    }

    @discardableResult
    func setStickyWide(_ wide: Bool) -> Bool {
        guard !session.isClosed, editor?.hasMarkedText() != true else { return false }
        cancelPointerInteraction()
        let ids = selection
        return commit(wide ? "Make sticky wide" : "Make sticky square") { document in
            for index in document.items.indices where ids.contains(document.items[index].id) {
                let item = document.items[index]
                guard item.kind == .sticky, !item.isLocked else { continue }
                document.items[index] = EaselBoardObjects.widened(item, wide: wide, textHeight: EaselStickyText.height)
            }
        }
    }
}

extension EaselCanvasView {
    func presentedStickyHeight(_ item: EaselItem) -> Double {
        guard let growth = canvasFeedback.growths[item.id] else { return item.frame.height }
        return EaselFeedbackCurve.grownValue(CACurrentMediaTime() - growth.start, from: growth.from, to: growth.to)
    }

    func noteStickyGrowth(from before: EaselDocument, to after: EaselDocument) {
        guard let id = editingID, editor != nil, canAnimateObjects, !feedbackReducesMotion,
              let old = before.items.first(where: { $0.id == id }), old.kind == .sticky,
              let new = after.items.first(where: { $0.id == id }), new.kind == .sticky,
              old.frame.width == new.frame.width, old.frame.y == new.frame.y,
              abs(old.frame.height - new.frame.height) > 0.5 else { return }
        canvasFeedback.growths[id] = .init(from: presentedStickyHeight(old), to: new.frame.height, start: CACurrentMediaTime(), result: new)
        startCanvasFeedback()
    }

    func updateStickyEditorMask() {
        guard let editor, let layer = editor.layer else { return }
        guard let id = editingID, canvasFeedback.growths[id] != nil,
              let item = session.document.items.first(where: { $0.id == id }), item.kind == .sticky else {
            if layer.mask != nil { layer.mask = nil }
            return
        }
        let paperBottom = CGFloat(item.frame.y + presentedStickyHeight(item))
        let visible = max(0, min(editor.bounds.height, paperBottom - editor.frame.minY))
        let mask = layer.mask ?? CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let top = layer.contentsAreFlipped() ? 0 : editor.bounds.height - visible
        mask.frame = CGRect(x: -editor.bounds.width, y: top, width: editor.bounds.width * 3, height: visible)
        if layer.mask !== mask { layer.mask = mask }
        CATransaction.commit()
    }
}
