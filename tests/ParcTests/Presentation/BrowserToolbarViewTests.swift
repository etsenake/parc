import AppKit
import Testing
import ParcCore
@testable import Parc

@MainActor struct BrowserToolbarViewTests {
    private let url = URL(string: "https://sub.example.test:8443/a%20b?q=%2F#part")!

    private final class Recorder {
        var invocations = 0
        var actions: [BrowserToolbarView.Action] = []
        var anchors: [NSView] = []
    }

    private func item(_ recorder: Recorder = Recorder()) -> ExtensionControlItem {
        ExtensionControlItem(identifier: "test", name: "Test", tooltip: "Test", accessibilityLabel: "Test", image: nil,
                             pinnedIndex: 0, canChangePin: true, execute: { _ in recorder.invocations += 1 },
                             showContextMenu: { _ in }, setPinned: { _ in })
    }

    private func toolbar(width: CGFloat = 720, enabled: Bool = true, recorder: Recorder = Recorder()) -> BrowserToolbarView {
        _ = NSApplication.shared
        let toolbar = BrowserToolbarView(frame: NSRect(x: 0, y: 0, width: width, height: BrowserToolbarView.height))
        update(toolbar, enabled: enabled, recorder: recorder)
        return toolbar
    }

    private func update(_ toolbar: BrowserToolbarView, enabled: Bool = true, recorder: Recorder = Recorder()) {
        toolbar.update(url: url, fullURL: true, enabled: enabled, canBack: true, canForward: false, loading: false,
                       canReload: true, canCopy: true, canShowSiteInfo: true, canSplit: true, close: true,
                       showSidebar: true, extensionItems: [item(recorder)])
        toolbar.layoutSubtreeIfNeeded()
    }

    private func update(_ toolbar: BrowserToolbarView, insecure: Bool) {
        toolbar.update(url: URL(string: "http://example.test/a"), fullURL: false, enabled: true, canBack: true,
                       canForward: false, loading: false, canReload: true, canCopy: true, canShowSiteInfo: true,
                       canSplit: true, close: true, showSidebar: true, insecure: insecure, extensionItems: [item()])
        toolbar.layoutSubtreeIfNeeded()
    }

    private func named(_ toolbar: BrowserToolbarView, _ tip: String) -> NSView? {
        toolbar.subviews.first { $0.parcTooltip?.label == tip }
    }

    private func title(_ toolbar: BrowserToolbarView) -> PaneTitleControl {
        toolbar.subviews.compactMap { $0 as? PaneTitleControl }.first!
    }

    private func splitControl(_ toolbar: BrowserToolbarView, _ kind: SplitPaneControl.Kind) -> SplitPaneControl {
        toolbar.subviews.compactMap { $0 as? SplitPaneControl }.first { $0.kind == kind }!
    }

