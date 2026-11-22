import AppKit
import Combine
import ParcCore
import SwiftUI

enum LibraryBadgeSource: String, CaseIterable {
    case documents, desktop, screenshots, captures, downloads
    var title: String {
        switch self {
        case .documents: return "Documents"
        case .desktop: return "Desktop"
        case .screenshots: return "Screenshots"
        case .captures: return "Saved Captures"
        case .downloads: return "Downloads"
        }
    }
    var isAvailable: Bool { true }
}

enum LibraryEntryLayout {
    static let buttonSize: CGFloat = 32
    static let cellHeight: CGFloat = 56
    static let collapsedCellWidth: CGFloat = 40
    static let badgeGrowth: CGFloat = 10
    static let maximumWidth: CGFloat = 1000
    static let expandedInset: CGFloat = 16
    static let overlayOffset = CGSize(width: -4, height: -30)
    static let collapsedCellX: CGFloat = 10
    static let collapsedCellY: CGFloat = 30
    static func totalHeight(count: Int) -> CGFloat { (cellHeight + 0) * CGFloat(count) + buttonSize }
    static func expandedCellWidth(containerWidth: CGFloat) -> CGFloat { min(containerWidth, maximumWidth) - expandedInset }
    static func hostSize(badgeVisible: Bool, expanded: Bool = false, containerWidth: CGFloat = 0) -> CGSize {
        if expanded { return CGSize(width: min(containerWidth, maximumWidth), height: totalHeight(count: LibraryFlyoutItems.limit)) }
        return badgeVisible ? CGSize(width: buttonSize + badgeGrowth, height: buttonSize + badgeGrowth) : CGSize(width: buttonSize, height: buttonSize)
    }
    static let canvasInsets = NSEdgeInsets(top: 320, left: 8, bottom: 8, right: 24)
    static func canvasSize(containerWidth: CGFloat) -> CGSize {
        CGSize(width: max(canvasInsets.left + buttonSize + canvasInsets.right, min(containerWidth, maximumWidth)),
               height: canvasInsets.top + buttonSize + canvasInsets.bottom)
    }
}
