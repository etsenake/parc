import Foundation

extension EaselVectorExport {
    static let strokeAllowance = 4.0

    static func exportFrame(_ item: EaselItem, art: EaselVectorArt = .init()) -> EaselRect {
        let painted = paintedFrame(item)
        let width = EaselPaintRules.strokeWidth(item)
        guard item.kind == .arrow else { return outset(painted, by: max(0, width / 2 - strokeAllowance)) }
        var reach = outset(painted, by: max(0, EaselPaintRules.arrowHeadLength(width: width) + width / 2 - strokeAllowance))
        guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return reach }
        if let label = art.connectorLabels[item.id], let route = art.connectorRoutes[item.id] ?? EaselConnectorRouter.storedRoute(item),
           let rect = EaselConnectorDrawing(route: route, item: item, labelSize: (width: label.width, height: label.height)).label {
            reach = union(reach, rect)
        } else {
            let spread = EaselConnectorLabel.maximumWidth / 2 + EaselConnectorLabel.paddingX
            let f = item.frame
            reach = union(reach, EaselRect(x: f.x - spread, y: f.y - spread / 4, width: f.width + 2 * spread, height: f.height + spread / 2))
        }
        return reach
    }

    static func outset(_ r: EaselRect, by amount: Double) -> EaselRect {
        guard amount > 0, amount.isFinite else { return r }
        return EaselRect(x: r.x - amount, y: r.y - amount, width: r.width + 2 * amount, height: r.height + 2 * amount)
    }

    static func union(_ a: EaselRect, _ b: EaselRect) -> EaselRect {
        let minX = min(a.x, b.x), minY = min(a.y, b.y)
        return EaselRect(x: minX, y: minY, width: max(a.x + a.width, b.x + b.width) - minX, height: max(a.y + a.height, b.y + b.height) - minY)
    }
}

enum EaselPreviewRegion {
    static let margin = 40.0

    static func content(_ items: [EaselItem]) -> EaselRect? {
        let shown = EaselBoardObjects.displayed(items)
        guard !shown.isEmpty else { return nil }
        return EaselVectorExport.contentBounds(shown, margin: margin)
    }

    static func fit(_ content: EaselRect, aspect: Double, minimumWidth: Double) -> EaselRect {
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
        let width = max(content.width, content.height / ratio, minimumWidth)
        let x = max(0, content.x + content.width / 2 - width / 2)
        let y = max(0, content.y + content.height / 2 - width * ratio / 2)
        return EaselRect(x: x, y: y, width: width, height: width * ratio)
    }

    static func crop(_ content: EaselRect) -> EaselRect {
        let x = max(0, content.x), y = max(0, content.y)
        return EaselRect(x: x, y: y, width: max(1, content.x + content.width - x), height: max(1, content.y + content.height - y))
    }
}
