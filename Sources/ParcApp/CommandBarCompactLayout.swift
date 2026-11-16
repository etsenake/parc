import CoreGraphics

enum CommandBarCompactLayout {
    static let sidebarWidth: CGFloat = 450
    static let popupWidth: CGFloat = 350
    static let windowMargin: CGFloat = 8
    static let screenMargin: CGFloat = 8
    static let listInset: CGFloat = 9
    static let iconSize: CGFloat = 14
    static let iconX = listInset + CommandResultCell.iconX
    static let textX = listInset + CommandResultCell.titleX
    static let trailing = listInset + CommandResultCell.trailingInset
    static let headerCentre: CGFloat = 24
    static let browsingIconX: CGFloat = 15
    static let browsingTextX: CGFloat = 38
    static let browsingTrailing: CGFloat = 11

    static func width(popup: Bool, window: CGRect, screen: CGRect) -> CGFloat {
        let preferred = popup ? popupWidth : sidebarWidth
        return max(0, min(preferred, window.width - 2 * windowMargin, screen.width - 2 * screenMargin))
    }

    static func originX(anchor: CGFloat, width: CGFloat, window: CGRect, screen: CGRect) -> CGFloat {
        let lower = max(window.minX + windowMargin, screen.minX + screenMargin)
        let upper = min(window.maxX - windowMargin, screen.maxX - screenMargin) - width
        return max(lower, min(anchor, upper))
    }
}
