import AppKit
@testable import Parc
@testable import ParcKit

final class SidebarTestWindow: NSWindow, ApplicationActivityReporting {
    var key = true
    override var isKeyWindow: Bool { key }
    var pointer: NSPoint?
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer ?? super.mouseLocationOutsideOfEventStream }
    var applicationActive = false
    var reportsApplicationActive: Bool { applicationActive }
}

final class SidebarAreaEvent: NSEvent {
    var area: NSTrackingArea?
    override var trackingArea: NSTrackingArea? { area }
}

func sidebarDescendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(sidebarDescendants) }

@MainActor
func sidebarTestWindow(containing view: NSView, deferred: Bool = true) -> SidebarTestWindow {
    let window = SidebarTestWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: deferred)
    window.isReleasedWhenClosed = false
    window.contentView = view
    return window
}

final class SidebarLayerWrites: NSObject {
    private static let layerKeys = ["frame", "bounds", "position", "transform", "opacity", "cornerRadius", "maskedCorners", "shadowPath"]
    private static let shapeKeys = ["path", "strokeStart", "strokeEnd"]
    private var count = 0

    @MainActor static func count(byLayersOf view: NSView, during body: () -> Void) -> Int {
        let recorder = SidebarLayerWrites()
        let observed = ownedLayers(view.layer?.sublayers ?? []).map { layer in
            (layer, layerKeys + (layer is CAShapeLayer ? shapeKeys : []))
        }
        for (layer, keys) in observed { for key in keys { layer.addObserver(recorder, forKeyPath: key, options: [], context: nil) } }
        body()
        for (layer, keys) in observed { for key in keys { layer.removeObserver(recorder, forKeyPath: key) } }
        return recorder.count
    }

    private static func ownedLayers(_ layers: [CALayer]) -> [CALayer] {
        layers.filter { !($0.delegate is NSView) }.flatMap { [$0] + ownedLayers($0.sublayers ?? []) }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        count += 1
    }
}
