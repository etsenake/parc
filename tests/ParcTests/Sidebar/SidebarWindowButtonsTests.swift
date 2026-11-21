import AppKit
import Testing
@testable import Parc

private final class FlippedHost: NSView { override var isFlipped: Bool { true } }

private final class PointerWindow: NSWindow {
    var pointer = NSPoint(x: -100, y: -100)
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

private final class ClosingWindow: NSWindow {
    var closes = 0
    override func close() {
        closes += 1
        super.close()
    }
}

@MainActor
struct SidebarWindowButtonsTests {
    typealias W = WindowStandardButtons
    private static let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    private var isAtLeast26: Bool { ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) }

    @MainActor private final class Lights {
        let main: NSWindow
        let lights = W()
        let sidebar = FlippedHost(frame: NSRect(x: 0, y: 0, width: 228, height: 600))
        let systemButtons: [NSButton]

        init() {
            main = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: SidebarWindowButtonsTests.style, backing: .buffered, defer: false)
            main.isReleasedWhenClosed = false
            main.titleVisibility = .hidden
            main.titlebarAppearsTransparent = true
            main.contentView?.wantsLayer = true
            main.standardWindowButton(.zoomButton)?.isEnabled = false
            systemButtons = W.systemButtons(of: main)
            main.contentView?.addSubview(sidebar)
            sidebar.addSubview(lights)
        }

        deinit { MainActor.assumeIsolated { main.close() } }

        var made: [NSButton] { lights.buttons }
        var overlays: [NSView] { lights.subviews.filter { !($0 is NSButton) } }

