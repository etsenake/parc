import AppKit
import QuartzCore

@MainActor final class FakePan: NSPanGestureRecognizer {
    var fakeState: NSGestureRecognizer.State = .possible
    var translationX: CGFloat = 0
    var velocityX: CGFloat = 0
    var measuredIn: [NSView?] = []
    override var state: NSGestureRecognizer.State { get { fakeState } set { fakeState = newValue } }
    override func translation(in view: NSView?) -> NSPoint { measuredIn.append(view); return NSPoint(x: translationX, y: 7) }
    override func velocity(in view: NSView?) -> NSPoint { NSPoint(x: velocityX, y: 9) }
}
@MainActor final class FakeClick: NSClickGestureRecognizer {
    var fakeState: NSGestureRecognizer.State = .possible
    override var state: NSGestureRecognizer.State { get { fakeState } set { fakeState = newValue } }
}

@main @MainActor struct SidebarResizeRegionTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarResizeRegion: \(message)") }
    }
    static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)); CATransaction.flush()
    }
    static func fade(_ region: SidebarResizeRegionView) -> CABasicAnimation? {
        region.indicatorLayer.animation(forKey: "opacity") as? CABasicAnimation
    }
    static func main() {
        typealias R = SidebarResizeRegionView
        check(R.frame(trailing: NSRect(x: 0, y: 0, width: 228, height: 700), in: NSRect(x: 0, y: 0, width: 1000, height: 700))
              == NSRect(x: 224, y: 11, width: 8, height: 678), "locked strip straddles the trailing edge")
        check(R.frame(trailing: NSRect(x: 5, y: 5, width: 228, height: 690), in: NSRect(x: 0, y: 0, width: 1000, height: 700))
              == NSRect(x: 229, y: 11, width: 8, height: 678), "floating strip follows the container maxX")
        check(R.frame(trailing: NSRect(x: 0, y: 0, width: 300, height: 10), in: NSRect(x: 0, y: 40, width: 500, height: 10))
              == NSRect(x: 296, y: 51, width: 8, height: 0), "vertical insets follow the container and never go negative")

        _ = NSApplication.shared
        // Real AppKit hierarchy, outside the desktop; no browser, profile or input.
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        root.wantsLayer = true; window.contentView = root
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let region = R(frame: .zero)
        var haptics = 0
        region.performHaptic = { haptics += 1 }
        region.referenceView = sidebar
        root.addSubview(sidebar); root.addSubview(region)
        window.orderFront(nil)
        region.frame = R.frame(trailing: sidebar.frame, in: root.bounds)
        root.layoutSubtreeIfNeeded(); CATransaction.flush()

        let indicator = region.indicatorLayer
        check(region.wantsLayer && region.layer?.masksToBounds == false, "layer-backed and unclipped")
        check(indicator.superlayer === region.layer && indicator.isHidden && indicator.opacity == 0.5, "hidden indicator sublayer")
        check(indicator.bounds.size == CGSize(width: 3, height: 670), "3 pt by height − 8")
        check(indicator.anchorPoint == CGPoint(x: 0.5, y: 0.5) && indicator.position == CGPoint(x: 0, y: 339), "centred on the leading edge")
        check(indicator.frame.minX == -1.5 && indicator.frame.minY == 4, "half the line sits outside the strip")
        check(indicator.path?.boundingBox == CGRect(x: 0, y: 0, width: 3, height: 670), "rounded path fills the line")
        check(!region.mouseDownCanMoveWindow, "strip never drags the window")
        // AppKit asks for tracking areas when the pointer next needs them, which
        // an off-screen window never does; ask twice, as each geometry change would.
        region.updateTrackingAreas(); region.updateTrackingAreas()
        let area = region.trackingAreas.first
        check(region.trackingAreas.count == 1 && area?.options.rawValue == 0x227 && area?.owner === region,
              "recovered tracking options 0x227, replaced on each update")
        check(region.gestureRecognizers.count == 2 && region.gestureRecognizers.allSatisfy { $0.delegate == nil }, "two recognizers without delegate")
        check(region.panGestureRecognizer.view === region, "pan installed")
        check(region.doubleClickGestureRecognizer.numberOfClicksRequired == 2 && region.doubleClickGestureRecognizer.view === region, "double-click installed")

        region.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        region.display(); CATransaction.flush()
        check(indicator.fillColor == region.color.cgColor && indicator.strokeColor == region.color.cgColor, "fill and stroke use the theme colour")
        region.frame.size.height = 100
        root.layoutSubtreeIfNeeded()
        check(indicator.bounds.height == 92 && indicator.position.y == 50, "height follows relayout")
        region.frame = R.frame(trailing: sidebar.frame, in: root.bounds)
        root.layoutSubtreeIfNeeded(); wait(0.05)

        // Hit test of the actual strip, its overlays and child windows.
        let center = region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil)
        check(region.isUnobstructed(atWindowPoint: center), "unobstructed strip owns the cursor")
        check(!region.isUnobstructed(atWindowPoint: NSPoint(x: 600, y: 300)), "page area does not")
        let overlay = NSView(frame: NSRect(x: 200, y: 0, width: 60, height: 700))
        root.addSubview(overlay)
        check(!region.isUnobstructed(atWindowPoint: center), "a view above the strip obstructs it")
        overlay.removeFromSuperview()
        let child = NSWindow(contentRect: NSRect(x: -10000 + 200, y: -10000, width: 60, height: 700),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false; child.contentView = NSView()
        window.addChildWindow(child, ordered: .above)
        check(!region.isUnobstructed(atWindowPoint: center), "a child window above the strip obstructs it")
        child.ignoresMouseEvents = true
        check(region.isUnobstructed(atWindowPoint: center), "a click-through child window does not")
        window.removeChildWindow(child); child.close()

        // Hover: 0.25 s delay, 0.2 s fades, and cancellation before the delay.
        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: center, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let exited = NSEvent.enterExitEvent(with: .mouseExited, location: center, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        region.mouseEntered(with: entered)
        check(region.isHovered && indicator.isHidden, "hover does not show at once")
        wait(0.15)
        check(indicator.isHidden && fade(region) == nil, "still waiting at 0.15 s")
        wait(0.2)
        check(!indicator.isHidden && indicator.opacity == 0.5, "shown after 0.25 s")
        let fadeIn = fade(region)
        check(fadeIn?.fromValue as? Double == 0 && fadeIn?.toValue as? Double == 0.5, "fades 0 → 0.5")
        check(fadeIn?.duration == 0.2 && fadeIn?.fillMode == .forwards, "fade-in timing")
        region.mouseExited(with: exited)
        let fadeOut = fade(region)
        check(fadeOut?.fromValue as? Double == 0.5 && fadeOut?.toValue as? Double == 0 && fadeOut?.duration == 0.2, "fades 0.5 → 0")
        check(!indicator.isHidden, "visible while fading out")
        wait(0.4)
        check(indicator.isHidden && indicator.opacity == 0.5 && fade(region) == nil, "hidden at model opacity 0.5 after fade")
        region.mouseEntered(with: entered); wait(0.1)
        region.mouseExited(with: exited); wait(0.4)
        check(indicator.isHidden && fade(region) == nil, "hover ending before 0.25 s cancels the show")
        region.mouseMoved(with: entered)
        check(region.isHovered, "movement inside re-establishes hover")
        region.mouseExited(with: exited); wait(0.3)

        // Resizing shows immediately and suppresses the hover path.
        region.isResizing = true
        check(!indicator.isHidden && indicator.animationKeys() == nil, "resizing shows at once without animation")
        region.mouseEntered(with: entered); wait(0.35)
        check(!indicator.isHidden && fade(region) == nil, "hover while resizing adds no fade")
        region.isResizing = false
        check(!indicator.isHidden && fade(region) == nil, "end of resizing keeps a hovered indicator")
        region.mouseExited(with: exited)
        check(fade(region)?.toValue as? Double == 0, "later exit fades out")
        region.isResizing = true
        wait(0.35)
        check(!indicator.isHidden, "an interrupted fade cannot hide a resizing indicator")
        region.isResizing = false
        check(fade(region)?.toValue as? Double == 0, "unhovered end of resizing fades out")
        wait(0.35)
        check(indicator.isHidden, "fade-out completes")
        region.isResizing = false
        check(fade(region) == nil, "unchanged resizing value does nothing")

        // Snap feedback.
        region.isResizing = true
        region.present([.previewHiddenChanged(true), .breakpointChanged(1)])
        check(haptics == 0 && indicator.animationKeys() == nil, "layout events have no feedback")
        indicator.add(CABasicAnimation(keyPath: "opacity"), forKey: "opacity")
        region.present([.snapEngaged])
        check(haptics == 1 && fade(region) == nil, "engage performs one haptic after removing animations")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let pulse = indicator.animation(forKey: "transform.scale.x") as? CABasicAnimation
            check(pulse?.keyPath == "transform.scale.x" && pulse?.fromValue as? Double == 1 && pulse?.toValue as? Double == 1.7, "scale.x 1 → 1.7")
            check(pulse?.duration == 0.08 && pulse?.autoreverses == true && pulse?.fillMode == .forwards, "0.08 s autoreversing pulse")
            var points = [Float](repeating: 0, count: 2), expected: [[Float]] = [[0.215, 0.61], [0.355, 1]]
            for index in 1...2 {
                pulse?.timingFunction?.getControlPoint(at: index, values: &points)
                check(points == expected[index - 1], "pulse timing control point \(index)")
            }
        }
        region.present([.snapReleased(haptic: false)])
        check(haptics == 1, "short hold release is silent")
        region.present([.snapReleased(haptic: true)])
        check(haptics == 2, "long hold release performs the haptic")
        region.isResizing = false; wait(0.35)

        // Pan forwarding, cursor rects and session cancellation.
        var pans: [(NSGestureRecognizer.State, CGFloat, CGFloat)] = []
        region.onPan = { pans.append(($0, $1, $2)) }
        let pan = FakePan(target: nil, action: nil)
        func send(_ state: NSGestureRecognizer.State, _ x: CGFloat, _ v: CGFloat) {
            pan.fakeState = state; pan.translationX = x; pan.velocityX = v
            region.perform(NSSelectorFromString("handlePan:"), with: pan)
        }
        send(.changed, 5, 1)
        check(pans.isEmpty, "a change without a began session is ignored")
        send(.began, 0, 0)
        check(pans.count == 1 && pans[0].0 == .began && !window.areCursorRectsEnabled, "began forwards and disables cursor rects")
        check(pan.measuredIn.allSatisfy { $0 === sidebar }, "translation measured in the reference view")
        send(.changed, -12.5, -40)
        check(pans.count == 2 && pans[1].0 == .changed && pans[1].1 == -12.5 && pans[1].2 == -40, "change forwards x translation and velocity")
        send(.ended, -20, -60)
        check(pans.count == 3 && pans[2].0 == .ended && pans[2].1 == -20 && window.areCursorRectsEnabled, "end forwards and restores cursor rects")
        send(.ended, -20, -60)
        check(pans.count == 3, "end is reported once")
        send(.began, 0, 0); send(.changed, 30, 10)
        region.isHidden = true
        check(pans.count == 6 && pans[5].0 == .cancelled && pans[5].1 == 30 && window.areCursorRectsEnabled, "hiding cancels the drag once")
        send(.changed, 40, 0); send(.cancelled, 40, 0)
        check(pans.count == 6, "late native callbacks belong to no session")
        region.isHidden = false
        send(.began, 0, 0)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(pans.count == 8 && pans[7].0 == .cancelled && window.areCursorRectsEnabled, "resigning key cancels the drag")
        send(.began, 0, 0); send(.failed, 3, 0)
        check(pans.count == 10 && pans[9].0 == .failed, "failure forwards")

        var doubleClicks = 0
        region.onDoubleClick = { doubleClicks += 1 }
        let click = FakeClick(target: nil, action: nil)
        click.fakeState = .ended
        region.perform(NSSelectorFromString("handleDoubleClick:"), with: click)
        check(doubleClicks == 1, "recognized double-click forwards")
        click.fakeState = .began
        region.perform(NSSelectorFromString("handleDoubleClick:"), with: click)
        check(doubleClicks == 1, "unrecognized click does nothing")

        region.mouseEntered(with: entered)
        region.removeFromSuperview()
        check(!region.isHovered, "leaving the window clears hover")
        window.orderOut(nil)
        print("SidebarResizeRegion: \(count) assertions passed")
    }
}
