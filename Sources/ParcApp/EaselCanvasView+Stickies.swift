import AppKit

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
enum EaselStickyText {
    static func scaled(_ value: NSAttributedString, by scale: Double) -> NSAttributedString {
        resized(value, by: scale, rounding: false)
    }

    static func unscaled(_ value: NSAttributedString, by scale: Double) -> NSAttributedString {
        guard scale.isFinite, scale > 0 else { return value }
        return resized(value, by: 1 / scale, rounding: true)
    }

    private nonisolated static func resized(_ value: NSAttributedString, by factor: Double, rounding: Bool) -> NSAttributedString {
        guard factor.isFinite, factor > 0, abs(factor - 1) > 0.0005, value.length > 0 else { return value }
        let size: (Double) -> Double = { points in rounding ? (points * factor * 1000).rounded() / 1000 : points * factor }
        let result = NSMutableAttributedString(attributedString: value)
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, range, _ in
            if let font = attributes[.font] as? NSFont {
                let points = CGFloat(size(Double(font.pointSize)))
                result.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: points) ?? font, range: range)
            }
            if let kern = attributes[.kern] as? NSNumber { result.addAttribute(.kern, value: size(kern.doubleValue), range: range) }
            if let offset = attributes[.baselineOffset] as? NSNumber {
                result.addAttribute(.baselineOffset, value: size(offset.doubleValue), range: range)
            }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               let copy = paragraph.mutableCopy() as? NSMutableParagraphStyle {
                func scaled(_ value: CGFloat) -> CGFloat { CGFloat(size(Double(value))) }
                copy.headIndent = scaled(paragraph.headIndent)
                copy.firstLineHeadIndent = scaled(paragraph.firstLineHeadIndent)
                copy.tailIndent = scaled(paragraph.tailIndent)
                copy.lineSpacing = scaled(paragraph.lineSpacing)
                copy.paragraphSpacing = scaled(paragraph.paragraphSpacing)
                copy.paragraphSpacingBefore = scaled(paragraph.paragraphSpacingBefore)
                copy.minimumLineHeight = scaled(paragraph.minimumLineHeight)
                copy.maximumLineHeight = scaled(paragraph.maximumLineHeight)
                copy.defaultTabInterval = scaled(paragraph.defaultTabInterval)
                copy.tabStops = paragraph.tabStops.map {
                    NSTextTab(textAlignment: $0.alignment, location: scaled($0.location), options: $0.options)
                }
                result.addAttribute(.paragraphStyle, value: copy, range: range)
            }
        }
        return result
    }

    static func presented(_ item: EaselItem, adaptive: Bool) -> NSAttributedString {
        let value = scaled(EaselRichTextCodec.attributed(item), by: EaselBoardObjects.textScale(item))
        return adaptive ? EaselInk.adapting(value) : value
    }

    static func height(_ item: EaselItem) -> Double {
        let box = EaselBoardObjects.stickyTextBox(item)
        let value = item.text.isEmpty ? NSAttributedString() : presented(item, adaptive: false)
        return value.length == 0 ? 0 : Double(EaselTextLayout.Layout(value, width: box.width).height)
    }
}

@MainActor
enum EaselStickyArt {
    static func cornerRadius(scale: Double) -> CGFloat { CGFloat(max(1.5, 4 * scale)) }

    static func overhang(_ item: EaselItem) -> CGFloat { CGFloat(30 * EaselBoardObjects.textScale(item)) }

    static func drawPaper(_ paper: NSColor?, in frame: NSRect, scale: Double, dark: Bool) {
        guard let paper, frame.width > 0, frame.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let unit = CGFloat(scale), radius = cornerRadius(scale: scale)
        let sheet = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        let liftHeight = min(frame.height * 0.45, 72 * unit)
        let lift = NSRect(x: frame.minX + 6 * unit, y: frame.maxY - liftHeight, width: max(1, frame.width - 12 * unit), height: liftHeight)
        context.saveGState()
        shadow(context, drop: 6 * unit, blur: 12 * unit, alpha: dark ? 0.55 : 0.2)
        paper.setFill(); NSBezierPath(roundedRect: lift, xRadius: radius, yRadius: radius).fill()
        context.restoreGState()
        context.saveGState()
        shadow(context, drop: unit, blur: 2.5 * unit, alpha: dark ? 0.5 : 0.18)
        paper.setFill(); sheet.fill()
        context.restoreGState()
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
        let frame = rect(item)
        let dark = adaptsInk && NoteTheme.isDark(NSAppearance.currentDrawing())
        EaselStickyArt.drawPaper(EaselPaint(item, adaptive: adaptsInk).fillColor, in: frame,
                                 scale: EaselBoardObjects.textScale(item), dark: dark)
        guard !(showsEditor && editingID == item.id && editor != nil), !item.text.isEmpty else { return }
        let box = EaselBoardObjects.stickyTextBox(item)
        stickyLayout(item, width: box.width).draw(at: NSPoint(x: box.x, y: box.y), style: item.resolvedTextStyle)
    }

    private func stickyLayout(_ item: EaselItem, width: Double) -> EaselTextLayout.Layout {
        let key = EaselStickyLayoutKey(text: item.text, rich: item.richText, style: item.textStyle, color: item.color,
                                       width: width, adapts: adaptsInk)
        if let cached = boardState.stickyLayouts[item.id], cached.key == key { return cached.layout }
        let layout = EaselTextLayout.Layout(EaselStickyText.presented(item, adaptive: adaptsInk), width: CGFloat(width))
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
        insertSticky(EaselBoardObjects.sticky(centeredAt: EaselPoint(x: point.x, y: point.y), wide: wide, zIndex: nextZIndex))
    }

    @discardableResult
    func insertSticky(origin: NSPoint, like source: EaselItem) -> Bool {
        insertSticky(EaselBoardObjects.sticky(origin: EaselPoint(x: origin.x, y: origin.y), like: source, zIndex: nextZIndex))
    }

    private func insertSticky(_ proposed: EaselItem) -> Bool {
        guard !session.isClosed, !session.isDeleted else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        var item = proposed
        if let size = fixedCanvasSize {
            item.frame = EaselToolGeometry.constrained(item.frame, to: EaselRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        guard commit("Add sticky note", { $0.items.append(item) }) else { return false }
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
