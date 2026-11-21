import AppKit
import Testing
@testable import Parc

struct ExtensionPopupPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private var window: CGRect { screen }
    private let tall = CGSize(width: 600, height: 510)
    private let popup = CGSize(width: 600, height: 400)
    private var gap: CGFloat { ExtensionPopupPlacement.gap }

    private func frame(_ origin: CGPoint, _ size: CGSize) -> CGRect {
        CGRect(origin: origin, size: size)
    }

    @Test func sidebarPopupFitsBelowTheURLBar() {
        let pill = CGRect(x: 8, y: 860, width: 224, height: 34)
        let sidebarButton = CGRect(x: 150, y: 863, width: 28, height: 28)
        let fromSidebar = frame(ExtensionPopupPlacement.origin(size: popup, control: sidebarButton, bar: pill,
                                                               window: window, screen: screen), popup)
        #expect(!fromSidebar.intersects(pill))
        #expect(fromSidebar.maxY == pill.minY - gap)
        #expect(fromSidebar.minX == window.minX + ExtensionPopupPlacement.margin && fromSidebar.maxX > sidebarButton.maxX)
    }

    @Test func splitPanePopupsStayWithTheirOwnToolbar() {
        let split = window.midY
        let topBar = CGRect(x: 248, y: 904, width: 1256, height: 32)
        let topButton = CGRect(x: 1400, y: 908, width: 32, height: 24)
        let bottomBar = CGRect(x: 248, y: split - 36, width: 1256, height: 32)
        let bottomButton = CGRect(x: 1400, y: split - 32, width: 32, height: 24)
        let top = frame(ExtensionPopupPlacement.origin(size: popup, control: topButton, bar: topBar,
                                                       window: window, screen: screen), popup)
        let bottom = frame(ExtensionPopupPlacement.origin(size: popup, control: bottomButton, bar: bottomBar,
                                                          window: window, screen: screen), popup)
        #expect(top.maxY == topBar.minY - gap)
        #expect(top.minY > bottomBar.maxY)
        #expect(bottom.maxY == bottomBar.minY - gap)
        #expect(bottom.maxY < split)
    }

    @Test func thePopupFlipsAboveAToolbarWithoutRoomBelow() {
        let shortBar = CGRect(x: 248, y: 260, width: 1256, height: 32)
        let shortButton = CGRect(x: 1400, y: 264, width: 32, height: 24)
        let flipped = frame(ExtensionPopupPlacement.origin(size: popup, control: shortButton, bar: shortBar,
                                                           window: window, screen: screen), popup)
        #expect(flipped.minY == shortBar.maxY + gap && flipped.maxX == shortButton.maxX)
    }

    @Test func aTallPopupOpensBesideTheSidebarWhenNeeded() {
        let lowWindow = CGRect(x: 0, y: 0, width: 1512, height: 600)
        let lowPill = CGRect(x: 8, y: 516, width: 224, height: 34)
        let lowButton = CGRect(x: 150, y: 519, width: 28, height: 28)
        let beside = frame(ExtensionPopupPlacement.origin(size: tall, control: lowButton, bar: lowPill,
                                                          window: lowWindow, screen: screen), tall)
        #expect(!beside.intersects(lowPill) && beside.minX == lowPill.maxX + gap && beside.maxY == lowPill.maxY)
        #expect(lowWindow.contains(beside))
    }

    @Test func aCrowdedPopupKeepsItsOwnButtonUncovered() {
        let lowerSplitBar = CGRect(x: 248, y: 436, width: 1256, height: 32)
        let lowerSplitButton = CGRect(x: 1400, y: 440, width: 32, height: 24)
        let crowded = frame(ExtensionPopupPlacement.origin(size: tall, control: lowerSplitButton, bar: lowerSplitBar,
                                                           window: window, screen: screen), tall)
        #expect(!crowded.intersects(lowerSplitButton) && crowded.maxX == lowerSplitButton.minX - gap)
        #expect(window.insetBy(dx: 8, dy: 8).contains(crowded))
    }

    @Test func aPopupCanExtendFromItsWindowOntoTheScreen() {
        let smallWindow = CGRect(x: 300, y: 300, width: 700, height: 400)
        let smallBar = CGRect(x: 308, y: 660, width: 684, height: 32)
        let smallButton = CGRect(x: 900, y: 664, width: 32, height: 24)
        let spilled = frame(ExtensionPopupPlacement.origin(size: popup, control: smallButton, bar: smallBar,
                                                           window: smallWindow, screen: screen), popup)
        #expect(spilled.maxY == smallBar.minY - gap && spilled.maxX == smallButton.maxX)
        #expect(screen.contains(spilled))
    }

    @Test func aPopupStaysOnScreenWhenThereIsNoClearSide() {
        let tiny = CGRect(x: 0, y: 0, width: 620, height: 540)
        let tinyBar = CGRect(x: 8, y: 500, width: 604, height: 32)
        let tinyButton = CGRect(x: 570, y: 504, width: 32, height: 24)
        let pinned = frame(ExtensionPopupPlacement.origin(size: tall, control: tinyButton, bar: tinyBar,
                                                          window: tiny, screen: tiny), tall)
        #expect(tiny.insetBy(dx: 8, dy: 8).contains(pinned))
    }

    @Test func thePopupAtTheTrailingEdgeSlidesInsideTheWindow() {
        let nearEdge = CGRect(x: 1476, y: 908, width: 32, height: 24)
        let edgeBar = CGRect(x: 8, y: 904, width: 1504, height: 32)
        let right = frame(ExtensionPopupPlacement.origin(size: popup, control: nearEdge, bar: edgeBar,
                                                         window: window, screen: screen), popup)
        #expect(right.maxX == window.maxX - ExtensionPopupPlacement.margin && right.maxY == edgeBar.minY - gap)
    }

    @Test func thePageCornerAnchorsAPopupWithoutAVisibleControl() {
        let page = CGRect(x: 248, y: 8, width: 1256, height: 928)
        let pageAnchor = ExtensionPopupPlacement.pageAnchor(page)
        let fallback = frame(ExtensionPopupPlacement.origin(size: popup, control: pageAnchor, bar: pageAnchor,
                                                            window: window, screen: nil), popup)
        #expect(fallback.maxX == page.maxX - ExtensionPopupPlacement.pageInset && fallback.maxY == page.maxY - gap)
    }

    @Test func thePopupKeepsTheURLBarClearEvenWhenItMustLeaveItsWindow() {
        let shortWindow = CGRect(x: 0, y: 200, width: 760, height: 620)
        let shortPill = CGRect(x: 8, y: 736, width: 224, height: 34)
        let shortPillButton = CGRect(x: 150, y: 739, width: 28, height: 28)
        let square = CGSize(width: 600, height: 600)
        let hanging = frame(ExtensionPopupPlacement.origin(size: square, control: shortPillButton, bar: shortPill,
                                                           window: shortWindow, screen: screen), square)
        #expect(!hanging.intersects(shortPill) && hanging.maxY == shortPill.minY - gap && screen.contains(hanging))
    }

    @Test func aLowerPanePopupUsesTheSpaceAboveItsToolbar() {
        let shortSplit = CGRect(x: 0, y: 300, width: 1512, height: 644)
        let shortLowerBar = CGRect(x: 248, y: 586, width: 1256, height: 32)
        let shortLowerButton = CGRect(x: 1400, y: 590, width: 32, height: 24)
        let flippedUp = frame(ExtensionPopupPlacement.origin(size: CGSize(width: 600, height: 300), control: shortLowerButton,
                                                             bar: shortLowerBar, window: shortSplit, screen: screen),
                              CGSize(width: 600, height: 300))
        #expect(flippedUp.minY == shortLowerBar.maxY + gap && shortSplit.contains(flippedUp))
    }

    @Test(arguments: [CGFloat(240), 0])
    func aToolbarPopupHangsBelowItsButtonAtEitherSidebarWidth(_ sidebarWidth: CGFloat) {
        let toolbar = CGRect(x: sidebarWidth + 8, y: 904, width: window.width - sidebarWidth - 16, height: 32)
        let button = CGRect(x: toolbar.maxX - 104, y: 908, width: 32, height: 24)
        let placed = frame(ExtensionPopupPlacement.origin(size: popup, control: button, bar: toolbar,
                                                          window: window, screen: screen), popup)
        #expect(!placed.intersects(toolbar))
        #expect(placed.maxY == toolbar.minY - gap && placed.maxX == button.maxX)
        #expect(placed.minX > sidebarWidth)
    }
}

