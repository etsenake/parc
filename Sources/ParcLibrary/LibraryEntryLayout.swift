import AppKit
import Combine
import ParcCore
import SwiftUI

package enum LibraryBadgeSource: String, CaseIterable {
    case documents, desktop, screenshots, captures, downloads
    package var title: String {
        switch self {
        case .documents: return "Documents"
        case .desktop: return "Desktop"
        case .screenshots: return "Screenshots"
        case .captures: return "Saved Captures"
        case .downloads: return "Downloads"
        }
    }
    package var isAvailable: Bool { true }
}

package enum LibraryEntryLayout {
    package static let buttonSize: CGFloat = 32
    package static let cellHeight: CGFloat = 56
    package static let collapsedCellWidth: CGFloat = 40
    static let badgeGrowth: CGFloat = 10
    static let maximumWidth: CGFloat = 1000
    static let expandedInset: CGFloat = 16
    package static let overlayOffset = CGSize(width: -4, height: -30)
    package static let collapsedCellX: CGFloat = 10
    package static let collapsedCellY: CGFloat = 30
    package static func totalHeight(count: Int) -> CGFloat { (cellHeight + 0) * CGFloat(count) + buttonSize }
    static func expandedCellWidth(containerWidth: CGFloat) -> CGFloat { min(containerWidth, maximumWidth) - expandedInset }
    package static func hostSize(badgeVisible: Bool, expanded: Bool = false, containerWidth: CGFloat = 0) -> CGSize {
        if expanded { return CGSize(width: min(containerWidth, maximumWidth), height: totalHeight(count: LibraryFlyoutItems.limit)) }
        return badgeVisible ? CGSize(width: buttonSize + badgeGrowth, height: buttonSize + badgeGrowth) : CGSize(width: buttonSize, height: buttonSize)
    }
    package static let canvasInsets = NSEdgeInsets(top: 320, left: 8, bottom: 8, right: 24)
    package static func canvasSize(containerWidth: CGFloat) -> CGSize {
        CGSize(width: max(canvasInsets.left + buttonSize + canvasInsets.right, min(containerWidth, maximumWidth)),
               height: canvasInsets.top + buttonSize + canvasInsets.bottom)
    }
}
