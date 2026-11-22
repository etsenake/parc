import CoreGraphics
import Foundation

package enum PageContentResizeMode: Equatable {
    case intrinsic
    case throttle
    case locked
}

package struct PageContentResizeReasons: OptionSet, Hashable {
    package let rawValue: Int

    package init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let windowResize = Self(rawValue: 0x1)
    package static let splitDividerResize = Self(rawValue: 0x2)
    package static let splitInteractiveEditing = Self(rawValue: 0x4)
    package static let sidebarResize = Self(rawValue: 0x8)
    package static let frameAdjust = Self(rawValue: 0x10)

    package var mode: PageContentResizeMode {
        contains(.splitInteractiveEditing) ? .locked : isEmpty ? .intrinsic : .throttle
    }
}

package struct PageContentResizeHold {
    static let maxPendingFrames = 1
    package static let tolerance = 1.00001

    package private(set) var mode = PageContentResizeMode.intrinsic
    private(set) var pendingFrames: [CGSize] = []
    package private(set) var lockedSize: CGSize?

    package init(mode: PageContentResizeMode = PageContentResizeMode.intrinsic, pendingFrames: [CGSize] = [], lockedSize: CGSize? = nil) {
        self.mode = mode
        self.pendingFrames = pendingFrames
        self.lockedSize = lockedSize
    }

    @discardableResult
    package mutating func setMode(_ newMode: PageContentResizeMode, frameSize: CGSize) -> Bool {
        guard newMode != mode else { return false }
        mode = newMode
        lockedSize = newMode == .locked ? frameSize : nil
        return true
    }

    package func frame(in bounds: CGRect) -> CGRect {
        guard let lockedSize else { return bounds }
        return CGRect(origin: bounds.origin, size: lockedSize)
    }

    package mutating func didApply(frameSize: CGSize, lastReport: CGSize) {
        guard mode == .throttle, lockedSize == nil else { return }
        guard Self.differs(frameSize, pendingFrames.last ?? lastReport) else { return }
        pendingFrames.append(frameSize)
        if pendingFrames.count >= Self.maxPendingFrames { lockedSize = frameSize }
    }

    package mutating func acknowledge(_ viewport: CGSize) {
        while !pendingFrames.isEmpty, Self.differs(pendingFrames.removeFirst(), viewport) {}
        lockedSize = nil
    }

    static func differs(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) > tolerance || abs(a.height - b.height) > tolerance
    }

    package static func pageSize(ofViewport viewport: CGSize, page: CGSize, renderer: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return viewport }
        return CGSize(width: viewport.width + page.width - renderer.width,
                      height: viewport.height + page.height - renderer.height)
    }
}
