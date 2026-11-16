import AppKit

@main struct SidebarFaviconTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let placeholder = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
        let red = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let blue = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let view = SidebarFaviconView()
        view.image = placeholder; view.fallbackTintColor = .gray
        check(!view.allowsVibrancy, "Fallback glyphs paint the Space title color without window-appearance vibrancy")
        check(view.imageScaling == .scaleProportionallyDown, "Native image keeps aspect without enlargement")
        check(!view.isAccessibilityElement(), "Decorative favicon does not duplicate the row AX name")
        var first: ((NSImage?) -> Void)?, second: ((NSImage?) -> Void)?
        view.load { first = $0 }
        check(view.image === placeholder && view.contentTintColor == .gray, "Pending lookup retains fallback")
        view.load { second = $0 }
        second?(blue)
        check(view.image === blue && view.contentTintColor == nil, "Actual multicolor bitmap has no template tint")
        first?(red)
        check(view.image === blue, "Older profile/URL request cannot replace newer result")
        view.fallbackTintColor = .green
        check(view.contentTintColor == nil, "Theme changes do not recolor actual page artwork")
        view.load { $0(nil) }
        check(view.image === placeholder && view.contentTintColor == .green, "Deleted or missing icon restores current themed fallback")
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        parent.addSubview(view); view.frame = NSRect(x: 10, y: 10, width: 15, height: 15)
        view.load { first = $0 }; view.removeFromSuperview(); first?(red)
        check(view.image === placeholder, "Detached row rejects delayed completion")
        parent.addSubview(view); view.load { $0(blue) }
        check(view.image === blue, "Explicit new request on a reused row can succeed")
        check(view.hasSettledFavicon, "Non-nil load marks settled page art")
        let adopted = SidebarFaviconView()
        adopted.image = placeholder
        adopted.fallbackTintColor = .gray
        adopted.adoptSettled(red)
        check(adopted.hasSettledFavicon && adopted.image === red, "Adopt installs settled art without a load")
        var reloadAfterAdopt: ((NSImage?) -> Void)?
        adopted.load { reloadAfterAdopt = $0 }
        check(!adopted.hasSettledFavicon && adopted.image === placeholder,
              "reloadFavicon-style load after adopt keeps themed glyph interim, not nil")
        reloadAfterAdopt?(blue)
        check(adopted.image === blue && adopted.hasSettledFavicon, "Post-adopt load can still settle new bytes")
        var superseded: ((NSImage?) -> Void)?
        adopted.load { superseded = $0 }
        check(!adopted.hasSettledFavicon, "New load clears settled art until reply")
        adopted.image = placeholder
        adopted.adoptSettled(blue)
        superseded?(red)
        check(adopted.image === blue && adopted.hasSettledFavicon, "Adopt cancels an in-flight load generation")
        let oldFrame = view.frame
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "Production icon draws into native image slot")
        check(view.frame == oldFrame, "Favicon drawing does not move row hit targets")
        var late: ((NSImage?) -> Void)?
        weak var released: SidebarFaviconView?
        do {
            let temporary = SidebarFaviconView(); released = temporary
            temporary.image = placeholder; temporary.load { late = $0 }
        }
        check(released == nil, "Outstanding lookup never retains a removed row")
        late?(red)
        check(released == nil, "Late callback cannot revive a row")
        print("\(checks) favicon presentation assertions passed (isolated AppKit, no browser)")
    }
}