        static func subroles(_ buttons: [NSButton]) -> [NSAccessibility.Subrole?] {
            buttons.map { (NSAccessibility.unignoredDescendant(of: $0) as? NSCell)?.accessibilitySubrole() }
        }
    }

    @Test func theButtonsAreFourteenPointsWithTheRecoveredSpacing() {
        #expect(W.buttonDimension == 14)
        #expect(W.buttonSpace == (isAtLeast26 ? 9 : 6))
    }

    @Test func theStackSizeIsThreeButtonsAndTwoSpacings() {
        #expect(W.stackSize == CGSize(width: isAtLeast26 ? 60 : 54, height: 14))
    }

    @Test func beforeAWindowTheSizeIsTheFormulas() {
        let lights = W()
        #expect(lights.buttons.isEmpty)
        #expect(lights.frame.size == W.stackSize)
    }

    @Test func theWindowsOwnButtonsAreCaptured() {
        #expect(Lights().systemButtons.count == 3)
    }

    @Test func closeMinimizeAndZoomAreCreatedWhenTheViewMovesToAWindow() {
        #expect(Lights().made.count == 3)
    }

    @Test func theyAreTheSameWidgetClassesAsTheWindowsOwnButNewInstances() {
        let l = Lights()
        #expect(zip(l.made, l.systemButtons).allSatisfy { type(of: $0) == type(of: $1) && $0 !== $1 })
    }

    @Test func theyAreDirectChildrenKeepingAppKitsOwnActions() {
        let l = Lights()
        #expect(l.made.allSatisfy { $0.superview === l.lights && $0.target == nil && $0.action != nil })
    }

    @Test func enabledStateIsCopiedFromTheWindowsOwnButtons() {
        let l = Lights()
        #expect(l.made[0].isEnabled)
        #expect(l.made[1].isEnabled)
        #expect(!l.made[2].isEnabled)
    }

    @Test(arguments: [0, 1, 2])
    func subrolesMatchTheWindowsOwnForEachCollectionBehavior(variant: Int) {
        let l = Lights()
        let initial = l.main.collectionBehavior
        l.main.collectionBehavior = [initial, initial.union(.fullScreenNone), initial.union(.fullScreenPrimary)][variant]
        let mine = Lights.subroles(l.made)
        #expect(mine == Lights.subroles(l.systemButtons))
        #expect(mine.prefix(2) == [.closeButton, .minimizeButton])
    }

    @Test func aWindowThatCannotGoFullScreenExposesAXZoomButton() {
        let l = Lights()
        l.main.collectionBehavior = l.main.collectionBehavior.union(.fullScreenNone)
        #expect(Lights.subroles(l.made).last == .zoomButton)
    }

    @Test func aFullScreenPrimaryWindowExposesAXFullScreenButton() {
        let l = Lights()
        l.main.collectionBehavior = l.main.collectionBehavior.union(.fullScreenPrimary)
        #expect(Lights.subroles(l.made).last == .fullScreenButton)
    }

    @Test func theButtonsAreMadeOnce() {
        let l = Lights()
        let made = l.made
        l.lights.removeFromSuperview()
        l.sidebar.addSubview(l.lights)
        #expect(l.lights.buttons.count == 3)
        #expect(zip(l.lights.buttons, made).allSatisfy { $0 === $1 })
    }

    private var bar: SidebarChromeLayout.Toolbar {
        SidebarChromeLayout.toolbar(width: 228, windowButtons: W.stackSize, showsNavigation: true)
    }

    @Test func theLightsSitAtThirteenCentredInTheRow() {
        #expect(bar.windowButtons == CGRect(x: 13, y: 17, width: W.stackSize.width, height: 14))
    }

    @Test func theToggleSitsFourPointsAfterTheLightsAndLevelWithThem() {
        #expect(bar.toggle?.minX == (isAtLeast26 ? 77 : 71))
        #expect(bar.windowButtons?.midY == bar.toggle?.midY)
    }

    private func laidOut() -> Lights {
        let l = Lights()
        l.lights.frame = bar.windowButtons ?? .zero
        l.lights.layoutSubtreeIfNeeded()
        return l
    }

    @Test func fourteenPointButtonsAreTwentyThreeApartOnMacOSTwentySixAndLater() {
        let l = laidOut()
        let pitch = W.buttonDimension + W.buttonSpace
        #expect(!isAtLeast26 || l.made.map(\.frame) == (0..<3).map { NSRect(x: CGFloat($0) * pitch, y: 0, width: 14, height: 14) })
    }

    @Test func eachButtonIsCentredOnItsSlot() {
        let l = laidOut()
        let pitch = W.buttonDimension + W.buttonSpace
        #expect(l.made.enumerated().allSatisfy { abs($1.frame.midX - (CGFloat($0) * pitch + 7)) < 0.001 && abs($1.frame.midY - 7) < 0.001 })
    }

    @Test func oneOverlayTwoPointsSmallerSitsOverEachButton() {
        let l = laidOut()
        #expect(l.overlays.count == 3)
        #expect(zip(l.overlays, l.made).allSatisfy { $0.frame == $1.frame.insetBy(dx: 1, dy: 1) })
    }

    @Test func overlaysNeverTakeTheClick() {
        let l = laidOut()
        #expect(l.overlays.allSatisfy { $0.hitTest(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) == nil })
    }

    @Test func theMinimizeWidgetReceivesItsClick() {
        let l = laidOut()
        let point = l.lights.convert(NSPoint(x: l.made[1].frame.midX, y: l.made[1].frame.midY), to: l.lights.superview)
        #expect(l.lights.hitTest(point) === l.made[1])
    }

    @Test func theViewAnswersMouseInGroup() {
        #expect(Lights().lights.responds(to: NSSelectorFromString("_mouseInGroup:")))
    }

    @MainActor private final class Answers {
        var all: [Bool] = []
    }

    private func answers(drawing button: NSView, in l: Lights) -> [Bool] {
        let answers = Answers()
        l.lights.onGroupQuery = { answers.all.append($0) }
        button.needsDisplay = true
        button.needsLayout = true
        let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
        button.cacheDisplay(in: button.bounds, to: rep)
        l.lights.onGroupQuery = nil
        return answers.all
    }

    @Test func drawnWidgetsAskTheLightsWhetherTheGroupIsHovered() {
        let l = laidOut()
        let asked = answers(drawing: l.made[0], in: l)
        #expect(!asked.isEmpty)
        #expect(!asked.contains(true))
    }

    @Test func afterAHoverChangeTheWidgetsAreAnsweredTrue() {
        let l = laidOut()
        l.lights.setMouseInside(true)
        let asked = answers(drawing: l.made[0], in: l)
        #expect(!asked.isEmpty)
        #expect(asked.allSatisfy { $0 })
    }

    @Test func aWidgetFindsTheLightsAcrossAnIntermediateView() {
        let l = laidOut()
        let intermediate = NSView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        let nested = NSWindow.standardWindowButton(.closeButton, for: SidebarWindowButtonsTests.style)!
        intermediate.addSubview(nested)
        l.lights.addSubview(intermediate)
        #expect(!answers(drawing: nested, in: l).isEmpty)
    }

    @MainActor private final class Returning {
        let window = PointerWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100), styleMask: [.borderless],
                                   backing: .buffered, defer: true)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let lights = W()

        init() {
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host)
            host.addSubview(lights)
            lights.frame.origin = .zero
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func pointAtLights() { window.pointer = lights.convert(NSPoint(x: 5, y: 5), to: nil) }
    }

    @Test func aHeaderLeavingUnderThePointerDropsItsHover() {
        let r = Returning()
        r.pointAtLights()
        r.lights.setMouseInside(true)
        r.lights.setPresented(false)
        #expect(!r.lights.mouseInside)
    }

    @Test func itsReturnUnderThePointerHoversItAgain() {
        let r = Returning()
        r.pointAtLights()
        r.lights.setPresented(false)
        r.lights.setPresented(true)
        #expect(r.lights.mouseInside)
    }

    @Test func itsReturnAwayFromThePointerDoesNotHoverIt() {
        let r = Returning()
        r.lights.setMouseInside(true)
        r.lights.setPresented(false)
        r.lights.setPresented(true)
        #expect(!r.lights.mouseInside)
    }

    @Test func closeActsOnItsOwnWindowWhenNoWindowIsKey() {
        func window() -> ClosingWindow {
            let window = ClosingWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600),
                                       styleMask: SidebarWindowButtonsTests.style, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            return window
        }
        let other = window()
        let closing = window()
        let lights = W()
        closing.contentView?.addSubview(lights)
        #expect(!closing.isKeyWindow)
        #expect(!other.isKeyWindow)
        lights.buttons[0].performClick(nil)
        #expect(closing.closes == 1)
        #expect(other.closes == 0)
    }

    private func inGroup(_ l: Lights) -> Bool { l.lights.mouseInGroup(l.made[0]) }

    @Test func notHoveredInAquaTheLightsDimToPointOne() {
        let l = laidOut()
        l.lights.appearance = NSAppearance(named: .aqua)
        l.lights.displayIfNeeded()
        #expect(!inGroup(l))
        #expect(abs(l.lights.alphaValue - 0.1) < 0.0001)
    }

    @Test func roundOverlaysShowWhileDimmed() {
        let l = laidOut()
        l.lights.appearance = NSAppearance(named: .aqua)
        l.lights.displayIfNeeded()
        #expect(l.overlays.allSatisfy { !$0.isHidden && $0.layer?.cornerRadius == $0.bounds.height / 2 })
    }

    @Test func dimmedWindowControlsAreBlackInAqua() {
        let l = laidOut()
        l.lights.appearance = NSAppearance(named: .aqua)
        l.lights.displayIfNeeded()
        l.overlays.forEach { $0.displayIfNeeded() }
        #expect(l.overlays.first?.layer?.backgroundColor == CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    }

    @Test func notHoveredInDarkAquaTheLightsDimToPointThirtyThree() {
        let l = laidOut()
        l.lights.appearance = NSAppearance(named: .darkAqua)
        l.lights.displayIfNeeded()
        #expect(abs(l.lights.alphaValue - 0.33) < 0.0001)
    }

    @Test func theDarkAquaOverlayColour() {
        let l = laidOut()
        l.lights.appearance = NSAppearance(named: .darkAqua)
        l.lights.displayIfNeeded()
        l.overlays.forEach { $0.displayIfNeeded() }
        #expect(l.overlays.first?.layer?.backgroundColor == CGColor(srgbRed: 0.953, green: 0.953, blue: 0.918, alpha: 1))
    }

    @Test func hoveredTheGlyphsShowTogetherAtFullAlphaWithNoOverlays() {
        let l = laidOut()
        l.lights.appearance = NSAppearance(named: .darkAqua)
        l.lights.setMouseInside(true)
        l.lights.displayIfNeeded()
        #expect(inGroup(l))
        #expect(l.lights.alphaValue == 1)
        #expect(l.overlays.allSatisfy { $0.isHidden })
    }

    @Test func aHiddenHeaderDropsItsHover() {
        let l = laidOut()
        l.lights.setMouseInside(true)
        l.lights.isHidden = true
        #expect(!l.lights.mouseInside)
    }

    @Test func reShownAwayFromThePointerItDimsAgain() {
        let l = laidOut()
        l.lights.setMouseInside(true)
        l.lights.isHidden = true
        l.lights.isHidden = false
        #expect(!l.lights.mouseInside)
        #expect(l.overlays.allSatisfy { !$0.isHidden })
    }

    @Test func aHeaderLeavingWithAnUnhiddenSidebarDropsItsHover() {
        let l = laidOut()
        l.lights.setMouseInside(true)
        l.lights.setPresented(false)
        #expect(!l.lights.mouseInside)
        #expect(!l.lights.isHiddenOrHasHiddenAncestor)
    }

    typealias P = WindowFullscreenPhase

    private static let phases: [(phase: P?, sidebarless: Bool, system: Bool, header: Bool)] = [
        (nil, false, false, true), (.entering, false, false, false), (.expanded, false, true, false), (.exiting, false, false, true),
        (nil, true, true, true), (.entering, true, false, false), (.expanded, true, true, false), (.exiting, true, false, true)]

    @Test(arguments: 0..<8)
    func theFullscreenPhaseRuleShowsExactlyTheRightLights(index: Int) {
        let l = laidOut()
        let (phase, sidebarless, system, header) = Self.phases[index]
        let shows = P.apply(phase, sidebarless: sidebarless, system: l.systemButtons)
        #expect(l.systemButtons.allSatisfy { $0.isHidden == !system && $0.window === l.main })
        #expect(shows == header)
    }

    @Test(arguments: 0..<8)
    func theHeaderDropsItsLightsAndTheToggleLeadsAtThirteenWithoutThem(index: Int) {
        let l = laidOut()
        let (phase, sidebarless, _, header) = Self.phases[index]
        let shows = P.apply(phase, sidebarless: sidebarless, system: l.systemButtons)
        let row = SidebarChromeLayout.toolbar(width: 228, windowButtons: shows ? W.stackSize : nil, showsNavigation: true)
        #expect((row.windowButtons != nil) == header)
        #expect(row.toggle?.minX == (header ? bar.toggle?.minX : 13))
        #expect(l.made.allSatisfy { !$0.isHidden })
    }

    @Test func aFullScreenStyleMaskWithoutDelegateCallbacksCountsAsExpanded() {
        #expect(P.current(nil, inFullScreen: false) == nil)
        #expect(P.current(nil, inFullScreen: true) == .expanded)
    }

    @Test func leavingWithoutDidExitAndTransitionsReconcile() {
        #expect(P.current(.expanded, inFullScreen: false) == nil)
        #expect(P.current(.entering, inFullScreen: false) == .entering)
        #expect(P.current(.exiting, inFullScreen: true) == .exiting)
    }

    @Test func theWindowsOwnLightsShowInPlaceOfTheHeadersInFullScreen() {
        let l = laidOut()
        #expect(P.apply(P.current(nil, inFullScreen: true), sidebarless: false, system: l.systemButtons) == false)
        #expect(l.systemButtons.allSatisfy { !$0.isHidden })
    }

    @Test(arguments: [nil, P.entering, .expanded, .exiting] as [P?])
    func exactlyOneSetOfTrafficLightsExceptWhileEntering(phase: P?) {
        #expect(P.showsSystemButtons(phase, sidebarless: false) != P.showsSidebarButtons(phase) || phase == .entering)
    }

    @Test func standardWindowButtonAnswersWithTheContentWidget() {
        let l = laidOut()
        _ = P.apply(nil, sidebarless: false, system: l.systemButtons)
        #expect(l.main.standardWindowButton(.closeButton) === l.made[0])
    }

    @Test func soItsEnabledStateMustMatchTheWindowsOwn() {
        #expect(Lights().main.standardWindowButton(.zoomButton)?.isEnabled == false)
    }
}
