import AppKit
import ParcCore

extension EaselCanvasView {
    var acceptsTemplates: Bool { fixedCanvasSize == nil && !session.isClosed && !session.isDeleted }

    @discardableResult
    func insertTemplate(_ template: EaselTemplate) -> Bool {
        guard acceptsTemplates, finishImageEditing() else { return false }
        drawing = false
        let document = session.document
        let visible = visibleRect
        let placed = EaselTemplates.placed(template, centeredAt: EaselPoint(x: visible.midX, y: visible.midY),
                                           within: EaselRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
                                           firstZIndex: (document.items.map(\.zIndex).max() ?? 0) + 1)
        let limit = EaselRect.maximumCoordinate - 1
        guard document.items.count + placed.items.count <= 10_000,
              placed.bounds.x + placed.bounds.width < limit, placed.bounds.y + placed.bounds.height < limit else {
            onError?(EaselStoreError.tooLarge)
            return false
        }
        guard withObjectMotion(.appear, { commit("Add \(template.title) template") { $0.items.append(contentsOf: placed.items) } }) else { return false }
        selection = Set(placed.items.map(\.id))
        resizeCanvas(viewport: enclosingScrollView?.contentSize ?? visible.size)
        window?.makeFirstResponder(self)
        if placed.bounds.width > visible.width || placed.bounds.height > visible.height {
            zoom(.selection)
        } else {
            scrollToVisible(NSRect(x: placed.bounds.x, y: placed.bounds.y, width: placed.bounds.width, height: placed.bounds.height))
        }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Added the \(template.title) template",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }
}
