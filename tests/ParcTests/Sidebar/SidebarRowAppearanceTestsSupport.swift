import AppKit
@testable import ParcKit

enum SidebarRowAppearanceTestsSupport {
    final class FlippedHost: NSView {
        override var isFlipped: Bool { true }
    }

    static func rgba(_ color: NSColor, _ space: NSColorSpace = .sRGB) -> [CGFloat] {
        let c = color.usingColorSpace(space)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }

    static func state(_ bits: Int) -> SidebarRowAppearance {
        SidebarRowAppearance(current: bits & 1 != 0, contentVisible: bits & 2 != 0, multiSelected: bits & 4 != 0, hovered: bits & 8 != 0)
    }

    static func child(_ width: CGFloat, recording: Bool = false, hovered: Bool = false, close: Bool = true) -> SidebarRowAppearance.SplitChildLayout {
        SidebarRowAppearance.splitChildLayout(in: NSRect(x: 0, y: 0, width: width, height: 35), titleHeight: 17,
                                              recording: recording, closeAvailable: close, groupHovered: hovered)
    }

    @MainActor final class Background {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        let view = SidebarRowBackgroundView(frame: NSRect(x: 8, y: 10, width: 212, height: 35))
        var layer: CALayer { view.fillLayer }
        var ring: CALayer { view.ringLayer }

        init() {
            window.isReleasedWhenClosed = false
            window.contentView!.addSubview(host)
            host.addSubview(view)
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func painted() -> Background {
            view.updateLayer()
            return self
        }
    }

    @MainActor static func highlighted() -> Background {
        let background = Background()
        background.view.ringColor = .black
        background.view.appearanceState = SidebarRowAppearance(current: true, highlighted: true, dimmed: true)
        background.view.updateLayer()
        return background
    }
}
