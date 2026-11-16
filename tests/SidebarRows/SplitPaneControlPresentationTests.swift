import AppKit
import QuartzCore

@MainActor private final class ControlWindow: NSWindow {
    var key = true
    var pointer = NSPoint(x: -100, y: -100)
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    override var isKeyWindow: Bool { key }
}
private final class FlippedControlHost: NSView { override var isFlipped: Bool { true } }
private final class TrackingEvent: NSEvent {
    var area: NSTrackingArea?
    var location = NSPoint.zero
    var eventWindow: NSWindow?
    override var trackingArea: NSTrackingArea? { area }
    override var locationInWindow: NSPoint { location }
    override var window: NSWindow? { eventWindow }
}
private final class SeeThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

@main struct SplitPaneControlPresentationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        GeometryWrites.install()
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        check(PaneTopBarLayout.height == 32 && PaneTopBarLayout.horizontalInset == 5, "shared original parent dimensions")
        check(PaneTopBarLayout.frame(x: 15, width: 32, height: 24) == NSRect(x: 15, y: 4, width: 32, height: 24), "native symbol centered independently of content inset")
        check(PaneTopBarLayout.frame(x: 13, width: 100, height: 26).midY == 16, "title centers in same parent row")
        let window = ControlWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: window.contentView!.bounds); window.contentView = host
        let control = SplitPaneControl(.menu)
        control.frame = NSRect(x: 20, y: 20, width: 32, height: 24)
        host.addSubview(control); control.layoutSubtreeIfNeeded(); control.updateTrackingAreas()
        let background = control.layer!.sublayers!.first!
        let glyph = control.subviews.compactMap { $0 as? NSImageView }.first!
        check(control.intrinsicContentSize == NSSize(width: 32, height: 24), "original symbol surface")
        check(background.frame == control.bounds && background.cornerRadius == 6 && background.cornerCurve == .continuous, "original continuous rounded background")
        check(control.focusRingMaskBounds == control.bounds, "native focus ring uses actual symbol surface")
        check(control.accessibilityLabel() == "Split View Menu" && control.parcTooltip == TooltipConfiguration("Split View Options")
              && control.toolTip == nil && control.accessibilityHelp() == "Split View Options", "original menu identity, Parc tooltip and its help")
        check(control.accessibilityRole() == .button, "native button AX role")
        check(glyph.hitTest(.zero) == nil && !glyph.isAccessibilityElement(), "passive image has no input or AX identity")
        check(control.hitTest(NSPoint(x: 30, y: 30)) === control, "native button owns glyph hit")
        check((control.cell as? NSButtonCell)?.highlightsBy == [], "system cell does not add an unrelated press fill")
        func ownedAreas() -> [NSTrackingArea] {
            control.trackingAreas.filter { $0.owner === control && $0.options == [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeInKeyWindow] }
        }
        check(ownedAreas().count == 1, "one decoration tracking owner alongside AppKit's own tracking")
        let old = TrackingEvent(); old.area = ownedAreas()[0]
        control.updateTrackingAreas()
        control.mouseEntered(with: old)
        check(!control.isHovered, "retired tracking event cannot start hover")
        let hover = TrackingEvent(); hover.area = ownedAreas()[0]
        control.appearance = NSAppearance(named: .aqua); control.viewDidChangeEffectiveAppearance()
        check(abs((glyph.contentTintColor?.alphaComponent ?? 0) - 0.55) < 0.00001 && background.opacity == 0, "light foreground and rest")
        control.mouseEntered(with: hover)
        check(control.isHovered && abs(background.opacity - 0.05) < 0.00001, "light hover")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(abs((background.animation(forKey: "split-control-opacity")?.duration ?? 0) - 0.18) < 0.00001, "original hover timing")
        }
        control.cell!.highlight(true, withFrame: control.bounds, in: control)
        check(control.isPressed && abs(background.opacity - 0.09) < 0.00001, "native press takes precedence")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(abs((background.animation(forKey: "split-control-opacity")?.duration ?? 0) - 0.16) < 0.00001, "original press timing")
        }
        control.appearance = NSAppearance(named: .darkAqua); control.viewDidChangeEffectiveAppearance()
        check(abs((glyph.contentTintColor?.alphaComponent ?? 0) - 0.675) < 0.00001 && abs(background.opacity - 0.13) < 0.00001, "dark enabled press")
        check(NSColor(cgColor: background.backgroundColor!)?.usingColorSpace(.sRGB)?.redComponent == 1, "named dark ink is white")
        control.cell!.highlight(false, withFrame: control.bounds, in: control)
        check(!control.isPressed && abs(background.opacity - 0.09) < 0.00001, "native release returns to dark hover")
        control.mouseExited(with: old)
        check(control.isHovered, "retired exit cannot clear current hover")
        control.mouseExited(with: hover)
        check(!control.isHovered && background.opacity == 0, "current exit returns to rest")
        var actions = 0
        control.actionBlock = { actions += 1 }
        control.performClick(nil)
        check(actions == 1, "actual native button dispatch reaches original callback")
        control.isEnabled = false; control.performClick(nil); control.mouseEntered(with: hover)
        check(actions == 1 && !control.isHovered && !control.isPressed && background.opacity == 0, "disabled refuses action and decoration")
        check(glyph.contentTintColor?.alphaComponent == 0.25, "original disabled ink")
        control.isEnabled = true; control.mouseEntered(with: hover)
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        control.performClick(nil); control.mouseEntered(with: hover)
        check(actions == 1 && !control.isHovered && background.animationKeys()?.isEmpty != false, "original key loss cancels state and dispatch")
        window.key = true; control.mouseEntered(with: hover)
        control.isHidden = true; control.viewDidHide(); control.performClick(nil)
        check(actions == 1 && !control.isHovered && !control.isPressed, "hidden controls cannot invoke")
        control.isHidden = false; control.mouseEntered(with: hover)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        check(background.animationKeys()?.isEmpty != false, "appearance-options notification retires in-flight motion")
        control.removeFromSuperview(); control.mouseEntered(with: hover); control.performClick(nil)
        check(actions == 1 && !control.isHovered && ownedAreas().isEmpty, "detach revokes tracking and callback admission")
        host.addSubview(control)
        let unrelated = TrackingEvent()
        control.mouseEntered(with: unrelated)
        check(!control.isHovered, "an event without an attributed area cannot start decoration")
        control.updateTrackingAreas(); control.mouseEntered(with: hover)
        check(!control.isHovered, "old-window tracking does not revive after attach")
        let close = SplitPaneControl(.close)
        check(close.accessibilityLabel() == "Close Split View Pane" && close.parcTooltip?.label == "Remove Tab from Split View" && close.intrinsicContentSize == control.intrinsicContentSize, "close shares style with its distinct action identity")
        let paneA = UUID(), paneB = UUID(), paneC = UUID()
        check(SplitPaneCloseAdmission.accepts(tabID: paneA, selected: [paneA, paneB])
              && SplitPaneCloseAdmission.accepts(tabID: paneB, selected: [paneA, paneB]),
              "each split pane's Close retires that original page")
        check(!SplitPaneCloseAdmission.accepts(tabID: paneC, selected: [paneA, paneB])
              && !SplitPaneCloseAdmission.accepts(tabID: paneA, selected: [paneA])
              && !SplitPaneCloseAdmission.accepts(tabID: paneA, selected: [paneA, paneB], isPeek: true),
              "Close cannot retire a page outside the split, a single page, or Peek")
        let lock = SplitPaneControl(.insecure)
        lock.frame = NSRect(x: 60, y: 20, width: 24, height: 24)
        host.addSubview(lock); lock.layoutSubtreeIfNeeded(); lock.updateTrackingAreas()
        let lockSurface = lock.layer!.sublayers!.first!
        let lockGlyph = lock.subviews.compactMap { $0 as? NSImageView }.first!
        check(lock.intrinsicContentSize == NSSize(width: 24, height: 24) && lockSurface.frame == lock.bounds,
              "original 24-point insecure-lock slot and surface")
        check(lock.accessibilityLabel() == "Site is not secure" && lock.parcTooltip?.label == "Site is not secure"
              && lock.accessibilityHelp() == "Site is not secure" && lock.accessibilityRole() == .button, "original insecure-lock label, tooltip and help")
        check(lockGlyph.contentTintColor == .systemRed, "original red lock foreground at full opacity")
        lock.isEnabled = false
        check(lockGlyph.contentTintColor == .systemRed && lockSurface.opacity == 0,
              "disabled lock keeps its foreground and shows no surface")
        lock.isEnabled = true
        let lockArea = TrackingEvent()
        lockArea.area = lock.trackingAreas.first { $0.owner === lock && $0.options.contains(.inVisibleRect) && !$0.options.contains(.cursorUpdate) }
        lock.appearance = NSAppearance(named: .aqua); lock.viewDidChangeEffectiveAppearance()
        lock.mouseEntered(with: lockArea)
        check(lock.isHovered && abs(lockSurface.opacity - 0.05) < 0.00001, "lock shares the symbol hover surface")
        lock.mouseExited(with: lockArea)
        lockArea.location = lock.convert(NSPoint(x: 12, y: 12), to: nil)
        let cover = NSView(frame: lock.frame.insetBy(dx: -4, dy: -4)); host.addSubview(cover)
        lock.mouseEntered(with: lockArea)
        check(!lock.isHovered && lockSurface.opacity == 0, "a command surface covering the control keeps its hover off")
        let lockMove = NSEvent.mouseEvent(with: .mouseMoved, location: lockArea.location, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        cover.removeFromSuperview(); lock.mouseMoved(with: lockMove)
        check(lock.isHovered && abs(lockSurface.opacity - 0.05) < 0.00001, "moving out from under the cover restores hover")
        lock.mouseExited(with: lockArea)
        let glass = SeeThroughView(frame: cover.frame); host.addSubview(glass)
        lock.mouseEntered(with: lockArea)
        check(lock.isHovered, "a see-through overlay leaves hover alone")
        glass.removeFromSuperview()
        lock.mouseExited(with: lockArea); lock.removeFromSuperview()

        typealias LayoutSkip = SplitPaneControlLayoutSkip
        let skipBounds = NSRect(x: 0, y: 0, width: 32, height: 24)
        let skipSurface = LayoutSkip.surfaceFrame(bounds: skipBounds, surfaceSize: SplitPaneControl.surfaceSize)
        check(LayoutSkip.shouldSkipSurface(current: skipSurface, bounds: skipBounds,
                                           surfaceSize: SplitPaneControl.surfaceSize),
              "Matching centered surface frame skips")
        check(!LayoutSkip.shouldSkipSurface(current: .zero, bounds: skipBounds,
                                            surfaceSize: SplitPaneControl.surfaceSize),
              "Mismatched surface frame does not skip")
        check(LayoutSkip.shouldSkipGlyph(current: skipBounds, bounds: skipBounds),
              "Matching glyph frame skips")
        check(!LayoutSkip.shouldSkipGlyph(current: .zero, bounds: skipBounds),
              "Mismatched glyph frame does not skip")
        let oversized = NSRect(x: 0, y: 0, width: 40, height: 30)
        check(LayoutSkip.surfaceFrame(bounds: oversized, surfaceSize: SplitPaneControl.surfaceSize)
              == NSRect(x: 4, y: 3, width: 32, height: 24),
              "Centered surface stays 32×24 inside a larger control")

        host.addSubview(control)
        func layoutWrites(_ body: () -> Void) -> (surface: Int, glyph: Int) {
            let writes = GeometryWrites.during(body)
            return (writes.filter { $0.object === background && $0.key != "opacity" }.count,
                    writes.filter { $0.object === glyph && $0.key == "frame" }.count)
        }
        control.frame = NSRect(x: 20, y: 20, width: 36, height: 28)
        let first = layoutWrites { control.layoutSubtreeIfNeeded() }
        check(first.surface >= 1 && first.glyph >= 1, "first layout writes surface and glyph")
        let surfaceBefore = background.frame
        let glyphBefore = glyph.frame
        let noOp = layoutWrites { control.layout() }
        check(noOp == (0, 0) && background.frame == surfaceBefore && glyph.frame == glyphBefore,
              "no-op layout skips surface CATransaction and glyph frame write")
        control.setFrameSize(NSSize(width: 40, height: 30))
        let resized = layoutWrites { control.layout() }
        check(resized.surface >= 1 && resized.glyph >= 1
              && background.frame == LayoutSkip.surfaceFrame(bounds: control.bounds, surfaceSize: control.surfaceSize)
              && glyph.frame == control.bounds,
              "a bounds change still rewrites centered surface and glyph")
        check(layoutWrites { control.layout() } == (0, 0), "follow-up layout at the new size remains a no-op")
        control.updateTrackingAreas()
        let skipHover = TrackingEvent()
        skipHover.area = control.trackingAreas.first {
            $0.owner === control && $0.options.contains(.inVisibleRect) && !$0.options.contains(.cursorUpdate)
        }
        control.appearance = NSAppearance(named: .aqua); control.viewDidChangeEffectiveAppearance()
        let hovered = layoutWrites { control.mouseEntered(with: skipHover) }
        check(control.isHovered && abs(background.opacity - 0.05) < 0.00001 && hovered == (0, 0),
              "hover refresh stays ungated by the layout skip")
        control.mouseExited(with: skipHover)
        control.frame = NSRect(x: 20, y: 20, width: 32, height: 24)
        control.layoutSubtreeIfNeeded()
        control.removeFromSuperview()

        weak var retired: SplitPaneControl?
        autoreleasepool {
            let temporary = SplitPaneControl(.menu); retired = temporary; host.addSubview(temporary); temporary.removeFromSuperview()
        }
        check(retired == nil, "notification observers and passive layers do not retain detached control")
        let originalResponder = window.firstResponder
        let pane = FlippedControlHost(frame: NSRect(x: 20, y: 10, width: 120, height: 70))
        host.addSubview(pane)
        var applicationActive = true
        let reveal = PaneControlVisibility(applicationIsActive: { applicationActive })
        var changes: [Bool] = []
        var durations: [TimeInterval?] = []
        reveal.onChange = { changes.append($0); durations.append($1) }
        let bar = NSRect(x: 0, y: 0, width: 120, height: 32)
        check(PaneControlVisibility.hoverRegion(for: bar) == NSRect(x: 0, y: -40, width: 120, height: 100), "original expanded hover region")
        reveal.update(host: pane, bar: bar, focused: false)
        check(!reveal.isRevealed && changes == [false], "unfocused original pane begins essential-only")
        func revealAreas() -> [NSTrackingArea] { host.trackingAreas.filter { $0.owner === reveal } }
        check(revealAreas().count == 1 && revealAreas()[0].options == [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], "passive root tracking covers original parent extent")
        check(revealAreas()[0].rect == host.convert(PaneControlVisibility.hoverRegion(for: bar), from: pane).intersection(host.bounds), "flipped native region converted into actual window content")
        let firstArea = revealAreas()[0]
        window.pointer = pane.convert(NSPoint(x: 60, y: 50), to: nil)
        let enter = TrackingEvent(); enter.area = firstArea
        reveal.mouseEntered(with: enter)
        check(reveal.isHovered && reveal.isRevealed && changes.last == true, "hover below bar reveals background pane options")
        check(durations.last == PaneTopBarFade.hover && PaneTopBarFade.hover == 0.18, "hover reveal uses the original 0.18-second transition")
        check(window.firstResponder === originalResponder, "passive reveal does not select or focus a page")
        window.pointer = pane.convert(NSPoint(x: 60, y: 61), to: nil)
        reveal.mouseExited(with: enter)
        check(!reveal.isHovered && !reveal.isRevealed, "leaving exact original region restores essential-only state")
        reveal.update(host: pane, bar: bar, focused: true)
        check(reveal.isRevealed && !reveal.isHovered, "focused pane needs no hover")
        check(durations.last! == nil, "focus reveal is immediate")
        reveal.update(host: pane, bar: bar, focused: true, obstructed: true)
        check(!reveal.isRevealed && durations.last == PaneTopBarFade.obstruction && PaneTopBarFade.obstruction == 0.17,
              "a presented modal hides even the focused pane's menu with the original 0.17-second transition")
        reveal.update(host: pane, bar: bar, focused: true, obstructed: false)
        check(reveal.isRevealed && durations.last == PaneTopBarFade.obstruction, "modal retirement restores the menu")
        reveal.update(host: pane, bar: bar, focused: false)
        reveal.trackMenu {
            check(reveal.isRevealed, "actual menu tracking retains its original control")
            reveal.trackMenu { check(reveal.isRevealed, "nested synchronous tracking retains the original presentation") }
            check(reveal.isRevealed, "inner completion does not retire outer menu")
        }
        check(!reveal.isRevealed, "menu completion samples current original pointer")
        pane.frame.origin.x += 5
        reveal.update(host: pane, bar: bar, focused: false)
        window.pointer = pane.convert(NSPoint(x: 60, y: 20), to: nil)
        reveal.mouseEntered(with: enter)
        check(!reveal.isRevealed, "obsolete geometry event cannot reveal a new region")
        let current = TrackingEvent(); current.area = revealAreas()[0]
        reveal.mouseEntered(with: current)
        check(reveal.isRevealed, "current geometry accepts actual pointer")
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        reveal.mouseEntered(with: current)
        check(!reveal.isRevealed && !reveal.isHovered, "original key loss retires hover")
        window.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        check(reveal.isRevealed, "key return resamples original window pointer")
        applicationActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        reveal.mouseEntered(with: current)
        check(!reveal.isHovered && !reveal.isRevealed, "application resignation clears and refuses hover even if native key lags")
        applicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        check(reveal.isRevealed, "original application activation samples current pointer")
        pane.isHidden = true
        reveal.update(host: pane, bar: bar, focused: false)
        reveal.mouseEntered(with: current)
        check(!reveal.isRevealed && revealAreas().isEmpty, "hidden original pane releases root tracking")
        pane.isHidden = false; reveal.update(host: pane, bar: bar, focused: false)
        check(reveal.isRevealed, "revealed pane samples pointer without synthetic input")
        let paneMove = TrackingEvent(); paneMove.area = revealAreas()[0]; paneMove.eventWindow = window
        let paneCover = NSView(frame: pane.frame); host.addSubview(paneCover)
        reveal.mouseMoved(with: paneMove)
        check(!reveal.isHovered && !reveal.isRevealed, "moving onto a command surface over a background pane's top hides its options")
        paneCover.removeFromSuperview(); reveal.mouseMoved(with: paneMove)
        check(reveal.isRevealed, "moving out from under the cover reveals the pane's options again")
        let paneGlass = SeeThroughView(frame: pane.frame); host.addSubview(paneGlass)
        reveal.mouseMoved(with: paneMove)
        check(reveal.isRevealed, "a see-through overlay leaves the pane's hover reveal alone")
        paneGlass.removeFromSuperview()
        reveal.invalidate(); reveal.mouseEntered(with: current)
        check(!reveal.isRevealed && revealAreas().isEmpty, "retirement invalidates old original area")
        weak var retiredReveal: PaneControlVisibility?
        autoreleasepool {
            let temporary = PaneControlVisibility(applicationIsActive: { true }); retiredReveal = temporary
            temporary.update(host: pane, bar: bar, focused: false)
        }
        check(retiredReveal == nil && host.trackingAreas.allSatisfy { !($0.owner is PaneControlVisibility) }, "root tracking and weak observers do not retain released owner")
        window.close()
        print("\(checks) Split control presentation assertions passed")
    }
}
