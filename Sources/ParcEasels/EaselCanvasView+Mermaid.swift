import AppKit
import ParcCore

@MainActor
package protocol EaselMermaidSheetPresenting: AnyObject {
    func begin(for window: NSWindow) -> Bool
}

extension EaselCanvasView {
    package static var mermaidSheetFactory: (@MainActor (EaselCanvasView, String) -> EaselMermaidSheetPresenting)?

    var acceptsMermaid: Bool { fixedCanvasSize == nil && !session.isClosed && !session.isDeleted }

    func canParseMermaid(_ text: String) -> Bool { acceptsMermaid && EaselMermaid.canParse(text) }

    func mermaidDiagram(on pasteboard: NSPasteboard) -> Result<EaselMermaidDiagram, EaselMermaidRefusal>? {
        guard acceptsMermaid,
              pasteboard.availableType(from: [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType,
                                              EaselStyledText.legacyPasteboardType]) == nil,
              let text = pasteboard.string(forType: .string) else { return nil }
        switch EaselMermaid.parse(text) {
        case .success(let diagram): return .success(diagram)
        case .failure(.tooLarge): return .failure(.tooLarge)
        case .failure: return nil
        }
    }

    func mermaidText(on pasteboard: NSPasteboard) -> String? {
        guard case .success? = mermaidDiagram(on: pasteboard) else { return nil }
        return pasteboard.string(forType: .string)
    }

    @discardableResult
    func pasteMermaid(from pasteboard: NSPasteboard, at point: NSPoint? = nil) -> Bool {
        switch mermaidDiagram(on: pasteboard) {
        case .success(let diagram)?: insertMermaid(diagram, at: point)
        case .failure(let refusal)?: onError?(refusal)
        case nil: return false
        }
        return true
    }

    @discardableResult
    func insertMermaid(_ source: String, at point: NSPoint? = nil) -> Bool {
        guard acceptsMermaid, case .success(let diagram) = EaselMermaid.parse(source) else { return false }
        return insertMermaid(diagram, at: point)
    }

    @discardableResult
    func insertMermaid(_ diagram: EaselMermaidDiagram, at point: NSPoint? = nil) -> Bool {
        guard acceptsMermaid, finishImageEditing() else { return false }
        drawing = false
        let document = session.document
        let base = EaselMermaid.drawing(diagram, zIndex: (document.items.map(\.zIndex).max() ?? 0) + 1,
                                        ink: EaselInk.automatic, measure: Self.mermaidMeasure)
        let visible = visibleRect
        let center = point ?? NSPoint(x: visible.midX, y: visible.midY)
        var x = center.x - base.width / 2, y = center.y - base.height / 2
        if point == nil {
            if base.width > visible.width - 96 { x = visible.minX + 48 }
            if base.height > visible.height - 96 { y = visible.minY + 56 }
        }
        x = max(48, x).rounded(); y = max(56, y).rounded()
        let limit = EaselRect.maximumCoordinate - 1
        guard document.items.count + base.items.count <= 10_000, x.isFinite, y.isFinite,
              x + base.width < limit, y + base.height < limit else {
            onError?(EaselMermaidRefusal.tooLarge)
            return false
        }
        let placed = Self.emphasizingHeadings(base.moved(by: x, y))
        do { try recordingMotion(.appear) { try session.perform("Add Mermaid diagram") { $0.items.append(contentsOf: placed.items) } } }
        catch { onError?(error); return false }
        revealConnectors(placed.items.map(\.id))
        selection = Set(placed.items.map(\.id))
        resizeCanvas(viewport: enclosingScrollView?.contentSize ?? visible.size)
        window?.makeFirstResponder(self)
        scrollToVisible(NSRect(x: x, y: y, width: min(base.width, visible.width), height: min(base.height, visible.height)))
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Added " + diagram.summary.replacingOccurrences(of: " · ", with: " with "),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }

    @discardableResult
    func showMermaidSheet() -> Bool {
        guard acceptsMermaid, let window, window.attachedSheet == nil, let factory = Self.mermaidSheetFactory,
              finishImageEditing() else { return false }
        drawing = false
        return factory(self, mermaidText(on: .general) ?? "").begin(for: window)
    }

    @objc func insertMermaidDiagram(_ sender: Any?) { showMermaidSheet() }

    static func emphasizingHeadings(_ drawing: EaselMermaidDrawing) -> EaselMermaidDrawing {
        var copy = drawing
        for index in copy.items.indices where drawing.headings.contains(copy.items[index].id) {
            let item = copy.items[index], text = item.text as NSString
            var length = text.paragraphRange(for: NSRange(location: 0, length: 0)).length
            while length > 0, let scalar = UnicodeScalar(text.character(at: length - 1)), CharacterSet.newlines.contains(scalar) { length -= 1 }
            guard length > 0 else { continue }
            let style = item.resolvedTextStyle
            let attributed = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed(item.text, style: style, color: item.color))
            attributed.addAttribute(.font, value: NSFontManager.shared.convert(EaselTextAppearance.font(style), toHaveTrait: .boldFontMask),
                                    range: NSRange(location: 0, length: length))
            if let rich = try? EaselRichTextCodec.snapshot(attributed) { copy.items[index].richText = rich }
        }
        return copy
    }

    nonisolated static func mermaidMeasure(_ text: String, _ maximumWidth: Double) -> EaselMermaidSize {
        let font = EaselTextAppearance.font(EaselTextStyle())
        let sample = text.isEmpty ? " " : text
        let bounds = (sample as NSString).boundingRect(with: NSSize(width: max(1, maximumWidth), height: 1_000_000),
                                                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                       attributes: [.font: font])
        return EaselMermaidSize(width: min(maximumWidth, ceil(bounds.width)) + 20, height: ceil(bounds.height) + 8)
    }
}
