import AppKit
import QuartzCore
@testable import ParcSidebar

@MainActor
enum FavoriteTileSelectionTestsSupport {
    final class ActivityWindow: NSWindow {
        var key = true
        var main = true
        override var isKeyWindow: Bool { key }
        override var isMainWindow: Bool { main }
    }

    static func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    static func alpha(_ color: CGColor?) -> CGFloat? { color.map(\.alpha) }

    @MainActor final class Lit {
        let browser = ActivityWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 120),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        let other = ActivityWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 120),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        let tile = FavoriteTile(title: "Highlighted Favorite", monogram: "H", url: "https://example.test")
        let badgeImage = NSImage(size: NSSize(width: 16, height: 16))
        let maxContrast = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        var overlays: FavoriteTileOverlays { tile.overlays }

        init(attached: Bool = true, reduceMotion: Bool = false) {
            tile.reducesMotion = { reduceMotion }
            tile.overlays.reducesMotion = { reduceMotion }
            browser.isReleasedWhenClosed = false
            other.isReleasedWhenClosed = false
            tile.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
            tile.applyPalette(isDark: false, glyphColor: .black, highlightColor: maxContrast)
            tile.selected = true
            if attached {
                browser.contentView!.addSubview(tile)
                browser.contentView!.layoutSubtreeIfNeeded()
            }
        }

        deinit {
            MainActor.assumeIsolated {
                browser.close()
                other.close()
            }
        }

        func loseKey() {
            browser.key = false
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: browser)
        }

        func loseMain() {
            browser.main = false
            NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: browser)
        }

        func inactive() {
            loseKey()
            loseMain()
        }

        func undimmed(dark: Bool) -> Bool {
            !tile.dimmed && tile.shadowLayer.shadowOpacity == 0.1 && !tile.shadowLayer.isHidden
                && abs((tile.selectionFill.backgroundColor?.alpha ?? -1) - (dark ? 0.45 : 0.8)) < 0.0001
                && tile.washLayer.opacity == (dark ? 0.2 : 0) && !tile.outlineImage.isHidden
                && tile.outlineLayer.backgroundColor == nil
        }

        func dimmedStyle(dark: Bool) -> Bool {
            tile.dimmed && tile.shadowLayer.shadowOpacity == 0 && !tile.selectionFill.isHidden
                && abs((tile.selectionFill.backgroundColor?.alpha ?? -1) - (dark ? 0.225 : 0.4)) < 0.0001
                && tile.washLayer.opacity == 0 && tile.outlineImage.isHidden && !tile.outlineLayer.isHidden
                && abs((tile.outlineLayer.backgroundColor?.alpha ?? -1) - 0.2) < 0.0001
        }
    }

    static func ring(of lit: Lit) -> FavoriteHighlightRingView? {
        lit.tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: lit.badgeImage)))
        lit.tile.setKeyboardHighlighted(true)
        lit.browser.contentView!.layoutSubtreeIfNeeded()
        return lit.overlays.ringView
    }
}
