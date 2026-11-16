import AppKit
import QuartzCore

@MainActor private final class ControlWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}
private final class SeeThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

@main
struct ExtensionControlsTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }
        func item(_ id: String, pin: Int? = nil, canPin: Bool = true,
                  execute: @escaping () -> Void = {},
                  context: @escaping (NSView) -> Void = { _ in },
                  setPinned: @escaping (Bool) -> Void = { _ in }) -> ExtensionControlItem {
            ExtensionControlItem(identifier: id, name: "Action " + id, tooltip: "Title " + id,
                accessibilityLabel: "Accessible " + id, image: nil, pinnedIndex: pin,
                canChangePin: canPin, execute: execute, showContextMenu: context, setPinned: setPinned)
        }

        var dispatches = 0
        var menus = 0
        let window = ControlWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let button = ExtensionActionButton(item: item("a", execute: { dispatches += 1 }))
        window.contentView?.addSubview(button)
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        expect(button.isEnabled, "Action controls preserve the engine's disabled-action fallback")
        expect(button.parcTooltip?.label == "Title a" && button.toolTip == nil, "Actual tooltip reaches native control as a Parc tooltip")
        expect(button.accessibilityLabel() == "Accessible a", "Native accessibility uses actual action label")
        button.performClick(nil)
        expect(dispatches == 1, "Native activation dispatches once")
        button.update(item("a", execute: { button.invalidate(); dispatches += 1 }))
        button.performClick(nil)
        expect(dispatches == 2, "Synchronous self invalidation completes the current callback")
        button.performClick(nil)
        expect(dispatches == 2, "Invalidated controls cannot dispatch a second action")

        button.update(item("a", execute: { dispatches += 1 }, context: { control in menus += control === button ? 1 : 100 }))
        expect(button.accessibilityPerformShowMenu() && menus == 1, "AX Show Menu dispatches the original native context action")
        expect(button.accessibilityPerformPress() && dispatches == 3, "AX press reaches the same original action")
        button.isHidden = true
        expect(!button.isAccessibilityEnabled() && !button.accessibilityPerformPress()
               && !button.accessibilityPerformShowMenu(), "Hidden pins neither advertise availability nor dispatch accessibility actions")
        button.performClick(nil)
        expect(dispatches == 3 && menus == 1, "Hidden native activation cannot dispatch")
        button.isHidden = false
        button.isEnabled = false
        expect(!button.accessibilityPerformPress() && !button.accessibilityPerformShowMenu(), "Invalid controls reject both AX actions")
        button.update(item("a", execute: { dispatches += 1 }))
        button.removeFromSuperview()
        expect(!button.accessibilityPerformPress() && !button.isAccessibilityEnabled(), "Detached actions cannot dispatch")
        expect(button.focusRingMaskBounds == button.bounds, "The focus mask follows the actual pin surface")
        window.contentView?.addSubview(button)
        button.appearance = NSAppearance(named: .aqua)
        button.cell!.highlight(true, withFrame: button.bounds, in: button)
        expect(abs((button.layer?.transform.m11 ?? 0) - 0.95) < 0.00001,
               "AppKit cell tracking drives the sidebar press transform")
        expect(abs((NSColor(cgColor: button.layer!.backgroundColor!)?.alphaComponent ?? 0) - 0.09) < 0.00001,
               "AppKit cell tracking drives GrayA5 pressed fill")
        button.cell!.highlight(false, withFrame: button.bounds, in: button)
        expect(CATransform3DIsIdentity(button.layer!.transform), "Native cell release restores the sidebar transform")
        expect(NSColor(cgColor: button.layer!.backgroundColor!)?.alphaComponent == 0,
               "Native cell release clears the unhovered background")
        button.cell!.highlight(true, withFrame: button.bounds, in: button)
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        expect(CATransform3DIsIdentity(button.layer!.transform) && button.layer?.animation(forKey: "extensionPress") == nil,
               "Losing the original key window cancels its native press")
        window.key = true
        let centre = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let exited = NSEvent.enterExitEvent(with: .mouseExited, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let moved = NSEvent.mouseEvent(with: .mouseMoved, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        func hoverAlpha() -> CGFloat { NSColor(cgColor: button.layer!.backgroundColor!)?.alphaComponent ?? 0 }
        let cover = NSView(frame: button.frame.insetBy(dx: -4, dy: -4))
        window.contentView?.addSubview(cover)
        button.mouseEntered(with: entered)
        expect(hoverAlpha() == 0, "A command surface covering the pin keeps its hover fill off")
        cover.removeFromSuperview()
        button.mouseMoved(with: moved)
        expect(abs(hoverAlpha() - 0.071) < 0.00001, "Moving out from under the cover restores the hover fill")
        button.mouseExited(with: exited)
        let glass = SeeThroughView(frame: cover.frame)
        window.contentView?.addSubview(glass)
        button.mouseEntered(with: entered)
        expect(abs(hoverAlpha() - 0.071) < 0.00001, "A see-through overlay leaves the hover fill alone")
        button.mouseExited(with: exited); glass.removeFromSuperview()
        let topbarAction = ExtensionActionButton(item: item("top"), style: .toolbar)
        window.contentView?.addSubview(topbarAction)
        topbarAction.cell!.highlight(true, withFrame: topbarAction.bounds, in: topbarAction)
        expect(CATransform3DIsIdentity(topbarAction.layer!.transform) && topbarAction.layer?.animation(forKey: "extensionPress") == nil,
               "The distinct topbarAction cell does not acquire the sidebar press spring")
        expect(NSColor(cgColor: topbarAction.layer!.backgroundColor!)?.alphaComponent == 0,
               "The distinct topbarAction cell does not acquire the sidebar pressed fill")
        topbarAction.cell!.highlight(false, withFrame: topbarAction.bounds, in: topbarAction)
        expect((topbarAction.cell as? NSButtonCell)?.highlightsBy.isEmpty == true, "AppKit does not add an unrelated pressed-image effect")

        let toolbar = ExtensionToolbarView(frame: NSRect(x: 0, y: 0, width: 56, height: 28))
        var widths = 0
        toolbar.onWidthChange = { widths += 1 }
        toolbar.update([item("a", pin: 1), item("b", pin: 0), item("c")])
        toolbar.layoutSubtreeIfNeeded()
        expect(toolbar.desiredWidth == 56, "Only pinned actions reserve toolbar width")
        expect(toolbar.subviews.count == 2, "Unpinned actions stay out of the toolbar")
        let a = toolbar.subviews.first { $0.accessibilityIdentifier() == "extension-action-a" }!
        let b = toolbar.subviews.first { $0.accessibilityIdentifier() == "extension-action-b" }!
        expect(b.frame.minX < a.frame.minX, "Real pin positions override model order")
        toolbar.update([item("a", pin: 1), item("b", pin: 0)])
        expect(toolbar.subviews.contains { $0 === a }, "Ordinary model updates preserve native button identity")
        expect(widths == 1, "Unchanged pin geometry does not request another sidebar layout")
        toolbar.frame.size.width = 28
        toolbar.needsLayout = true; toolbar.layoutSubtreeIfNeeded()
        expect(a.isHidden && !b.isHidden, "Compression follows real pin order")
        toolbar.update([item("b", pin: 0)])
        expect(a.superview == nil, "Removed pin is detached")
        expect((a as! NSButton).isEnabled == false, "Detached pin cannot dispatch stale input")
        toolbar.update([])
        expect(toolbar.desiredWidth == 0 && toolbar.subviews.isEmpty, "Clearing a page/profile releases every pin")
        let topbar = ExtensionToolbarView(frame: NSRect(x: 0, y: 0, width: 63, height: 24), style: .toolbar)
        topbar.update([item("first", pin: 0), item("second", pin: 1)])
        topbar.layoutSubtreeIfNeeded()
        let topButtons = topbar.orderedButtons
        expect(topbar.desiredWidth == 64 && !topButtons[0].isHidden && topButtons[1].isHidden,
               "A 63-point toolbar contains one complete 32-point action")
        topbar.frame.size.width = 64
        topbar.needsLayout = true; topbar.layoutSubtreeIfNeeded()
        expect(!topButtons[1].isHidden && topButtons[0].frame.maxX == topButtons[1].frame.minX,
               "Both toolbar pins fit at 64 points with adjoining surfaces")
        expect(topButtons.allSatisfy { $0.frame.height == 24 && $0.layer?.cornerRadius == 6 },
               "Top bar retains its short radius-six surface")
        expect(b.frame.size == NSSize(width: 28, height: 28) && b.layer?.cornerRadius == 9,
               "Sidebar pins retain their independent square radius-nine surface")
        let artwork = NSImage(size: NSSize(width: 32, height: 32))
        let artItem = ExtensionControlItem(identifier: "art", name: "Artwork", tooltip: "", accessibilityLabel: "",
            image: artwork, pinnedIndex: 0, canChangePin: true, execute: {}, showContextMenu: { _ in }, setPinned: { _ in })
        let artButton = ExtensionActionButton(item: artItem, style: .toolbar)
        artButton.frame = NSRect(origin: .zero, size: NSSize(width: 32, height: 24))
        expect(artButton.cell?.imageRect(forBounds: artButton.bounds) == NSRect(x: 0, y: -4, width: 32, height: 32),
               "The native cell centers the genuine canvas at its own size, independent of its hit surface")
        let sidebarArt = ExtensionActionButton(item: artItem)
        sidebarArt.frame = NSRect(origin: .zero, size: ExtensionControlStyle.sidebar.surfaceSize)
        expect(sidebarArt.cell?.imageRect(forBounds: sidebarArt.bounds) == NSRect(x: -2, y: -2, width: 32, height: 32),
               "The sidebar canvas centres the 16-point icon at (6, 6), its badge area filling the surface")
        expect(!artButton.clipsToBounds && !topbar.clipsToBounds,
               "The canvas's badge may overhang the 24-point toolbar surface inside the pane bar")
        let other = ExtensionActionButton(item: ExtensionControlItem(identifier: "other", name: "Other", tooltip: "",
            accessibilityLabel: "", image: NSImage(size: NSSize(width: 64, height: 64)), pinnedIndex: 0,
            canChangePin: true, execute: {}, showContextMenu: { _ in }, setPinned: { _ in }), style: .toolbar)
        other.frame = NSRect(origin: .zero, size: NSSize(width: 32, height: 24))
        expect(other.cell?.imageRect(forBounds: other.bounds) == NSRect(x: 8, y: 4, width: 16, height: 16),
               "An image that is not the action canvas keeps the centred 16-point rect")
        let fallback = ExtensionActionButton(item: item("fallback"))
        fallback.frame = NSRect(origin: .zero, size: ExtensionControlStyle.sidebar.surfaceSize)
        expect(fallback.cell?.imageRect(forBounds: fallback.bounds) == NSRect(x: 6, y: 6, width: 16, height: 16),
               "The fallback symbol keeps the centred 16-point rect")
        let padded = NSImage(size: NSSize(width: 32, height: 32), flipped: true) { _ in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            NSRect(x: 8, y: 8, width: 16, height: 16).fill()
            return true
        }
        func ink(_ host: NSView, scale: Int, _ match: (NSColor) -> Bool) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * scale,
                pixelsHigh: Int(host.bounds.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: rep)
            var bounds = (minX: Int.max, maxX: -1, minY: Int.max, maxY: -1)
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5, match(color) else { continue }
                    bounds = (min(bounds.minX, x), max(bounds.maxX, x), min(bounds.minY, y), max(bounds.maxY, y))
                }
            }
            return bounds
        }
        let red = { (color: NSColor) in color.redComponent > 0.5 && color.greenComponent < 0.3 && color.blueComponent < 0.3 }
        for style in [ExtensionControlStyle.toolbar, .sidebar] {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
            let rendered = ExtensionActionButton(item: ExtensionControlItem(identifier: "padded", name: "Padded",
                tooltip: "", accessibilityLabel: "", image: padded, pinnedIndex: 0, canChangePin: true,
                execute: {}, showContextMenu: { _ in }, setPinned: { _ in }), style: style)
            rendered.frame = NSRect(origin: NSPoint(x: 8, y: 8), size: style.surfaceSize)
            host.addSubview(rendered)
            for scale in [1, 2] {
                let icon = ink(host, scale: scale, red)
                expect(icon.maxX - icon.minX + 1 == 16 * scale && icon.maxY - icon.minY + 1 == 16 * scale,
                       "A padded 32-point canvas renders 16 points of icon ink at \(scale)x in the \(style) surface")
            }
        }

        let green = NSColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1), white = NSColor.white
        func badged(_ text: String, style: ExtensionControlStyle) -> ExtensionActionButton {
            let button = ExtensionActionButton(item: ExtensionControlItem(identifier: "badged", name: "Badged",
                tooltip: "", accessibilityLabel: "", image: artwork, pinnedIndex: 0, canChangePin: true,
                execute: {}, showContextMenu: { _ in }, setPinned: { _ in },
                pinnedArtwork: ExtensionPinnedArtwork(unbadged: padded, badgeText: text, textColor: white,
                                                      backgroundColor: green), badgeText: text), style: style)
            button.frame = NSRect(origin: .zero, size: style.surfaceSize)
            button.layoutSubtreeIfNeeded()
            return button
        }
        func top(_ frame: NSRect?, in button: NSView) -> NSRect? {
            guard var frame else { return nil }
            if !button.isFlipped { frame.origin.y = button.bounds.height - frame.maxY }
            return frame
        }
        for (text, style, expected) in [
            ("3", ExtensionControlStyle.toolbar, NSRect(x: 17, y: 0, width: 11, height: 11)),
            ("3", .sidebar, NSRect(x: 15, y: 2, width: 11, height: 11)),
            ("12", .sidebar, NSRect(x: 11, y: 2, width: 15, height: 11)),
            ("NEW", .toolbar, NSRect(x: 3, y: 0, width: 25, height: 11)),
            ("9999", .toolbar, NSRect(x: 2, y: 0, width: 26, height: 11)),
            ("WWWWWW", .sidebar, NSRect(x: 0, y: 2, width: 26, height: 11)),
        ] {
            let button = badged(text, style: style)
            expect(top(button.badgeFrame, in: button) == expected,
                   "Badge \(text) sits on the \(style) icon's top-right corner at \(expected)")
            expect(button.image === padded, "The \(style) strip shows the unbadged canvas under its own badge")
            expect(button.accessibilityValue() as? String == text, "VoiceOver reads badge \(text) as the action's value")
        }
        let passThrough = badged("3", style: .sidebar)
        let badgeCenter = NSPoint(x: passThrough.badgeFrame!.midX, y: passThrough.badgeFrame!.midY)
        expect(passThrough.hitTest(passThrough.convert(badgeCenter, to: passThrough.superview)) === passThrough,
               "The badge passes clicks to its action button")
        for style in [ExtensionControlStyle.toolbar, .sidebar] {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
            let button = badged("3", style: style)
            button.frame.origin = NSPoint(x: 8, y: 8)
            host.addSubview(button)
            let icon = ink(host, scale: 2, red)
            let badge = ink(host, scale: 2) { $0.greenComponent > 0.6 && $0.redComponent < 0.3 && $0.blueComponent < 0.3 }
            expect(badge.maxX - badge.minX + 1 == 22 && badge.maxY - badge.minY + 1 == 22,
                   "The \(style) badge renders as an 11-point circle at 2x")
            expect(badge.maxX == icon.maxX + 8 && badge.minY == icon.minY - 8,
                   "The \(style) badge overhangs the icon's top-right corner by 4 points at 2x")
        }
        let baked = ExtensionActionButton(item: ExtensionControlItem(identifier: "baked", name: "Baked", tooltip: "",
            accessibilityLabel: "", image: artwork, pinnedIndex: 0, canChangePin: true, execute: {},
            showContextMenu: { _ in }, setPinned: { _ in }, badgeText: "7"), style: .toolbar)
        expect(baked.image === artwork && baked.badgeFrame == nil,
               "Without the unbadged canvas the baked canvas shows alone, with Chromium's badge and no second one")
        expect(baked.accessibilityValue() as? String == "7", "VoiceOver reads an older engine's baked badge too")
        expect(ExtensionPinnedArtwork(unbadged: nil, badgeText: "3", textColor: white, backgroundColor: green) == nil,
               "An older engine without the unbadged canvas falls back to the baked one")
        expect(ExtensionPinnedArtwork(unbadged: padded, badgeText: "3", textColor: nil, backgroundColor: green) == nil,
               "A reported badge without its colours falls back to the baked canvas")
        let plain = ExtensionPinnedArtwork(unbadged: padded, badgeText: "", textColor: nil, backgroundColor: nil)
        expect(plain?.image === padded && plain?.badge == nil, "An empty badge shows the unbadged canvas alone")
        let cleared = badged("3", style: .sidebar)
        cleared.update(ExtensionControlItem(identifier: "badged", name: "Badged", tooltip: "", accessibilityLabel: "",
            image: artwork, pinnedIndex: 0, canChangePin: true, execute: {}, showContextMenu: { _ in }, setPinned: { _ in },
            pinnedArtwork: plain))
        expect(cleared.badgeFrame == nil && cleared.image === padded, "Clearing the badge text hides the shell badge")
        expect(cleared.accessibilityValue() == nil, "An action without badge text has no badge value")
        expect(artwork.size == NSSize(width: 32, height: 32) && artButton.image === artwork,
               "Presentation preserves the shared native image and its source dimensions")
        expect(artButton.imagePosition == .imageOnly,
               "Assigning real action artwork cannot restore a visible title over the icon")
        artButton.update(item("art"))
        expect(artButton.imagePosition == .imageOnly,
               "Refreshing fallback artwork also keeps the cell image-only")
        print("PASS: \(assertions) native extension control assertions")
    }
}