    private func hosted(_ toolbar: BrowserToolbarView) -> SidebarTestWindow {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 100))
        let window = sidebarTestWindow(containing: content)
        content.addSubview(toolbar)
        toolbar.layoutSubtreeIfNeeded()
        return window
    }

    @Test func theBarIsThirtyTwoPointsTallAndAnAccessibleToolbar() {
        let toolbar = toolbar()
        #expect(BrowserToolbarView.height == 32)
        #expect(toolbar.accessibilityRole() == .toolbar)
        #expect(toolbar.layerContentsRedrawPolicy == .beforeViewResize)
        #expect(toolbar.layerContentsPlacement == .scaleAxesIndependently)
    }

    @Test func reloadIsAnIconOnlyControlThatReturnsToReloadAfterLoading() throws {
        let toolbar = toolbar()
        let reload = try #require(named(toolbar, "Reload this page") as? NavigationControlButton)
        #expect(reload.imagePosition == .imageOnly)
        #expect(reload.title.isEmpty && reload.accessibilityLabel() == "Reload this page")
        reload.setLoading(true, enabled: true)
        reload.setLoading(false, enabled: true)
        #expect(reload.title.isEmpty)
        #expect(reload.accessibilityLabel() == "Reload this page" && reload.parcTooltip?.label == "Reload this page")
    }

    @Test(arguments: [CGFloat(160), 240, 300, 340, 720, 1200])
    func everyWidthKeepsTheControlsInsideTheBarOnOneRowWithoutOverlap(width: CGFloat) {
        let toolbar = toolbar(width: width)
        let visible = toolbar.subviews.filter { !$0.isHidden && !$0.frame.isEmpty }
        #expect(visible.allSatisfy { toolbar.bounds.contains($0.frame) })
        #expect(visible.allSatisfy { $0.frame.midY == 16 })
        #expect(visible.enumerated().allSatisfy { index, view in
            visible.dropFirst(index + 1).allSatisfy { !view.frame.intersects($0.frame) }
        })
    }

    @Test(arguments: [CGFloat(160), 240, 300, 340, 720, 1200])
    func essentialControlsNeverYieldRoom(width: CGFloat) {
        let toolbar = toolbar(width: width)
        for tip in ["Go back", "Go forward", "Split View Options", "Remove Tab from Split View", "Show sidebar"] {
            #expect(named(toolbar, tip).map { !$0.isHidden } == true, "\(tip)")
        }
        #expect(splitControl(toolbar, .insecure).isHidden)
    }

    @Test(arguments: [CGFloat(160), 240, 300, 340, 720, 1200])
    func optionalControlsShowOnlyWhenTheyHaveRoom(width: CGFloat) throws {
        let toolbar = toolbar(width: width)
        let reload = try #require(named(toolbar, "Reload this page"))
        let copy = try #require(named(toolbar, "Copy Current URL"))
        let forward = try #require(named(toolbar, "Go forward"))
        let site = try #require(named(toolbar, "Site Control Center"))
        #expect(reload.isHidden == (reload.frame.maxX >= copy.frame.minX))
        #expect(copy.isHidden == !(forward.frame.maxX < copy.frame.minX))
        #expect(site.isHidden == (title(toolbar).frame.maxX >= site.frame.minX))
    }

    @Test func copySitesInTheLeadingBalancedSlotBesideTheTitle() throws {
        let toolbar = toolbar()
        let copy = try #require(named(toolbar, "Copy Current URL"))
        #expect(title(toolbar).frame.midX == toolbar.bounds.midX)
        #expect(copy.frame.maxX == title(toolbar).frame.minX)
        #expect(copy.frame.width == 19)
    }

    @Test func anInsecurePageShowsTheLockBetweenCopyAndTheTitle() throws {
        let toolbar = toolbar()
        update(toolbar, insecure: true)
        let lock = splitControl(toolbar, .insecure)
        let copy = try #require(named(toolbar, "Copy Current URL"))
        #expect(!lock.isHidden && lock.frame.size == NSSize(width: 24, height: 24) && lock.frame.minY == 4)
        #expect(lock.frame.minX == title(toolbar).frame.minX - 19)
        #expect(copy.frame.maxX == lock.frame.minX)
        #expect(title(toolbar).frame.midX == toolbar.bounds.midX)
    }

    @Test func theTitleStaysAboveTheLocksOverhang() {
        let toolbar = toolbar()
        update(toolbar, insecure: true)
        let lock = splitControl(toolbar, .insecure)
        #expect(toolbar.hitTest(NSPoint(x: lock.frame.maxX - 2, y: 16)) === title(toolbar))
        #expect(toolbar.hitTest(NSPoint(x: lock.frame.minX + 4, y: 16)) === lock)
    }

    @Test func theLockRefusesToActOutsideAKeyWindow() {
        let toolbar = toolbar()
        update(toolbar, insecure: true)
        let recorder = Recorder()
        toolbar.onAction = { action, _ in recorder.actions.append(action) }
        splitControl(toolbar, .insecure).sendClick()
        #expect(recorder.actions.isEmpty)
    }

    @Test func theLockOpensSiteControlCenterAnchoredAtItsButton() throws {
        let toolbar = toolbar()
        update(toolbar, insecure: true)
        let window = hosted(toolbar)
        let recorder = Recorder()
        toolbar.onAction = { action, anchor in recorder.actions.append(action); recorder.anchors.append(anchor) }
        splitControl(toolbar, .insecure).sendClick()
        #expect(recorder.actions.count == 1)
        guard case .siteInsecure = try #require(recorder.actions.first) else {
            Issue.record("The lock sent another action")
            return
        }
        #expect(recorder.anchors.first === named(toolbar, "Site Control Center"))
        window.close()
    }

    @Test func aSecurePageDropsTheLockAndItsSlot() throws {
        let toolbar = toolbar()
        update(toolbar, insecure: true)
        update(toolbar, insecure: false)
        let copy = try #require(named(toolbar, "Copy Current URL"))
        #expect(splitControl(toolbar, .insecure).isHidden)
        #expect(copy.frame.maxX == title(toolbar).frame.minX)
    }

    @Test func aModalLeavesCloseAndTheNavigationWidths() throws {
        let toolbar = toolbar()
        toolbar.setObstructedByModal(true, animated: false)
        #expect(named(toolbar, "Remove Tab from Split View")?.alphaValue == 1)
        #expect(named(toolbar, "Go back")?.frame.width == 28)
    }

    @Test(arguments: [false, true])
    func changingExtensionsNeverMovesTheTitle(removing: Bool) {
        let toolbar = toolbar()
        let center = title(toolbar).frame.midX
        toolbar.updateExtensionItems(removing ? [] : [item(), item()])
        toolbar.layoutSubtreeIfNeeded()
        #expect(title(toolbar).frame.midX == center)
    }

    @Test func theSplitMenuAndCloseShareOneInsetSurfaceSize() {
        let toolbar = toolbar()
        let controls = toolbar.subviews.compactMap { $0 as? SplitPaneControl }.filter { $0.kind != .insecure }
        #expect(controls.count == 2)
        #expect(controls.allSatisfy { $0.frame.minY == 4 && $0.frame.maxY == 28 })
        #expect(controls.allSatisfy { $0.frame.size == SplitPaneControl.surfaceSize })
        #expect(splitControl(toolbar, .close).accessibilityLabel() == "Close Split View Pane")
        #expect(splitControl(toolbar, .menu).accessibilityLabel() == "Split View Menu")
        #expect(splitControl(toolbar, .close).frame.maxX == toolbar.bounds.maxX - 5)
    }

    @Test func retiringTheRevealedControlsFadesReloadSiteControlsAndExtensionsOnly() {
        let toolbar = toolbar()
        toolbar.setControlsRevealed(false)
        #expect(named(toolbar, "Reload this page")?.alphaValue == 0)
        #expect(named(toolbar, "Site Control Center")?.alphaValue == 0)
        #expect(toolbar.extensionToolbar.alphaValue == 0)
        #expect(named(toolbar, "Go back")?.alphaValue == 1)
        #expect(named(toolbar, "Copy Current URL")?.alphaValue == 1)
    }

    @Test func revealingTheControlsAgainRestoresThem() {
        let toolbar = toolbar()
        toolbar.setControlsRevealed(false)
        toolbar.setControlsRevealed(true)
        #expect(named(toolbar, "Reload this page")?.alphaValue == 1)
        #expect(toolbar.extensionToolbar.alphaValue == 1)
        #expect(splitControl(toolbar, .menu).alphaValue == 1 && splitControl(toolbar, .close).alphaValue == 1)
    }

    @Test(arguments: [(false, CGFloat(0.5)), (true, 1)])
    func disabledControlsDimTheExtensions(example: (Bool, CGFloat)) {
        let toolbar = toolbar(enabled: !example.0)
        update(toolbar, enabled: example.0)
        #expect(toolbar.extensionToolbar.alphaValue == example.1)
    }

    @Test(arguments: [CGFloat(220), 260, 300, 340, 380, 420],
          [(false, false), (false, true), (true, true), (true, false)])
    func aLongAddressNeverOverlapsAnotherControl(width: CGFloat, example: (Bool, Bool)) throws {
        let toolbar = toolbar(width: width)
        toolbar.update(url: URL(string: "https://www.example-domain-with-a-long-name.test/some/really/long/path?query=1"),
                       fullURL: true, enabled: true, canBack: true, canForward: true, loading: false, canReload: true,
                       canCopy: example.0, canShowSiteInfo: true, canSplit: true, close: true, showSidebar: false,
                       insecure: example.1, extensionItems: [])
        toolbar.layoutSubtreeIfNeeded()
        let copy = try #require(named(toolbar, "Copy Current URL"))
        if !example.0 { #expect(copy.isHidden) }
        let lock = splitControl(toolbar, .insecure), title = title(toolbar)
        let shown = toolbar.subviews.filter { !$0.isHidden && $0.frame.width > 0 }
        #expect(shown.enumerated().allSatisfy { index, view in
            shown.dropFirst(index + 1).allSatisfy { other in
                let overhang = (view === lock && other === title) || (view === title && other === lock)
                return overhang || !view.frame.intersects(other.frame)
            }
        })
    }

    private func documentToolbar() -> BrowserToolbarView {
        let toolbar = toolbar()
        toolbar.update(url: nil, documentTitle: "Original Note", fullURL: false, enabled: true, canBack: false,
                       canForward: false, loading: false, canReload: false, canCopy: false, canShowSiteInfo: false,
                       canSplit: true, close: true, showSidebar: true, siteControls: false, extensionItems: [item()])
        toolbar.layoutSubtreeIfNeeded()
        return toolbar
    }

    @Test func aLaterExtensionRefreshCannotGiveADocumentPins() {
        let toolbar = documentToolbar()
        toolbar.updateExtensionItems([item()])
        #expect(toolbar.extensionToolbar.subviews.isEmpty)
    }

    @Test func aDocumentKeepsTheDisabledNavigationSidebarMenuAndClose() throws {
        let toolbar = documentToolbar()
        let back = try #require(named(toolbar, "Go back") as? NSButton)
        let forward = try #require(named(toolbar, "Go forward") as? NSButton)
        #expect(!back.isHidden && !back.isEnabled && !forward.isEnabled)
        #expect(named(toolbar, "Show sidebar")?.isHidden == false)
        #expect(!splitControl(toolbar, .menu).isHidden && !splitControl(toolbar, .close).isHidden)
    }

    @Test func clickingCopyReachesTheOwnerOnce() throws {
        let toolbar = toolbar()
        let recorder = Recorder()
        toolbar.onAction = { _, _ in recorder.invocations += 1 }
        try #require(named(toolbar, "Copy Current URL") as? NSButton).sendClick()
        #expect(recorder.invocations == 1)
    }

    @Test func aDisabledBarRetiresItsPinsSoTheyCannotAct() throws {
        let recorder = Recorder()
        let toolbar = toolbar(recorder: recorder)
        let pin = try #require(toolbar.extensionToolbar.subviews.compactMap { $0 as? NSButton }.first)
        update(toolbar, enabled: false, recorder: recorder)
        toolbar.updateExtensionItems([item(recorder)])
        #expect(toolbar.extensionToolbar.subviews.isEmpty)
        pin.sendClick()
        #expect(recorder.invocations == 0)
    }

    @Test func anInvalidatedBarCannotDispatch() throws {
        let toolbar = toolbar()
        let recorder = Recorder()
        toolbar.onAction = { _, _ in recorder.invocations += 1 }
        toolbar.invalidate()
        try #require(named(toolbar, "Copy Current URL") as? NSButton).sendClick()
        #expect(recorder.invocations == 0)
    }
}

