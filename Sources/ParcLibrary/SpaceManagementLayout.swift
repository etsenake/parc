import AppKit
import ParcCore

package enum SpaceManagementLayout {
    static let cardWidth: CGFloat = 240
    static let gap: CGFloat = 24
    package static let verticalInset: CGFloat = 48
    static let horizontalInset: CGFloat = 24
    static let addItemSide: CGFloat = 48
    static let addCircleSide: CGFloat = 30

    package static func cardFrame(index: Int, height: CGFloat) -> NSRect {
        NSRect(x: horizontalInset + CGFloat(index) * (cardWidth + gap), y: verticalInset,
               width: cardWidth, height: max(0, height - 2 * verticalInset))
    }
    static func addItemFrame(count: Int, height: CGFloat) -> NSRect {
        NSRect(x: horizontalInset + CGFloat(count) * (cardWidth + gap), y: (height - addItemSide) / 2,
               width: addItemSide, height: addItemSide)
    }
    package static func addCircleFrame(count: Int, height: CGFloat) -> NSRect {
        let item = addItemFrame(count: count, height: height)
        return item.insetBy(dx: (addItemSide - addCircleSide) / 2, dy: (addItemSide - addCircleSide) / 2)
    }
    package static func contentWidth(count: Int) -> CGFloat {
        addItemFrame(count: count, height: 0).maxX + horizontalInset
    }
    static func libraryWidth(count: Int) -> CGFloat {
        3 * (2 * horizontalInset) + CGFloat(count) * (cardWidth + gap) + addItemSide + gap
    }
    static let pageInset: CGFloat = 4

    static let controlsHeight: CGFloat = 34
    package static func sidebarFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: 0, y: 5, width: bounds.width, height: max(0, bounds.height - controlsHeight - 15))
    }
    package static func controlsFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: 0, y: max(0, bounds.height - controlsHeight - 5), width: bounds.width, height: controlsHeight)
    }
    package static let cornerRadius: CGFloat = 12
}