struct ExtensionPopupAnchorTests {
    @MainActor private struct Fixture {
        let sidebar = NSView()
        let urlBar = NSView()
        let sidebarPin = NSView()
        let siteControls = NSView()
        let upperBar = NSView()
        let upperPin = NSView()
        let lowerBar = NSView()
        let lowerPin = NSView()

        init() {
            sidebar.addSubview(urlBar)
            sidebar.addSubview(sidebarPin)
            sidebar.addSubview(siteControls)
            upperBar.addSubview(upperPin)
            lowerBar.addSubview(lowerPin)
        }

        var sidebarArea: ExtensionPopupArea {
            ExtensionPopupArea(owner: sidebar, bar: urlBar, controls: [sidebarPin, siteControls])
        }
        var upperArea: ExtensionPopupArea {
            ExtensionPopupArea(owner: upperBar, bar: upperBar, controls: [upperPin])
        }
        var lowerArea: ExtensionPopupArea {
            ExtensionPopupArea(owner: lowerBar, bar: lowerBar, controls: [lowerPin])
        }

        func anchor(clicked: NSView?, areas: [ExtensionPopupArea]) -> (control: NSView, bar: NSView)? {
            ExtensionPopupPlacement.anchor(clicked: clicked, owners: [sidebarArea, upperArea, lowerArea], defaults: areas) {
                !$0.isHiddenOrHasHiddenAncestor
            }
        }
    }

