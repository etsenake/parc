import CoreGraphics

enum CommandBarCompactLayout {
    static let sidebarWidth: CGFloat = 450
    static let popupWidth: CGFloat = 350
    static let windowMargin: CGFloat = 8
    static let screenMargin: CGFloat = 8
    static let listInset: CGFloat = 9
    static let iconSize: CGFloat = 14
    static let inputHeight: CGFloat = 22
    static let iconX = listInset + CommandResultCell.iconX
    static let textX = listInset + CommandResultCell.titleX
    static let trailing = listInset + CommandResultCell.trailingInset
    static let headerCentre: CGFloat = 24
    static let restingCentre: CGFloat = 18
    static let sessionLift = headerCentre - restingCentre

    static func width(popup: Bool, window: CGRect, screen: CGRect) -> CGFloat {
        let preferred = popup ? popupWidth : sidebarWidth
        return max(0, min(preferred, window.width - 2 * windowMargin, screen.width - 2 * screenMargin))
    }

    static func originX(anchor: CGFloat, width: CGFloat, window: CGRect, screen: CGRect) -> CGFloat {
        let lower = max(window.minX + windowMargin, screen.minX + screenMargin)
        let upper = min(window.maxX - windowMargin, screen.maxX - screenMargin) - width
        return max(lower, min(anchor, upper))
    }

    static func originY(anchor: CGRect, height: CGFloat, lift: CGFloat, screen: CGRect) -> CGFloat {
        min(max(anchor.maxY + lift - height, screen.minY + screenMargin), screen.maxY - height - screenMargin)
    }

    static func restingFrame(anchor: CGRect, sidebar: CGFloat, screen: CGRect) -> CGRect {
        let width = min(max(180, sidebar) - 18, screen.width - 24)
        let x = min(max(anchor.minX, screen.minX + screenMargin), screen.maxX - width - screenMargin)
        return CGRect(x: x, y: originY(anchor: anchor, height: anchor.height, lift: 0, screen: screen),
                      width: width, height: anchor.height)
    }

    static func iconFrame(resting: Bool) -> CGRect {
        CGRect(x: iconX, y: (resting ? restingCentre : headerCentre) - iconSize / 2, width: iconSize, height: iconSize)
    }

    static func inputFrame(width: CGFloat, resting: Bool) -> CGRect {
        CGRect(x: textX, y: (resting ? restingCentre : headerCentre) - inputHeight / 2,
               width: max(0, width - textX - trailing), height: inputHeight)
    }
}
