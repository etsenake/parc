import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarNewTabRowTests {
    @MainActor private final class NewTab {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow
        let state = BrowserState.initial()
        var rendered: BrowserState
        var opened = 0

        static func tab(_ name: String, _ kind: TabKind, _ space: BrowserSpace) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                              kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }

        init() {
            window = sidebarTestWindow(containing: sidebar)
            window.applicationActive = true
            window.pointer = NSPoint(x: -100, y: -100)
            var base = state
            let space = base.spaces[0]
            base.tabs = [Self.tab("pinned", .pinned, space), Self.tab("today", .today, space), Self.tab("later", .today, space)]
            rendered = base
            sidebar.onNewTab = { [weak self] in self?.opened += 1 }
            render(base)
        }

        deinit {
            MainActor.assumeIsolated { window.contentView = nil }
        }

        func render(_ state: BrowserState) {
            rendered = state
            sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }

        var row: SidebarNewTabRow { sidebarDescendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first! }
        var plate: SidebarRowBackgroundView { sidebarDescendants(row).compactMap { $0 as? SidebarRowBackgroundView }.first! }
        var icon: NSImageView { sidebarDescendants(row).compactMap { $0 as? NSImageView }.first! }
        var title: SidebarChromeLabel { sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first! }
        var slot: NSRect { SidebarRowAppearance.iconSlotFrame(in: row.bounds) }
        var span: (minX: CGFloat, width: CGFloat) {
            let s = SidebarRowAppearance.titleLabelSpan(resettable: false,
                                                        trailing: SidebarRowAppearance.titleTrailingEdge(in: row.bounds, closeVisible: false))
            return (s.minX, s.width)
        }

        func centre(of view: NSView) -> NSPoint { view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) }

        func post(_ name: Notification.Name) { NotificationCenter.default.post(name: name, object: window) }

        func bounce() -> CASpringAnimation? { row.layer?.animation(forKey: SidebarNewTabRow.bounceKey) as? CASpringAnimation }
    }

    @Test func newTabTakesATabsWholeVisibleRow() {
        let n = NewTab()
        let tab = sidebarDescendants(n.sidebar).compactMap { $0 as? SidebarTabRow }.first!
        #expect(n.row.bounds.size == NSSize(width: tab.bounds.width, height: SidebarChromeLayout.tablistVisibleRowHeight))
        #expect(n.row.convert(n.row.bounds, to: n.sidebar).minX == tab.convert(tab.bounds, to: n.sidebar).minX)
    }

    @Test func thePlusIsCentredInTheFaviconColumn() {
        let n = NewTab()
        #expect(n.icon.image === SidebarNewTabAppearance.plus)
        #expect(abs(n.icon.frame.midX - n.slot.midX) < 0.01)
        #expect(abs(n.icon.frame.midY - n.slot.midY) < 0.01)
    }

    @Test func theTitleIsTheTabTitlesFourteenPointLabelAtItsInset() {
        let n = NewTab()
        #expect(n.title.frame == NSRect(x: n.span.minX, y: ((n.row.bounds.height - 18) / 2).rounded(.down), width: n.span.width, height: 18))
        #expect(n.title.stringValue == "New Tab")
        #expect(n.title.font == .systemFont(ofSize: SidebarRowAppearance.titleFontSize))
    }

    @Test func theTitleIsSidebarForegroundAndThePlusForegroundSecondary() {
        let n = NewTab()
        #expect(n.title.textColor == SidebarNewTabAppearance.titleColor(dark: n.row.dark))
        #expect(n.title.alphaValue == 1)
        #expect(n.icon.contentTintColor == SidebarNewTabAppearance.plusColor(dark: n.row.dark))
    }

    @Test func bothFollowTheThemesDarkness() {
        let n = NewTab()
        n.row.dark.toggle()
        #expect(n.title.textColor == SidebarNewTabAppearance.titleColor(dark: n.row.dark))
        #expect(n.icon.contentTintColor == SidebarNewTabAppearance.plusColor(dark: n.row.dark))
    }

    @Test func voiceOverReadsOneNewTabButton() {
        let n = NewTab()
        #expect(!n.icon.isAccessibilityElement())
        #expect(!n.title.isAccessibilityElement())
        #expect(n.row.button.accessibilityLabel() == "New Tab")
    }

    @Test func theNewTabCellInstallsNoTooltip() {
        let n = NewTab()
        #expect(n.row.button.toolTip == nil)
        #expect(n.row.toolTip == nil)
        #expect(n.row.button.parcTooltip == nil)
        #expect(n.row.parcTooltip == nil)
    }

    @Test func theWholeRowIsTheButton() {
        let n = NewTab()
        #expect(n.row.hitTest(n.row.convert(NSPoint(x: n.span.minX + 4, y: n.row.bounds.midY), to: n.row.superview)) === n.row.button)
        #expect(n.row.hitTest(n.row.convert(NSPoint(x: n.slot.midX, y: n.row.bounds.midY), to: n.row.superview)) === n.row.button)
    }

    @Test func newTabOpensATab() {
        let n = NewTab()
        n.row.button.sendAction(n.row.button.action, to: n.row.button.target)
        #expect(n.opened == 1)
    }

    @Test func atRestThePlateIsClear() {
        let n = NewTab()
        #expect(n.plate.frame == n.row.bounds)
        #expect(n.plate.appearanceState.fill == nil)
    }

    @Test func hoveringFillsTheRowWithSidebarItemBackgroundInTwelvePointContinuousCorners() {
        let n = NewTab()
        n.row.button.mouseEntered(with: SidebarAreaEvent())
        let fill = SidebarRowAppearance.color(.hovered, dark: n.plate.dark).cgColor
        #expect(n.plate.appearanceState.fill == .hovered)
        #expect(n.plate.fillLayer.backgroundColor.map { CFEqual($0, fill) } == true)
        #expect(n.plate.fillLayer.cornerRadius == SidebarRowAppearance.cornerRadius)
        #expect(n.plate.fillLayer.cornerCurve == .continuous)
    }

    @Test func leavingClearsThePlate() {
        let n = NewTab()
        n.row.button.mouseEntered(with: SidebarAreaEvent())
        n.row.button.mouseExited(with: SidebarAreaEvent())
        #expect(n.plate.appearanceState.fill == nil)
    }

    @Test func thePointerOnNewTabLightsThePlate() {
        let n = NewTab()
        n.window.pointer = n.centre(of: n.row)
        n.row.button.mouseEntered(with: SidebarAreaEvent())
        #expect(n.plate.appearanceState.fill == .hovered)
    }

    @Test func theWindowResigningKeyClearsThePlateWithoutAnExit() {
        let n = NewTab()
        n.window.pointer = n.centre(of: n.row)
        n.row.button.mouseEntered(with: SidebarAreaEvent())
        n.window.key = false
        n.post(NSWindow.didResignKeyNotification)
        #expect(n.plate.appearanceState.fill == nil)
    }

    @Test func takingKeyAgainUnderThePointerRelightsIt() {
        let n = NewTab()
        n.window.pointer = n.centre(of: n.row)
        n.row.button.mouseEntered(with: SidebarAreaEvent())
        n.window.key = false
        n.post(NSWindow.didResignKeyNotification)
        n.window.key = true
        n.post(NSWindow.didBecomeKeyNotification)
        #expect(n.plate.appearanceState.fill == .hovered)
    }

    @Test func takingKeyWithThePointerGoneLeavesThePlateClear() {
        let n = NewTab()
        n.window.pointer = n.centre(of: n.row)
        n.row.button.mouseEntered(with: SidebarAreaEvent())
        n.window.key = false
        n.post(NSWindow.didResignKeyNotification)
        n.window.pointer = NSPoint(x: -100, y: -100)
        n.window.key = true
        n.post(NSWindow.didBecomeKeyNotification)
        #expect(n.plate.appearanceState.fill == nil)
        #expect(!n.row.button.hovered)
    }

    private func todayless(_ n: NewTab) -> BrowserState {
        var state = n.rendered
        state.tabs = state.tabs.filter { $0.kind == .pinned }
        return state
    }

    @Test func rendersKeepTheOneNewTabRow() {
        let n = NewTab()
        let row = n.row
        n.render(todayless(n))
        #expect(n.row === row)
    }

    @Test func withTodayTheRowSitsBelowTheStillPointer() {
        let n = NewTab()
        let withToday = n.rendered
        n.render(todayless(n))
        let emptyTodayPlace = n.centre(of: n.row)
        n.render(withToday)
        n.window.pointer = emptyTodayPlace
        n.sidebar.layoutSubtreeIfNeeded()
        #expect(n.centre(of: n.row) != emptyTodayPlace)
        #expect(n.plate.appearanceState.fill == nil)
    }

    @Test func emptyingTodayMovesNewTabUnderThePointerAndLightsItsPlate() {
        let n = NewTab()
        let withToday = n.rendered
        n.render(todayless(n))
        let emptyTodayPlace = n.centre(of: n.row)
        n.render(withToday)
        n.window.pointer = emptyTodayPlace
        n.sidebar.layoutSubtreeIfNeeded()
        n.render(todayless(n))
        #expect(n.centre(of: n.row) == emptyTodayPlace)
        #expect(n.plate.appearanceState.fill == .hovered)
    }

    private func pressed(_ n: NewTab) -> (CASpringAnimation?, CATransform3D?) {
        n.row.button.highlight(true)
        let press = n.bounce()
        return (press, (press?.toValue as? NSValue)?.caTransform3DValue)
    }

    private func springsBack(_ spring: CASpringAnimation?) -> Bool {
        spring?.isRemovedOnCompletion == true && (spring?.toValue as? NSValue).map { CATransform3DIsIdentity($0.caTransform3DValue) } == true
    }

    @Test func aPressSpringsTheRowToItsPressedScaleAboutItsCentreAndHoldsIt() {
        let n = NewTab()
        let (press, transform) = pressed(n)
        let squeeze = 1 - SidebarNewTabRow.pressScale
        #expect(press?.keyPath == "transform")
        #expect(press?.isRemovedOnCompletion == false)
        #expect(press?.fillMode == .forwards)
        #expect(transform?.m11 == 0.992)
        #expect(transform?.m22 == 0.992)
        #expect(transform?.m33 == 1)
        #expect(abs((transform?.m41 ?? 0) - squeeze * n.row.bounds.midX) < 1e-9)
        #expect(abs((transform?.m42 ?? 0) - squeeze * n.row.bounds.midY) < 1e-9)
    }

    @Test func theSpringHasDampingRatioHalfAndResponseTwoTenthsAndLastsItsSettlingTime() {
        let n = NewTab()
        let (press, _) = pressed(n)
        #expect(press?.mass == 1)
        #expect(abs((press?.stiffness ?? 0) - pow(2 * .pi / 0.2, 2)) < 1e-9)
        #expect(abs((press?.damping ?? 0) - 4 * .pi * 0.5 / 0.2) < 1e-9)
        #expect(press?.duration == press?.settlingDuration)
    }

    @Test func aPressThatStaysDownKeepsItsOneSpring() {
        let n = NewTab()
        let (press, _) = pressed(n)
        n.row.button.highlight(true)
        #expect(n.bounce() === press)
    }

    @Test func draggingOffTheRowSpringsItBackToFullSize() {
        let n = NewTab()
        let (press, _) = pressed(n)
        n.row.button.highlight(false)
        let dragOff = n.bounce()
        #expect(dragOff !== press)
        #expect(springsBack(dragOff))
    }

    @Test func draggingBackOntoTheRowPressesItAgain() {
        let n = NewTab()
        let (_, pressedTransform) = pressed(n)
        n.row.button.highlight(false)
        let dragOff = n.bounce()
        n.row.button.highlight(true)
        let dragBack = n.bounce()
        #expect(dragBack !== dragOff)
        #expect(dragBack?.isRemovedOnCompletion == false)
        #expect((dragBack?.toValue as? NSValue).map { CATransform3DEqualToTransform($0.caTransform3DValue, pressedTransform ?? CATransform3DIdentity) } == true)
    }

    @Test func aClickReleasedOutsideTheRowReturnsItToFullSize() {
        let n = NewTab()
        _ = pressed(n)
        n.row.button.highlight(false)
        let dragOff = n.bounce()
        n.row.button.highlight(true)
        let dragBack = n.bounce()
        n.row.button.highlight(false)
        let cancelled = n.bounce()
        #expect(cancelled !== dragBack)
        #expect(dragOff !== cancelled)
        #expect(springsBack(cancelled))
    }

    @Test func aRepeatedReleaseLeavesTheSpringBackRunning() {
        let n = NewTab()
        _ = pressed(n)
        n.row.button.highlight(false)
        let released = n.bounce()
        n.row.button.highlight(false)
        #expect(n.bounce() === released)
    }

    @Test func aClickSpringsTheRowBackAsTheButtonLetsGo() {
        let n = NewTab()
        let (clicked, _) = pressed(n)
        n.row.button.highlight(false)
        #expect(clicked?.isRemovedOnCompletion == false)
        #expect(springsBack(n.bounce()))
    }

    @Test func newTabsActionKeepsTheSpringBackTheReleaseStarted() {
        let n = NewTab()
        _ = pressed(n)
        n.row.button.highlight(false)
        let release = n.bounce()
        #expect(n.row.button.sendAction(n.row.button.action, to: n.row.button.target))
        #expect(n.bounce() === release)
    }

    @Test func aHeldPressFollowsTheRowsCentreWhenTheSidebarResizesWithoutMoving() {
        let n = NewTab()
        _ = pressed(n)
        let squeeze = 1 - SidebarNewTabRow.pressScale
        let held = n.row.frame.size
        n.row.setFrameSize(NSSize(width: held.width + 100, height: held.height))
        n.row.layoutSubtreeIfNeeded()
        let moved = (n.bounce()?.toValue as? NSValue)?.caTransform3DValue
        #expect(n.bounce()?.isRemovedOnCompletion == false)
        #expect((n.bounce()?.fromValue as? NSValue)?.caTransform3DValue.m41 == moved?.m41)
        #expect(abs((moved?.m41 ?? 0) - squeeze * n.row.bounds.midX) < 1e-9)
    }

    @Test func anotherSpaceShowsItsNewTabUnpressed() {
        let n = NewTab()
        _ = pressed(n)
        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "star.fill", color: "CC3333", profileID: n.state.spaces[0].profileID)
        var elsewhere = n.rendered
        elsewhere.spaces.append(other)
        elsewhere.activeSpaceID = other.id
        n.sidebar.render(state: elsewhere, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        #expect(n.bounce() == nil)
    }

    @Test func theNextPressSpringsInAgain() {
        let n = NewTab()
        let (press, _) = pressed(n)
        n.row.button.highlight(false)
        n.row.button.highlight(true)
        let repressed = n.bounce()
        #expect(repressed !== press)
        #expect(repressed?.isRemovedOnCompletion == false)
    }

    @Test func aCompletedClickSpringsTheRowBackToIdentityAndNeverChangesTheLayersOwnTransform() {
        let n = NewTab()
        _ = pressed(n)
        let repressed = n.bounce()
        #expect(n.row.button.sendAction(n.row.button.action, to: n.row.button.target))
        let release = n.bounce()
        #expect(release !== repressed)
        #expect(release?.isRemovedOnCompletion == true)
        #expect((release?.toValue as? NSValue).map { CATransform3DIsIdentity($0.caTransform3DValue) } == true)
        #expect(n.row.layer.map { CATransform3DIsIdentity($0.transform) } == true)
    }

    @Test func theTabAClickOpensReRendersTheListWithoutCuttingTheReleaseBounceOff() {
        let n = NewTab()
        _ = pressed(n)
        _ = n.row.button.sendAction(n.row.button.action, to: n.row.button.target)
        let release = n.bounce()
        let row = n.row
        n.render(n.rendered)
        #expect(n.row === row)
        #expect(n.bounce() === release)
    }
}
