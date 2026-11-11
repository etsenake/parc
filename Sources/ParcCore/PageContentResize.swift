import CoreGraphics
import Foundation

enum PageContentResizeMode: Equatable {
    case intrinsic
    case throttle
    case locked
}

struct PageContentResizeReasons: OptionSet, Hashable {
    let rawValue: Int
    static let windowResize = Self(rawValue: 0x1)
    static let splitDividerResize = Self(rawValue: 0x2)
    static let splitInteractiveEditing = Self(rawValue: 0x4)
    static let sidebarResize = Self(rawValue: 0x8)

    var mode: PageContentResizeMode {
        contains(.splitInteractiveEditing) ? .locked : isEmpty ? .intrinsic : .throttle
    }
}

struct PageContentResizeHold {
    static let maxPendingFrames = 1
    static let tolerance = 1.00001

    private(set) var mode = PageContentResizeMode.intrinsic
    private(set) var pendingFrames: [CGSize] = []
    private(set) var lockedSize: CGSize?

    @discardableResult
    mutating func setMode(_ newMode: PageContentResizeMode, frameSize: CGSize) -> Bool {
        guard newMode != mode else { return false }
        mode = newMode
        lockedSize = newMode == .locked ? frameSize : nil
        return true
    }

    func frame(in bounds: CGRect) -> CGRect {
        guard let lockedSize else { return bounds }
        return CGRect(origin: bounds.origin, size: lockedSize)
    }

    mutating func didApply(frameSize: CGSize, lastReport: CGSize) {
        guard mode == .throttle, lockedSize == nil else { return }
        guard Self.differs(frameSize, pendingFrames.last ?? lastReport) else { return }
        pendingFrames.append(frameSize)
        if pendingFrames.count >= Self.maxPendingFrames { lockedSize = frameSize }
    }

    mutating func acknowledge(_ viewport: CGSize) {
        while !pendingFrames.isEmpty, Self.differs(pendingFrames.removeFirst(), viewport) {}
        lockedSize = nil
    }

    static func differs(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) > tolerance || abs(a.height - b.height) > tolerance
    }

    static func pageSize(ofViewport viewport: CGSize, page: CGSize, renderer: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return viewport }
        return CGSize(width: viewport.width + page.width - renderer.width,
                      height: viewport.height + page.height - renderer.height)
    }
}
