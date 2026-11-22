import CoreGraphics
import Foundation
import ParcCore

@MainActor
enum OnboardingWindowFrameLayout {
    static let copySize = NSSize(width: 560, height: 380)
    static let shudderValues: [CGFloat] = [0, 3.2, -2.8, 2, -1.4, 0.7, 0]
    static let shudderKeyTimes: [NSNumber] = [0, 0.14, 0.32, 0.5, 0.68, 0.84, 1]
    static let shudderDuration: CFTimeInterval = 0.38
    static let barInset: CGFloat = 28

    static func copyFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: (bounds.midX - copySize.width / 2).rounded(), y: (bounds.midY - copySize.height / 2).rounded(),
               width: copySize.width, height: copySize.height)
    }

    static func shownThickness(_ value: CGFloat) -> CGFloat {
        let bounds = WindowFramePreferences.previewBounds
        return min(bounds.upperBound, max(bounds.lowerBound, value))
    }

    static func pageCard(in copyBounds: NSRect, thickness: CGFloat) -> NSRect {
        let inset = shownThickness(thickness)
        return copyBounds.insetBy(dx: inset, dy: inset)
    }

    static func crankFrame(in copyBounds: NSRect, side: CGFloat, flipped: Bool) -> NSRect {
        let hub = WindowFrameCrankPlacement.hub(in: copyBounds, dockedSidebarEdge: nil)
        let y = flipped ? copyBounds.maxY - (hub.y - copyBounds.minY) : hub.y
        return NSRect(x: hub.x - side / 2, y: y - side / 2, width: side, height: side)
    }

    static func placeholderBars(in card: NSSize) -> [NSRect] {
        let width = max(0, card.width - 2 * barInset)
        let top = card.height - barInset
        func bar(_ y: CGFloat, _ fraction: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: barInset, y: top - y - height, width: (width * fraction).rounded(), height: height)
        }
        return [bar(0, 0.42, 14), bar(32, 0.78, 9), bar(52, 0.66, 9), bar(72, 0.72, 9), bar(100, 0.46, 96)]
    }
}