    enum Area: CaseIterable, Sendable { case sidebar, upper, lower }

    @MainActor @Test(arguments: Area.allCases)
    func clickingAnExtensionUsesItsOwnAddressArea(_ area: Area) {
        let fixture = Fixture()
        let clicked: NSView
        let bar: NSView
        switch area {
        case .sidebar: (clicked, bar) = (fixture.sidebarPin, fixture.urlBar)
        case .upper: (clicked, bar) = (fixture.upperPin, fixture.upperBar)
        case .lower: (clicked, bar) = (fixture.lowerPin, fixture.lowerBar)
        }
        let anchor = fixture.anchor(clicked: clicked, areas: [fixture.lowerArea, fixture.sidebarArea])
        #expect(anchor?.control === clicked && anchor?.bar === bar)
    }

    @MainActor @Test func aShortcutUsesTheExtensionsPinnedButton() {
        let fixture = Fixture()
        let anchor = fixture.anchor(clicked: nil, areas: [fixture.sidebarArea, fixture.upperArea])
        #expect(anchor?.control === fixture.sidebarPin && anchor?.bar === fixture.urlBar)
    }

    @MainActor @Test func anUnpinnedExtensionUsesSiteControls() {
        let fixture = Fixture()
        let unpinned = ExtensionPopupArea(owner: fixture.sidebar, bar: fixture.urlBar, controls: [nil, fixture.siteControls])
        #expect(fixture.anchor(clicked: nil, areas: [unpinned])?.control === fixture.siteControls)
    }

    @MainActor @Test func aHiddenClickedToolbarFallsBackToTheSelectedAddressArea() {
        let fixture = Fixture()
        fixture.upperBar.isHidden = true
        #expect(fixture.anchor(clicked: fixture.upperPin, areas: [fixture.lowerArea])?.bar === fixture.lowerBar)
    }

    @MainActor @Test func aClickOutsideTheAddressAreasUsesTheSelectedToolbar() {
        let fixture = Fixture()
        #expect(fixture.anchor(clicked: NSView(), areas: [fixture.upperArea])?.control === fixture.upperPin)
    }

    @MainActor @Test func noAddressAreaLeavesThePageCornerFallbackAvailable() {
        let fixture = Fixture()
        #expect(fixture.anchor(clicked: nil, areas: []) == nil)
    }
}

struct ExtensionPopupClickSourceTests {
    @MainActor @Test func anotherExtensionCannotClaimTheClick() {
        let button = NSView()
        var source = ExtensionPopupSource(identifier: "reading-list", control: button)
        #expect(source.control(for: "translate", popup: NSObject()) == nil)
        #expect(!source.claimed)
    }

    @MainActor @Test func theReadingListPopupClaimsItsOwnClick() {
        let button = NSView()
        var source = ExtensionPopupSource(identifier: "reading-list", control: button)
        #expect(source.control(for: "reading-list", popup: NSObject()) === button)
        #expect(source.claimed)
    }

    @MainActor @Test func resizingTheSamePopupPreservesItsOriginalButton() {
        let button = NSView()
        let popup = NSObject()
        var source = ExtensionPopupSource(identifier: "reading-list", control: button)
        _ = source.control(for: "reading-list", popup: popup)
        #expect(source.control(for: "reading-list", popup: popup) === button)
    }

    @MainActor @Test func aLaterPopupNeverReusesAClaimedClick() {
        let button = NSView()
        var source = ExtensionPopupSource(identifier: "reading-list", control: button)
        _ = source.control(for: "reading-list", popup: NSObject())
        #expect(source.control(for: "reading-list", popup: NSObject()) == nil)
    }
}
