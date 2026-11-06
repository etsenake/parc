import CoreGraphics
import Foundation

///
/// window content item's web view follows its layout size.
enum PageContentResizeMode: Equatable {
    /// Every layout size goes to the page at once.
    case intrinsic
    /// Renderer-paced: after a new size the page holds until the renderer
    /// reports a frame.
    case throttle
    /// The page keeps the size it had when the lock began.
    case locked
}

///
///
struct PageContentResizeReasons: OptionSet, Hashable {
    let rawValue: Int
    ///
    ///
    ///
    /// will-start/did-end live-resize NSWindow notifications.
    static let windowResize = Self(rawValue: 0x1)
    ///
    static let splitDividerResize = Self(rawValue: 0x2)
    ///
    static let splitInteractiveEditing = Self(rawValue: 0x4)
    /// WindowLayoutController.isSidebarResizing, the sidebar-width drag
    ///
    static let sidebarResize = Self(rawValue: 0x8)

    /// Every flag mutator: locked for 0x4, throttle for any other reason.
    var mode: PageContentResizeMode {
        contains(.splitInteractiveEditing) ? .locked : isEmpty ? .intrinsic : .throttle
    }
}

///
/// pendingResizeFrames, lockedContentSize and the mode that drives them. Sizes
/// are the page view's own, in points.
struct PageContentResizeHold {
    ///
    ///
    /// holds after every size the renderer has not drawn yet.
    static let maxPendingFrames = 1
    ///
    /// the report match.
    static let tolerance = 1.00001

    private(set) var mode = PageContentResizeMode.intrinsic
    private(set) var pendingFrames: [CGSize] = []
    private(set) var lockedSize: CGSize?

    ///
    /// entering locked holds `frameSize`. Pending frames stay until a renderer
    /// report removes them. Returns whether the content needs layout.
    @discardableResult
    mutating func setMode(_ newMode: PageContentResizeMode, frameSize: CGSize) -> Bool {
        guard newMode != mode else { return false }
        mode = newMode
        lockedSize = newMode == .locked ? frameSize : nil
        return true
    }

    ///
    ///
    /// top-leading corner (the content view is flipped).
    func frame(in bounds: CGRect) -> CGRect {
        guard let lockedSize else { return bounds }
        return CGRect(origin: bounds.origin, size: lockedSize)
    }

    /// viewWillLayout's bookkeeping after the frame is applied
    ///
    /// differs from the last pending one (or, with none pending, from the
    /// renderer's latest report) is queued, and a full queue holds it.
    mutating func didApply(frameSize: CGSize, lastReport: CGSize) {
        guard mode == .throttle, lockedSize == nil else { return }
        guard Self.differs(frameSize, pendingFrames.last ?? lastReport) else { return }
        pendingFrames.append(frameSize)
        if pendingFrames.count >= Self.maxPendingFrames { lockedSize = frameSize }
    }

    ///
    /// to and including the first that matches `viewport`, or all of them, and
    /// always releases the hold.
    mutating func acknowledge(_ viewport: CGSize) {
        while !pendingFrames.isEmpty, Self.differs(pendingFrames.removeFirst(), viewport) {}
        lockedSize = nil
    }

    static func differs(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) > tolerance || abs(a.height - b.height) > tolerance
    }

    /// A renderer viewport in the page view's own size. Parc's page view also
    /// holds chrome beside its renderer (docked DevTools, the infobar shelf),
    /// whose extent, the page view's size less the renderer view's, is added
    ///
    static func pageSize(ofViewport viewport: CGSize, page: CGSize, renderer: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return viewport }
        return CGSize(width: viewport.width + page.width - renderer.width,
                      height: viewport.height + page.height - renderer.height)
    }
}
