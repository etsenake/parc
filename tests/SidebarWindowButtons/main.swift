import AppKit

final class FlippedHost: NSView { override var isFlipped: Bool { true } }
final class GroupQueries { var receivers: [ObjectIdentifier] = []; var answers: [Bool] = [] }

@main @MainActor struct SidebarWindowButtonsTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarWindowButtons: \(message)") }
    }
    static let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    static func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: style,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentView?.wantsLayer = true
        return window
    }
    static func subroles(_ buttons: [NSButton]) -> [NSAccessibility.Subrole?] {
        buttons.map { (NSAccessibility.unignoredDescendant(of: $0) as? NSCell)?.accessibilitySubrole() }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        typealias W = WindowStandardButtons
        check(W.buttonDimension == 14 && W.buttonSpace == (isAtLeast26 ? 9 : 6), "1.170's 14-point buttons, 9 apart on macOS 26+")
        check(W.stackSize == CGSize(width: isAtLeast26 ? 60 : 54, height: 14), "3 × 14 + 2 × spacing by 14")
        let lights = W()
        check(lights.buttons.isEmpty && lights.frame.size == W.stackSize, "formula size before a window")

        let main = window()
        main.standardWindowButton(.zoomButton)?.isEnabled = false
        let systemButtons = W.systemButtons(of: main)
        check(systemButtons.count == 3, "window's own buttons captured")
        let sidebar = FlippedHost(frame: NSRect(x: 0, y: 0, width: 228, height: 600))
        main.contentView?.addSubview(sidebar)
        sidebar.addSubview(lights)
        let made = lights.buttons
        check(made.count == 3, "close, minimize and zoom created in viewDidMoveToWindow")
        check(zip(made, systemButtons).allSatisfy { type(of: $0) == type(of: $1) && $0 !== $1 },
              "same widget classes as the window's own, but new instances")
        check(made.allSatisfy { $0.superview === lights && $0.target == nil && $0.action != nil },
              "direct children keeping AppKit's own actions")
        check(made[0].isEnabled && made[1].isEnabled && !made[2].isEnabled, "enabled state copied from the window's own buttons")
        let initial = main.collectionBehavior
        for behavior in [initial, initial.union(.fullScreenNone), initial.union(.fullScreenPrimary)] {
            main.collectionBehavior = behavior
            let mine = subroles(made), theirs = subroles(systemButtons)
            check(mine == theirs && mine.prefix(2) == [.closeButton, .minimizeButton], "subroles match the window's own (\(mine), \(theirs))")
        }
        main.collectionBehavior = initial.union(.fullScreenNone)
        check(subroles(made).last == .zoomButton, "a window that cannot go full screen exposes AXZoomButton")
        main.collectionBehavior = initial.union(.fullScreenPrimary)
        check(subroles(made).last == .fullScreenButton, "a full-screen-primary window exposes AXFullScreenButton")
        main.collectionBehavior = initial
        lights.removeFromSuperview(); sidebar.addSubview(lights)
        check(lights.buttons.count == 3 && zip(lights.buttons, made).allSatisfy(===), "made once")

        let bar = SidebarChromeLayout.toolbar(width: 228, windowButtons: W.stackSize, showsNavigation: true)
        check(bar.windowButtons == CGRect(x: 13, y: 17, width: W.stackSize.width, height: 14), "lights at 13, centred in the row")
        check(bar.toggle?.minX == (isAtLeast26 ? 77 : 71) && bar.windowButtons?.midY == bar.toggle?.midY,
              "toggle 4 points after the lights and level with them")

        lights.frame = bar.windowButtons ?? .zero; lights.layoutSubtreeIfNeeded()
        let pitch = W.buttonDimension + W.buttonSpace
        check(!isAtLeast26 || lights.buttons.map(\.frame) == (0..<3).map { NSRect(x: CGFloat($0) * pitch, y: 0, width: 14, height: 14) },
              "14-point buttons 23 apart on macOS 26+")
        check(lights.buttons.enumerated().allSatisfy { abs($1.frame.midX - (CGFloat($0) * pitch + 7)) < 0.001 && abs($1.frame.midY - 7) < 0.001 },
              "each button centred on its slot")
        let overlays = lights.subviews.filter { !($0 is NSButton) }
        check(overlays.count == 3 && zip(overlays, lights.buttons).allSatisfy { $0.frame == $1.frame.insetBy(dx: 1, dy: 1) },
              "one overlay 2 points smaller over each button")
        check(overlays.allSatisfy { $0.hitTest(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) == nil }, "overlays never take the click")
        let point = lights.convert(NSPoint(x: lights.buttons[1].frame.midX, y: lights.buttons[1].frame.midY), to: lights.superview)
        check(lights.hitTest(point) === lights.buttons[1], "the minimize widget receives its click")
        if isAtLeast26 {
            let windowFrame = main.frame
            let frames = lights.buttons.map { button -> NSRect in
                let frame = (NSAccessibility.unignoredDescendant(of: button) as? NSAccessibilityElementProtocol)?.accessibilityFrame() ?? .zero
                return NSRect(x: frame.minX - windowFrame.minX, y: windowFrame.maxY - frame.maxY, width: frame.width, height: frame.height)
            }
            check(frames.allSatisfy { $0.size == CGSize(width: 16, height: 16) }, "AX frames 16 × 16 as in 1.170 (\(frames))")
            check(zip(frames, [12, 35, 57] as [CGFloat]).allSatisfy { abs($0.minX - $1 / 0.9905) <= 1 && abs($0.minY - 16 / 0.9905) <= 1 },
                  "AX frames within a point of 1.170's (\(frames))")
            check(abs((bar.toggle?.minX ?? 0) - 76 / 0.9905) <= 1, "toggle within a point of 1.170's")
        }

        let selector = NSSelectorFromString("_mouseInGroup:")
        check(lights.responds(to: selector), "answers _mouseInGroup:")
        typealias Query = @convention(c) (AnyObject, Selector, AnyObject?) -> Bool
        let method = class_getInstanceMethod(W.self, selector)!
        let originalIMP = method_getImplementation(method)
        let original = unsafeBitCast(originalIMP, to: Query.self)
        let queries = GroupQueries()
        let counting: @convention(block) (AnyObject, AnyObject?) -> Bool = { receiver, button in
            let answer = original(receiver, selector, button)
            queries.receivers.append(ObjectIdentifier(receiver)); queries.answers.append(answer)
            return answer
        }
        method_setImplementation(method, imp_implementationWithBlock(counting))
        func askedOnlyLights() -> Bool { !queries.receivers.isEmpty && queries.receivers.allSatisfy { $0 == ObjectIdentifier(lights) } }
        main.orderFront(nil); CATransaction.flush()
        check(askedOnlyLights() && !queries.answers.contains(true), "the shown widgets ask the lights (\(queries.receivers.count) queries)")
        queries.receivers = []; queries.answers = []
        lights.setMouseInside(true); CATransaction.flush()
        check(askedOnlyLights() && queries.answers.allSatisfy { $0 }, "a hover change makes them ask again, answered true")
        lights.setMouseInside(false); CATransaction.flush()
        queries.receivers = []; queries.answers = []
        let intermediate = NSView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        let nested = NSWindow.standardWindowButton(.closeButton, for: style)!
        intermediate.addSubview(nested); lights.addSubview(intermediate); CATransaction.flush()
        check(askedOnlyLights(), "and find them across an intermediate view (\(queries.receivers.count) queries)")
        intermediate.removeFromSuperview()
        method_setImplementation(method, originalIMP)
        func inGroup() -> Bool { original(lights, selector, lights.buttons[0]) }
        lights.appearance = NSAppearance(named: .aqua); lights.displayIfNeeded()
        check(!inGroup() && abs(lights.alphaValue - 0.1) < 0.0001, "not hovered in Aqua: alpha 0.1")
        check(overlays.allSatisfy { !$0.isHidden && $0.layer?.cornerRadius == $0.bounds.height / 2 }, "round overlays shown while dimmed")
        overlays.forEach { $0.displayIfNeeded() }
        check(overlays.first?.layer?.backgroundColor == CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), "DimmedWindowControls black in Aqua")
        lights.appearance = NSAppearance(named: .darkAqua); lights.displayIfNeeded(); overlays.forEach { $0.displayIfNeeded() }
        check(abs(lights.alphaValue - 0.33) < 0.0001, "not hovered in Dark Aqua: alpha 0.33")
        check(overlays.first?.layer?.backgroundColor == CGColor(srgbRed: 0.953, green: 0.953, blue: 0.918, alpha: 1), "Dark Aqua overlay colour")
        lights.setMouseInside(true); lights.displayIfNeeded()
        check(inGroup() && lights.alphaValue == 1 && overlays.allSatisfy(\.isHidden), "hovered: glyphs together, full alpha, no overlays")
        lights.isHidden = true
        check(!lights.mouseInside, "a hidden header drops its hover")
        lights.isHidden = false
        check(!lights.mouseInside && overlays.allSatisfy { !$0.isHidden }, "re-shown away from the pointer it dims again")
        lights.setMouseInside(true); lights.setPresented(false)
        check(!lights.mouseInside && !lights.isHiddenOrHasHiddenAncestor, "a header leaving with an unhidden sidebar drops its hover")
        lights.setMouseInside(true); lights.setPresented(true)
        check(!lights.mouseInside, "its return re-tests the pointer, which is elsewhere")
        do {
            let pointer = NSEvent.mouseLocation
            let under = NSWindow(contentRect: NSRect(x: pointer.x - 30, y: pointer.y - 93, width: 200, height: 100),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
            under.isReleasedWhenClosed = false
            let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            under.contentView?.addSubview(host)
            let returning = W(); host.addSubview(returning); returning.frame.origin = .zero
            returning.setPresented(false)
            check(!returning.mouseInside && !under.isVisible, "a header leaving under the pointer drops its hover")
            returning.setPresented(true)
            check(returning.mouseInside, "its return under the pointer hovers it again")
            under.setFrameOrigin(NSPoint(x: pointer.x + 400, y: pointer.y))
            returning.setPresented(true)
            check(!returning.mouseInside, "and away from the pointer it does not")
            under.close()
        }

        typealias P = WindowFullscreenPhase
        let cases: [(phase: P?, sidebarless: Bool, system: Bool, header: Bool)] = [
            (nil, false, false, true), (.entering, false, false, false), (.expanded, false, true, false), (.exiting, false, false, true),
            (nil, true, true, true), (.entering, true, false, false), (.expanded, true, true, false), (.exiting, true, false, true)]
        for (phase, sidebarless, system, header) in cases {
            let shows = P.apply(phase, sidebarless: sidebarless, system: systemButtons)
            check(systemButtons.allSatisfy { $0.isHidden == !system && $0.window === main } && shows == header,
                  "\(String(describing: phase)), sidebarless \(sidebarless): window's own \(system), header \(header)")
            let row = SidebarChromeLayout.toolbar(width: 228, windowButtons: shows ? W.stackSize : nil, showsNavigation: true)
            check((row.windowButtons != nil) == header && row.toggle?.minX == (header ? bar.toggle?.minX : 13),
                  "the header drops its lights and the toggle leads at 13 without them")
            check(lights.buttons.allSatisfy { !$0.isHidden }, "the rule never hides the sidebar's own widgets")
        }
        check(P.current(nil, inFullScreen: false) == nil && P.current(nil, inFullScreen: true) == .expanded,
              "a full-screen style mask without delegate callbacks counts as expanded")
        check(P.current(.expanded, inFullScreen: false) == nil && P.current(.entering, inFullScreen: false) == .entering
              && P.current(.exiting, inFullScreen: true) == .exiting, "leaving without did-exit, and transitions, reconcile")
        check(P.apply(P.current(nil, inFullScreen: true), sidebarless: false, system: systemButtons) == false
              && systemButtons.allSatisfy { !$0.isHidden }, "so the window's own show in place of the header's")
        for phase in [nil, .entering, .expanded, .exiting] as [P?] {
            check(P.showsSystemButtons(phase, sidebarless: false) != P.showsSidebarButtons(phase) || phase == .entering,
                  "exactly one set of traffic lights except while entering")
        }
        _ = P.apply(nil, sidebarless: false, system: systemButtons)
        check(main.standardWindowButton(.closeButton) === lights.buttons[0], "-standardWindowButton: answers with the content widget")
        check(main.standardWindowButton(.zoomButton)?.isEnabled == false, "so its enabled state must match the window's own")

        let other = window(); other.orderFront(nil)
        let closing = window(); closing.orderFront(nil)
        let closingLights = W(); closing.contentView?.addSubview(closingLights)
        check(!closing.isKeyWindow && !other.isKeyWindow, "no key window")
        closingLights.buttons[0].performClick(nil)
        check(!closing.isVisible && other.isVisible, "close acts on its own window")
        for window in [main, other, closing] { window.orderOut(nil) }
        print("SidebarWindowButtons: \(count) assertions passed")
    }
    static var isAtLeast26: Bool { ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) }
}
