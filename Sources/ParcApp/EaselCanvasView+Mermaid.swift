import AppKit

extension EaselCanvasView {
    var acceptsMermaid: Bool { fixedCanvasSize == nil && !session.isClosed && !session.isDeleted }

    func canParseMermaid(_ text: String) -> Bool { acceptsMermaid && EaselMermaid.canParse(text) }

    func mermaidText(on pasteboard: NSPasteboard) -> String? {
        guard acceptsMermaid,
              pasteboard.availableType(from: [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType,
                                              EaselStyledText.legacyPasteboardType]) == nil,
              let text = pasteboard.string(forType: .string), EaselMermaid.canParse(text) else { return nil }
        return text
    }

    @discardableResult
    func pasteMermaid(from pasteboard: NSPasteboard) -> Bool {
        guard let text = mermaidText(on: pasteboard) else { return false }
        return insertMermaid(text)
    }

    @discardableResult
    func insertMermaid(_ source: String, at point: NSPoint? = nil) -> Bool {
        guard acceptsMermaid, case .success(let diagram) = EaselMermaid.parse(source), finishImageEditing() else { return false }
        drawing = false
        let document = session.document
        let base = EaselMermaid.drawing(diagram, zIndex: (document.items.map(\.zIndex).max() ?? 0) + 1,
                                        ink: EaselInk.automatic, measure: Self.mermaidMeasure)
        guard document.items.count + base.items.count <= 10_000 else { onError?(EaselStoreError.tooLarge); return false }
        let visible = visibleRect
        let center = point ?? NSPoint(x: visible.midX, y: visible.midY)
        var x = center.x - base.width / 2, y = center.y - base.height / 2
        if point == nil {
            if base.width > visible.width - 96 { x = visible.minX + 48 }
            if base.height > visible.height - 96 { y = visible.minY + 56 }
        }
        x = max(48, x).rounded(); y = max(56, y).rounded()
        let placed = base.moved(by: x, y)
        do { try session.perform("Add Mermaid diagram") { $0.items.append(contentsOf: placed.items) } }
        catch { onError?(error); return false }
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
        guard acceptsMermaid, let window, window.attachedSheet == nil, finishImageEditing() else { return false }
        drawing = false
        return EaselMermaidSheet(canvas: self, text: mermaidText(on: .general) ?? "").begin(for: window)
    }

    @objc func insertMermaidDiagram(_ sender: Any?) { showMermaidSheet() }

    nonisolated static func mermaidMeasure(_ text: String, _ maximumWidth: Double) -> EaselMermaidSize {
        let font = EaselTextAppearance.font(EaselTextStyle())
        let sample = text.isEmpty ? " " : text
        let bounds = (sample as NSString).boundingRect(with: NSSize(width: max(1, maximumWidth), height: 1_000_000),
                                                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                       attributes: [.font: font])
        return EaselMermaidSize(width: min(maximumWidth, ceil(bounds.width)) + 20, height: ceil(bounds.height) + 8)
    }
}
