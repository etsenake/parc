import AppKit

@main struct SidebarRowActionButtonTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let button = SidebarRowActionButton("Archive Tab")
        button.frame = NSRect(x: 10, y: 10, width: 24, height: 25)
        var available = true, accepts = true, dispatches = 0, queries = 0, revision = 0
        button.prepareAction = {
            queries += 1
            guard available else { return nil }
            let original = revision; var used = false
            return {
                guard available, accepts, original == revision, !used else { return false }
                used = true; dispatches += 1; return true
            }
        }
        check(button.accessibilityLabel() == "Archive Tab", "Exact action label")
        check(button.focusRingType == .exterior, "Native keyboard focus treatment")
        check(!button.accessibilityPerformPress() && queries == 0, "Detached does not consult or dispatch owner")
        window.contentView!.addSubview(button)
        button.refreshAvailability()
        check(button.isEnabled && button.isAccessibilityEnabled(), "Attached original action available")
        check(button.accessibilityPerformPress() && dispatches == 1, "AX returns real accepted action")
        accepts = false
        check(!button.accessibilityPerformPress() && dispatches == 1, "Owner refusal is not success")
        accepts = true
        let captured = button.prepareAction!()!
        revision += 1
        check(!captured() && dispatches == 1, "Original command cannot retarget revised owner")
        check(button.accessibilityPerformPress() && dispatches == 2, "New AX request gets current owner")
        button.performClick(nil)
        check(dispatches == 3, "Native target/action path gets a fresh owned command")
        available = false; button.refreshAvailability()
        check(!button.isEnabled && !button.isAccessibilityEnabled(), "Unavailable owner disables real control")
        check(!button.accessibilityPerformPress() && dispatches == 3, "Unavailable AX does not dispatch")
        available = true; button.refreshAvailability()
        check(button.isEnabled, "Availability can return without rebuilding row")
        button.isHidden = true
        check(!button.accessibilityPerformPress(), "Hidden pointer control cannot dispatch")
        check(!button.isAccessibilityEnabled(), "Hidden control not AX enabled")
        button.isHidden = false
        button.highlight(true); button.isHidden = true
        check(CATransform3DIsIdentity(button.layer!.transform), "Hiding cancels any presentation transform")
        check(button.layer!.animation(forKey: "rowActionPress") == nil, "Hiding cancels spring")
        button.isHidden = false
        button.layer!.transform = CATransform3DMakeScale(0.95, 0.95, 1)
        button.isEnabled = false
        check(CATransform3DIsIdentity(button.layer!.transform), "Disabled control clears pressed transform")
        button.refreshAvailability()
        var menus = 0
        button.makeMenu = { menus += 1; return NSMenu(title: "Original row") }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        check(button.menu(for: event)?.title == "Original row" && menus == 1, "Control context keeps row's menu provider")
        button.layer!.transform = CATransform3DMakeScale(0.95, 0.95, 1)
        button.removeFromSuperview()
        check(CATransform3DIsIdentity(button.layer!.transform), "Detachment cancels pressed transform")
        check(!button.accessibilityPerformPress(), "Detached old control cannot act")
        check(button.menu(for: event) == nil && menus == 1, "Detached control cannot request a context")
        window.contentView!.addSubview(button)
        let oldFrame = button.frame
        let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
        button.cacheDisplay(in: button.bounds, to: bitmap)
        check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "Production Close renderer draws native bitmap")
        check(button.frame == oldFrame, "Drawing never changes hit geometry")
        // SidebarCellButtonCloseContentView: black or white bars under one
        //
        func closeInk(dark: Bool) -> (alpha: CGFloat, white: CGFloat, centre: CGFloat) {
            button.dark = dark
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = button.bounds.size
            button.cacheDisplay(in: button.bounds, to: rep)
            var best = (alpha: CGFloat(0), white: CGFloat(0))
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                let color = rep.colorAt(x: x, y: y)!
                if color.alphaComponent > best.alpha { best = (color.alphaComponent, color.redComponent / max(color.alphaComponent, 0.001)) }
            } }
            return (best.alpha, best.white, rep.colorAt(x: 24, y: 25)!.alphaComponent)
        }
        let light = closeInk(dark: false), darkInk = closeInk(dark: true)
        check(abs(light.alpha - 0.565) < 0.01 && light.white < 0.02, "Light Close is black at lightAlpha 0.565, not the theme title (\(light))")
        check(abs(darkInk.alpha - 0.592) < 0.01 && darkInk.white > 0.98, "Dark Close is white at darkAlpha 0.592 (\(darkInk))")
        check(abs(light.centre - 0.565) < 0.01 && abs(darkInk.centre - 0.592) < 0.01, "The bars' crossing is no darker than a bar")
        button.isEnabled = false
        check(abs(closeInk(dark: false).alpha - 0.565 * 0.35) < 0.01, "Disabled Close keeps the 0.35 dimming")
        button.isEnabled = true; button.dark = false

        //
        let reset = SidebarRowResetRegion()
        reset.frame = NSRect(x: 40, y: 10, width: 30, height: 35)
        let queriesBefore = queries
        check(!reset.accessibilityPerformPress() && queries == queriesBefore, "Detached reset region does not consult owner")
        window.contentView!.addSubview(reset); reset.prepareAction = button.prepareAction
        reset.refreshAvailability()
        check(reset.accessibilityLabel() == "Reset Tab to Original URL", "Reset region keeps the reset command label")
        check(reset.focusRingType == .exterior, "Reset region keeps native keyboard focus treatment")
        check(reset.accessibilityPerformPress() && dispatches == 4, "Reset uses same exact-command owner protocol")
        reset.performClick(nil)
        check(dispatches == 5, "Reset target/action path gets a fresh owned command")
        let layer = reset.layer!
        check(layer.backgroundColor == nil, "Idle reset region is clear")
        check(layer.cornerRadius == 12 && layer.cornerCurve == .continuous, "Region corners follow the row background")
        var hoverChanges = 0
        reset.onHoverChange = { hoverChanges += 1 }
        reset.mouseEntered(with: event)
        check(reset.hovered && hoverChanges == 1, "Entering the icon region reports hover")
        check(reset.hoverSubtitle == (NSEvent.modifierFlags.contains(.command) ? .resetAndSeparate : .reset),
              "Hover is the reset or reset-and-separate subtitle state")
        reset.updateHoverSubtitle([]); hoverChanges = 1
        check(reset.hoverSubtitle == .reset, "Plain hover is the reset state")
        check(reset.updateHoverSubtitle(.command) && reset.hoverSubtitle == .resetAndSeparate && hoverChanges == 2,
              "Holding Command switches to Separate From Pinned Tab without pointer motion")
        check(!reset.updateHoverSubtitle([.command, .shift]) && hoverChanges == 2, "Other modifiers keep the separate state")
        check(reset.updateHoverSubtitle([]) && reset.hoverSubtitle == .reset && hoverChanges == 3, "Releasing Command restores reset")
        check(SidebarRowHoverSubtitle.reset.text == "Back to Pinned URL"
              && SidebarRowHoverSubtitle.resetAndSeparate.text == "Separate From Pinned Tab", "Recovered subtitle strings")
        func components(_ cg: CGColor?) -> [CGFloat] {
            let c = NSColor(cgColor: cg!)!.usingColorSpace(.displayP3)!
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
        }
        check(components(layer.backgroundColor) == [0.055, 0.059, 0.063, 0.05], "Hovered region uses SidebarItemBackground")
        reset.corners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        check(layer.maskedCorners == [.layerMinXMinYCorner, .layerMinXMaxYCorner], "Per-region corner mask")
        reset.mouseExited(with: event)
        check(!reset.hovered && reset.hoverSubtitle == nil && hoverChanges == 4 && layer.backgroundColor == nil,
              "Leaving clears hover and the subtitle state")
        reset.mouseEntered(with: event); reset.isHidden = true
        check(!reset.hovered && reset.hoverSubtitle == nil, "Hiding cancels region hover")
        reset.isHidden = false
        available = false; reset.refreshAvailability()
        check(!reset.isEnabled && !reset.isAccessibilityEnabled() && !reset.accessibilityPerformPress(),
              "Unavailable reset owner disables the region")
        check(reset.hitTest(NSPoint(x: 50, y: 20)) == nil, "An unavailable reset region leaves the click to the row")
        reset.mouseEntered(with: event)
        check(!reset.hovered, "A disabled region shows no hover")
        available = true; reset.refreshAvailability()
        check(!NSEvent.modifierFlags.contains(.command) || reset.hitTest(NSPoint(x: 50, y: 20)) == nil,
              "Without a separate owner Command leaves the click to the row")
        check(NSEvent.modifierFlags.contains(.command) || reset.hitTest(NSPoint(x: 50, y: 20)) === reset,
              "An available reset region takes a plain click")
        // Command picks Separate From Pinned Tab's own one-use command
        //
        var separations = 0
        reset.prepareSeparate = {
            guard available else { return nil }
            var used = false
            return { guard !used else { return false }; used = true; separations += 1; return true }
        }
        let resets = dispatches
        check(reset.lease(.command)?() == true && separations == 1 && dispatches == resets, "Command click separates")
        check(reset.lease([.command, .shift])?() == true && separations == 2, "Command with Shift still separates")
        check(reset.lease([])?() == true && dispatches == resets + 1 && separations == 2, "A plain click resets")
        check(reset.lease(.shift)?() == true && dispatches == resets + 2, "Shift alone resets reads only Command")
        let separate = reset.lease(.command)!
        check(separate() && !separate() && separations == 3, "A separation command is one-use")
        available = false
        check(reset.lease(.command) == nil && reset.lease([]) == nil, "No command while the owner is unavailable")
        available = true; reset.refreshAvailability()
        reset.toolTip = "Reset Tab ⌥⌘R"
        check(reset.toolTip == "Reset Tab ⌥⌘R", "Reset tooltip carries the registry shortcut")
        reset.makeMenu = { menus += 1; return NSMenu(title: "Original row") }
        check(reset.menu(for: event)?.title == "Original row", "Region context keeps the row's menu provider")
        let body = SidebarRowBodyRegionView(frame: NSRect(x: 70, y: 10, width: 100, height: 35))
        window.contentView!.addSubview(body)
        check(body.hitTest(NSPoint(x: 80, y: 20)) == nil && !body.isAccessibilityElement(), "Body region takes no input")
        body.dark = true; body.hovered = true
        check(components(body.layer!.backgroundColor) == [0.98, 0.984, 1, 0.1], "Dark body hover uses SidebarItemBackground")
        let slash = SidebarRowSlashView(frame: NSRect(x: 0, y: 0, width: 4, height: 15))
        check(slash.hitTest(NSPoint(x: 2, y: 7)) == nil && !slash.isAccessibilityElement(), "Slash is decorative")
        let slashBitmap = slash.bitmapImageRepForCachingDisplay(in: slash.bounds)!
        slash.cacheDisplay(in: slash.bounds, to: slashBitmap)
        check(slashBitmap.pixelsWide > 0, "Production slash renders")
        // The row's −7 sublayer lift moves the title stack up on screen, as
        //
        let row = FlippedRow(frame: NSRect(x: 0, y: 0, width: 200, height: 35)); row.wantsLayer = true
        window.contentView!.addSubview(row)
        let stack = SidebarRowTitleStack(frame: NSRect(x: 38, y: 8, width: 100, height: 32)); stack.wantsLayer = true
        let title = NSTextField(labelWithString: "Title"); title.frame = NSRect(x: 0, y: 0, width: 100, height: 18); title.wantsLayer = true
        stack.addSubview(title); row.addSubview(stack)
        check(stack.hitTest(NSPoint(x: 50, y: 10)) == nil, "Title stack leaves input to the row")
        window.contentView!.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        let root = window.contentView!.layer!
        let resting = title.layer!.convert(CGPoint.zero, to: root)
        stack.layer!.sublayerTransform = CATransform3DMakeTranslation(0, -7, 0)
        let lifted = title.layer!.convert(CGPoint.zero, to: root)
        check(root.contentsAreFlipped() == false && lifted.y - resting.y == 7, "Lift raises the title 7 points")
        window.close()
        // A costly owner (the split cell's Close) enables through a cheap
        // check and prepares its action only when pressed; hidden, it waits.
        let costly = SidebarRowActionButton("Archive this item")
        costly.frame = NSRect(x: 40, y: 10, width: 24, height: 24)
        var prepares = 0, cheap = true, costlyDispatches = 0
        costly.prepareAction = { prepares += 1; return { costlyDispatches += 1; return true } }
        costly.isAvailable = { cheap }
        costly.isHidden = true
        window.contentView!.addSubview(costly)
        costly.refreshAvailability()
        check(prepares == 0, "Hidden button does not refresh")
        costly.isHidden = false
        check(costly.isEnabled && prepares == 0, "Showing refreshes through the cheap check without preparing")
        cheap = false; costly.refreshAvailability()
        check(!costly.isEnabled && !costly.isAccessibilityEnabled() && prepares == 0, "Cheap check disables without preparing")
        cheap = true; costly.refreshAvailability()
        check(costly.accessibilityPerformPress() && prepares == 1 && costlyDispatches == 1, "Press prepares and runs the action once")
        print("\(checks) Sidebar row action assertions passed (isolated AppKit; no browser or Apple Events)")
    }
}

private final class FlippedRow: NSView {
    override var isFlipped: Bool { true }
}