@MainActor struct BrowserToolbarActionButtonTests {
    private struct Fixture {
        let toolbar: BrowserToolbarView
        let window: SidebarTestWindow
        let site: BrowserToolbarActionButton
        let surface: CALayer
    }

    private func fixture() -> Fixture {
        _ = NSApplication.shared
        let toolbar = BrowserToolbarView(frame: NSRect(x: 0, y: 0, width: 720, height: BrowserToolbarView.height))
        toolbar.update(url: URL(string: "https://example.test/page"), fullURL: true, enabled: true, canBack: true,
                       canForward: false, loading: false, canReload: true, canCopy: true, canShowSiteInfo: true,
                       canSplit: true, close: true, showSidebar: true, extensionItems: [])
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 100))
        let window = sidebarTestWindow(containing: content)
        content.addSubview(toolbar)
        toolbar.layoutSubtreeIfNeeded()
        let site = toolbar.subviews.compactMap { $0 as? BrowserToolbarActionButton }
            .first { $0.parcTooltip?.label == "Site Control Center" }!
        site.reducesMotion = { false }
        return Fixture(toolbar: toolbar, window: window, site: site, surface: site.layer!.sublayers!.first!)
    }

    private func hover(_ button: BrowserToolbarActionButton) -> SidebarAreaEvent {
        let event = SidebarAreaEvent()
        event.area = button.trackingAreas.first { $0.owner === button && !$0.options.contains(.cursorUpdate) }
        return event
    }

    private func glyphAlpha(_ button: NSButton) -> CGFloat { button.contentTintColor?.alphaComponent ?? 0 }

    @Test func theThreeActionButtonsShareTheTopBarStyleAndParcTooltips() {
        let f = fixture()
        let buttons = f.toolbar.subviews.compactMap { $0 as? BrowserToolbarActionButton }.filter { !$0.isHidden }
        #expect(Set(buttons.map { $0.parcTooltip?.label ?? "" }) == ["Copy Current URL", "Site Control Center", "Show sidebar"])
        #expect(buttons.allSatisfy { $0.toolTip == nil })
        f.window.close()
    }

    @Test func theSurfaceKeepsTheSlotWidthAtTwentyFourPointsWithRoundedCorners() throws {
        let f = fixture()
        #expect(f.surface.frame.height == 24 && f.surface.frame.width == f.site.bounds.width)
        #expect(f.surface.cornerRadius == 6)
        let copy = try #require(f.toolbar.subviews.compactMap { $0 as? BrowserToolbarActionButton }
            .first { $0.parcTooltip?.label == "Copy Current URL" })
        #expect(copy.layer?.sublayers?.first?.frame.size == NSSize(width: 19, height: 24))
        f.window.close()
    }

    @Test(arguments: [(CGRect(x: 0, y: 4, width: 28, height: 24), true), (.zero, false)])
    func onlyAMatchingSurfaceFrameSkipsTheWrite(example: (CGRect, Bool)) {
        #expect(BrowserToolbarActionSurfaceLayoutSkip.shouldSkip(current: example.0,
                                                                 next: CGRect(x: 0, y: 4, width: 28, height: 24)) == example.1)
    }

    @Test func aResizedButtonMovesItsSurfaceToTheNewSlot() {
        let f = fixture()
        let prior = f.surface.frame
        f.site.setFrameSize(NSSize(width: f.site.bounds.width + 4, height: f.site.bounds.height))
        f.site.layoutSubtreeIfNeeded()
        #expect(f.surface.frame.width == prior.width + 4 && f.surface.frame.height == 24)
        f.window.close()
    }

    @Test func aDisplacedSurfaceIsRestoredByTheNextLayout() {
        let f = fixture()
        f.surface.frame = .zero
        f.site.needsLayout = true
        f.site.layoutSubtreeIfNeeded()
        #expect(f.surface.frame.height == 24 && f.surface.frame.width == f.site.bounds.width)
        f.window.close()
    }

    @Test func atRestTheLightSurfaceIsClearWithAnEnabledGlyph() {
        let f = fixture()
        f.site.appearance = NSAppearance(named: .aqua)
        f.site.viewDidChangeEffectiveAppearance()
        #expect(f.surface.opacity == 0)
        #expect(abs(glyphAlpha(f.site) - 0.55) < 0.00001)
        f.window.close()
    }

    @Test func hoverAndPressShowTheLightSurfaceWithTheirOwnDurations() throws {
        let f = fixture()
        f.site.appearance = NSAppearance(named: .aqua)
        f.site.viewDidChangeEffectiveAppearance()
        f.site.updateTrackingAreas()
        f.site.mouseEntered(with: hover(f.site))
        #expect(f.site.isHovered && abs(f.surface.opacity - 0.05) < 0.00001)
        #expect(abs((f.surface.animation(forKey: "toolbar-action-opacity")?.duration ?? 0) - 0.18) < 0.00001)
        try #require(f.site.cell).highlight(true, withFrame: f.site.bounds, in: f.site)
        #expect(f.site.isPressed && abs(f.surface.opacity - 0.09) < 0.00001)
        #expect(abs((f.surface.animation(forKey: "toolbar-action-opacity")?.duration ?? 0) - 0.16) < 0.00001)
        f.window.close()
    }

    @Test func reduceMotionShowsTheHoverSurfaceWithoutAFade() {
        let f = fixture()
        f.site.reducesMotion = { true }
        f.site.updateTrackingAreas()
        f.site.mouseEntered(with: hover(f.site))
        #expect(f.site.isHovered && f.surface.opacity > 0)
        #expect(f.surface.animation(forKey: "toolbar-action-opacity") == nil)
        f.window.close()
    }

    @Test func aDarkPressReleasesToTheDarkHoverSurface() throws {
        let f = fixture()
        f.site.updateTrackingAreas()
        f.site.mouseEntered(with: hover(f.site))
        let cell = try #require(f.site.cell)
        cell.highlight(true, withFrame: f.site.bounds, in: f.site)
        f.site.appearance = NSAppearance(named: .darkAqua)
        f.site.viewDidChangeEffectiveAppearance()
        #expect(abs(f.surface.opacity - 0.13) < 0.00001 && abs(glyphAlpha(f.site) - 0.675) < 0.00001)
        cell.highlight(false, withFrame: f.site.bounds, in: f.site)
        #expect(!f.site.isPressed && abs(f.surface.opacity - 0.09) < 0.00001)
        f.window.close()
    }

    @Test func aDisabledButtonDimsItsGlyphAndDropsItsSurface() {
        let f = fixture()
        f.site.updateTrackingAreas()
        f.site.mouseEntered(with: hover(f.site))
        f.site.isEnabled = false
        #expect(!f.site.isHovered && f.surface.opacity == 0 && abs(glyphAlpha(f.site) - 0.25) < 0.00001)
        f.window.close()
    }

    @Test func resamplingAnUnchangedHoverKeepsItsRunningFade() {
        let f = fixture()
        f.site.updateTrackingAreas()
        f.site.mouseEntered(with: hover(f.site))
        f.window.pointer = f.site.convert(NSPoint(x: 5, y: 5), to: nil)
        f.site.isEnabled = true
        f.site.updateTrackingAreas()
        #expect(f.site.isHovered && f.surface.opacity > 0)
        #expect(f.surface.animation(forKey: "toolbar-action-opacity") != nil)
        f.window.close()
    }

    @Test func reenablingUnderARestingPointerRestoresHover() {
        let f = fixture()
        f.window.pointer = f.site.convert(NSPoint(x: 5, y: 5), to: nil)
        f.site.isEnabled = false
        f.site.isEnabled = true
        #expect(f.site.isHovered && f.surface.opacity > 0)
        f.window.close()
    }

    @Test func losingKeyRetiresHoverAndMotion() {
        let f = fixture()
        f.site.updateTrackingAreas()
        f.site.mouseEntered(with: hover(f.site))
        f.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
        #expect(!f.site.isHovered && f.surface.opacity == 0)
        #expect(f.surface.animationKeys()?.isEmpty != false)
        f.window.close()
    }
}
