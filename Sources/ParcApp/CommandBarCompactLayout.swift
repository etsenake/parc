import CoreGraphics
import QuartzCore

enum CommandBarCompactLayout {
    static let sidebarWidth: CGFloat = 450
    static let popupWidth: CGFloat = 350
    static let windowMargin: CGFloat = 8
    static let screenMargin: CGFloat = 8
    static let listInset: CGFloat = 9
    static let iconSize: CGFloat = 14
    static let inputHeight: CGFloat = 22
    static let textLineHeight: CGFloat = 16
    static let fieldTextInset: CGFloat = 2
    static let iconX = listInset + CommandResultCell.iconX
    static let textX = listInset + CommandResultCell.titleX
    static let trailing = listInset + CommandResultCell.trailingInset
    static let headerCentre: CGFloat = 24
    static let glideDuration: CFTimeInterval = 0.15

    static func width(popup: Bool, window: CGRect, screen: CGRect) -> CGFloat {
        let preferred = popup ? popupWidth : sidebarWidth
        return max(0, min(preferred, window.width - 2 * windowMargin, screen.width - 2 * screenMargin))
    }

    static func originX(anchor: CGFloat, width: CGFloat, window: CGRect, screen: CGRect) -> CGFloat {
        let lower = max(window.minX + windowMargin, screen.minX + screenMargin)
        let upper = min(window.maxX - windowMargin, screen.maxX - screenMargin) - width
        return max(lower, min(anchor, upper))
    }

    static func lift(anchorHeight: CGFloat) -> CGFloat { headerCentre - anchorHeight / 2 }

    static func originY(anchor: CGRect, height: CGFloat, lift: CGFloat, screen: CGRect) -> CGFloat {
        min(max(anchor.maxY + lift - height, screen.minY + screenMargin), screen.maxY - height - screenMargin)
    }

    static func restingFrame(anchor: CGRect, sidebar: CGFloat, screen: CGRect) -> CGRect {
        let width = min(max(180, sidebar) - 18, screen.width - 24)
        let x = min(max(anchor.minX, screen.minX + screenMargin), screen.maxX - width - screenMargin)
        return CGRect(x: x, y: originY(anchor: anchor, height: anchor.height, lift: 0, screen: screen),
                      width: width, height: anchor.height)
    }

    static func iconFrame(centre: CGFloat) -> CGRect {
        CGRect(x: iconX, y: centre - iconSize / 2, width: iconSize, height: iconSize)
    }

    static func inputFrame(width: CGFloat, centre: CGFloat) -> CGRect {
        CGRect(x: textX, y: centre - textLineHeight / 2, width: max(0, width - textX - trailing), height: inputHeight)
    }

    static func glideOffsets(pillIconX: CGFloat, pillTextX: CGFloat, iconX: CGFloat, inputX: CGFloat) -> (icon: CGFloat, text: CGFloat) {
        (pillIconX - iconX, pillTextX - fieldTextInset - inputX)
    }
}
