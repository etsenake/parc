import AppKit
import MetalKit
import Testing
import ParcCore
@testable import Parc
@testable import ParcKit

enum ThemeRendererViewTestsSupport {
    @MainActor
    final class ActivityWindow: NSWindow {
        var reportsKey = false
        var reportsMain = false
        override var isKeyWindow: Bool { reportsKey }
        override var isMainWindow: Bool { reportsMain }

        convenience init(size: NSSize = NSSize(width: 800, height: 600), appearance: NSAppearance.Name = .aqua) {
            _ = NSApplication.shared
            self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
            isReleasedWhenClosed = false
            self.appearance = NSAppearance(named: appearance)
        }
    }

    @MainActor
    private final class PendingCanvas: ThemeMetalCanvas {
        private var pending = false
        override var needsDisplay: Bool {
            get { pending }
            set { pending = newValue }
        }
    }

    @MainActor
    final class Surface {
        let window: ActivityWindow
        let root: ThemeRendererView
        nonisolated static let darkTheme = SpaceTheme.singleColor(ThemeColor(red: 0.04, green: 0.03, blue: 0.08)!)
        nonisolated static let lightTheme = SpaceTheme.singleColor(ThemeColor(red: 0.98, green: 0.97, blue: 0.99)!)

        init(size: NSSize = NSSize(width: 800, height: 600), appearance: NSAppearance.Name = .aqua, theme: SpaceTheme = Surface.darkTheme,
             tracksPendingRedraws: Bool = false) {
            window = ActivityWindow(size: size, appearance: appearance)
            let frame = NSRect(origin: .zero, size: size)
            root = tracksPendingRedraws
                ? ThemeRendererView(frame: frame, makeCanvas: { PendingCanvas(frame: $0, device: $1) })
                : ThemeRendererView(frame: frame)
            window.contentView = root
            root.theme = theme
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var materials: [NSVisualEffectView] { root.subviews.compactMap { $0 as? NSVisualEffectView } }
        var material: NSVisualEffectView { materials[0] }
        var canvases: [MTKView] { root.subviews.compactMap { $0 as? MTKView } }

        func settleCanvas() throws {
            let canvas = try #require(canvases.first)
            canvas.draw(canvas.bounds)
            canvas.needsDisplay = false
        }

        func post(_ name: Notification.Name) {
            NotificationCenter.default.post(name: name, object: window)
        }

        func noisy() {
            var theme = Surface.darkTheme
            theme.noise = 0.5
            root.theme = theme
        }
    }
}
