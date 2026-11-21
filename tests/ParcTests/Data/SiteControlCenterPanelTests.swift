import AppKit
import ParcCore
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SiteControlCenterPanelTests {
    private static func extensionItem(_ id: String, pinned: Bool = false) -> SiteControlCenterModel.Extension {
        .init(id: id, name: "Extension " + id, tooltip: "", accessibilityLabel: "", icon: nil, isPinned: pinned, canChangePin: true)
    }

    private static func setting(_ id: String, title: String, subtitle: String, isOn: Bool) -> SiteControlCenterModel.Setting {
        .init(id: id, symbol: "gearshape.fill", symbolSize: 13, symbolWeight: .medium, title: title,
              subtitle: subtitle, isOn: isOn, isEnabled: true)
    }

    private static func borderlessWindow(hosting view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -12_000, y: -12_000), size: view.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }

    private static func views<View: NSView>(_ type: View.Type, in view: NSView) -> [View] {
        ((view as? View).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    private static func fullModel() -> SiteControlCenterModel {
        let model = SiteControlCenterModel()
        model.captureAvailable = true
        model.extensions = [extensionItem("a", pinned: true), extensionItem("b"), extensionItem("c"),
                            extensionItem("d"), extensionItem("e")]
        model.settings = [setting("developerMode", title: "Developer Mode", subtitle: "Off", isOn: false),
                          setting("permission:0:1", title: "Camera", subtitle: "Allowed", isOn: true)]
        model.isSecure = true
        return model
    }

    private static func hostedTooltips() throws -> (NSWindow, [TooltipAnchorView], [String: TooltipConfiguration]) {
        let directory = try #require(Bundle.module.url(forResource: "SiteControlCenter", withExtension: nil))
        let host = NSHostingView(rootView: SiteControlCenterView(model: fullModel())
            .environment(\.siteControlCenterArtwork, SiteControlCenterArtwork.Library(directory: directory)))
        host.frame.size = host.fittingSize
        let window = borderlessWindow(hosting: host)
        let anchors = views(TooltipAnchorView.self, in: host)
        let tooltips = Dictionary(anchors.compactMap { anchor in anchor.parcTooltip.map { ($0.label, $0) } }) { first, _ in first }
        return (window, anchors, tooltips)
    }

    @Test func theCardKeepsItsTilesInsideThePlusMenusEdgeInset() {
        #expect(SiteControlCenterMetrics.padding == SidebarPlusMenuView.inset)
        #expect(SiteControlCenterMetrics.width == 232)
        #expect(SiteControlCenterMetrics.button == CGSize(width: 48, height: 32))
        #expect(SiteControlCenterMetrics.extensionIcon == 16)
        #expect(SiteControlCenterMetrics.pin == 14)
    }

    @Test(arguments: [(SiteControlCenterModel.Button.capture, "Capture a portion of this page"),
                      (.captureVisiblePage, "Capture the visible area"), (.captureFullPage, "Capture the full page")])
    func captureHintsNameTheirAcquisitionMode(_ button: SiteControlCenterModel.Button, _ hint: String) {
        #expect(SiteControlCenterModel().help(button) == hint)
    }

    @Test func theHostedCardIsExactlyTheCardWidth() {
        let host = NSHostingView(rootView: SiteControlCenterView(model: Self.fullModel()))
        #expect(host.fittingSize.width == 232)
    }

    @Test func everyItemOfTheCardCarriesATooltip() throws {
        let (window, _, tooltips) = try Self.hostedTooltips()
        defer { window.close() }

        #expect(Set(tooltips.keys) == ["Share", "Capture the visible area", "Capture a portion of this page",
                                       "Capture the full page", "Extension a", "Extension b", "Extension c", "Extension d",
                                       "Extension e", "Unpin", "Add Extension", "Manage Extensions", "All Site Settings",
                                       "Developer Mode", "Camera", "Secure", "More"])
    }

    @Test func theActionKeycapsFollowTheirCommandsLiveBindings() throws {
        let (window, _, tooltips) = try Self.hostedTooltips()
        defer { window.close() }

        #expect(tooltips["Share"]?.shortcut == nil)
        #expect(tooltips["Capture the full page"]?.shortcut == .command("captureFullPage:"))
        #expect(tooltips["Capture a portion of this page"]?.shortcut == .command("capturePage:"))
        #expect(tooltips["Capture the visible area"]?.shortcut == .command("captureVisiblePage:"))
        #expect(SiteControlCenterModel.Button.copyURL.commandID == "copyCurrentURL:")
    }

    @Test func itemTooltipsTakeTheWindowsPaletteBelowTheirItem() throws {
        let (window, _, tooltips) = try Self.hostedTooltips()
        defer { window.close() }

        #expect(!tooltips.isEmpty)
        #expect(tooltips.values.allSatisfy { $0.palette == nil && $0.anchor == .bottomTrailing })
    }

    @Test func ordinaryHitTestsPassThroughEveryTooltipAnchor() throws {
        let (window, anchors, _) = try Self.hostedTooltips()
        defer { window.close() }
        let host = try #require(window.contentView)

        #expect(!anchors.isEmpty)
        for anchor in anchors {
            let centre = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
            let hit = host.hitTest(host.superview?.convert(centre, from: nil) ?? centre)
            #expect(!(hit is TooltipAnchorView))
        }
    }

    @Test func theShellDrawsAnExtensionsBadgeOnceClearOfItsPin() {
        let badge = ExtensionActionBadge(text: "12", textColor: .white, backgroundColor: .systemBlue)
        let model = SiteControlCenterModel()
        model.extensions = [
            .init(id: "unbadged", name: "Unbadged", tooltip: "", accessibilityLabel: "", icon: nil, isPinned: true,
                  canChangePin: true, badge: badge, badgeText: "12"),
            .init(id: "baked", name: "Baked", tooltip: "", accessibilityLabel: "", icon: nil, isPinned: false,
                  canChangePin: true, badgeText: "3")]
        let host = NSHostingView(rootView: SiteControlCenterView(model: model))
        host.frame.size = host.fittingSize
        let window = Self.borderlessWindow(hosting: host)
        defer { window.close() }

        let drawn = Self.views(ExtensionActionBadgeView.self, in: host)
        let expected = ExtensionActionBadgeMetrics.frame(text: "12", in: NSRect(origin: .zero, size: SiteControlCenterMetrics.button))

        #expect(drawn.count == 1)
        #expect(drawn.first?.badge == badge)
        #expect(drawn.first?.frame.size == expected.size)
        #expect(expected.maxX <= SiteControlCenterMetrics.button.width - SiteControlCenterMetrics.pin + 3)
        #expect(expected.maxY <= SiteControlCenterMetrics.button.height - SiteControlCenterMetrics.pin + 3)
    }

    private static func fittingSize(extensions: Int, settings: Bool) -> NSSize {
        let model = SiteControlCenterModel()
        model.extensions = (0..<extensions).map { extensionItem(String($0)) }
        if settings {
            model.settings = [setting("developerMode", title: "Developer Mode", subtitle: "Off", isOn: false)]
            model.isSecure = true
        }
        return NSHostingView(rootView: SiteControlCenterView(model: model)).fittingSize
    }

    @Test func settingsAndTheFooterCollapseWhenAbsent() {
        let bare = Self.fittingSize(extensions: 3, settings: false)
        #expect(bare.width == 232)
        #expect(bare.height < Self.fittingSize(extensions: 3, settings: true).height)
    }

    @Test func aFifthItemStartsASecondRowBelowTheFirst() {
        let oneRow = Self.fittingSize(extensions: 3, settings: false)
        let twoRows = Self.fittingSize(extensions: 4, settings: false)
        #expect(twoRows.height == oneRow.height + SiteControlCenterMetrics.button.height + SiteControlCenterMetrics.spacing)
    }

    struct Hang: CustomTestStringConvertible {
        let name: String
        let anchor: CGRect
        let card: CGFloat
        let parent: CGRect
        let screen: CGRect
        let check: @Sendable (CGRect, CGFloat, Bool, CGFloat) -> Bool
        var testDescription: String { name }
    }

    nonisolated static let hangs: [Hang] = {
        let window = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        return [
            Hang(name: "near the window's edge", anchor: CGRect(x: -6, y: 700, width: 32, height: 32), card: 300,
                 parent: window, screen: window) { frame, tail, _, edge in frame.minX == 0 && tail == edge },
            Hang(name: "a window running off the screen", anchor: CGRect(x: 1420, y: 800, width: 32, height: 32), card: 300,
                 parent: CGRect(x: 900, y: 300, width: 700, height: 575), screen: screen) { frame, _, _, _ in frame.maxX == screen.maxX },
            Hang(name: "no room on either side in the window", anchor: CGRect(x: 500, y: 350, width: 32, height: 32), card: 380,
                 parent: CGRect(x: 0, y: 0, width: 1000, height: 400), screen: screen) { frame, _, below, _ in
                     !below && frame.minY == 382 && frame.maxX <= 1000 },
            Hang(name: "no room on either side anywhere", anchor: CGRect(x: 500, y: 400, width: 32, height: 32), card: 600,
                 parent: CGRect(x: 0, y: 0, width: 1000, height: 875), screen: screen) { frame, _, below, _ in
                     !below && frame.maxY == screen.maxY },
            Hang(name: "a card taller than the window", anchor: CGRect(x: 500, y: 560, width: 32, height: 32), card: 400,
                 parent: CGRect(x: 0, y: 300, width: 1000, height: 300), screen: screen) { frame, _, below, _ in
                     below && frame.maxY == 560 && frame.minY >= screen.minY },
        ]
    }()

    @Test(arguments: hangs)
    func theCardStaysOnScreenAndBesideItsButton(_ hang: Hang) {
        let placed = SiteControlCenterPlacement.windowFrame(anchor: hang.anchor, card: CGSize(width: 232, height: hang.card),
                                                             below: true, parent: hang.parent, screen: hang.screen)
        let edge = SidebarPlusMenuPlacement.cornerRadius + SidebarPlusMenuPlacement.tailBase / 2
        #expect(hang.check(placed.frame, placed.tailX, placed.below, edge))
    }

    @Test func aHangingCardsTailTipIsAboveIt() {
        let content = NSView(frame: .zero)
        let colors = SiteControlCenterColors(theme: SpaceTheme()).menu
        let chrome = ParcMenuChrome(content: content, size: NSSize(width: 232, height: 100), colors: colors, tailX: 116, tailOnTop: true)

        #expect(content.frame == NSRect(x: 0, y: 0, width: 232, height: 100))
        #expect(chrome.tailTip == NSPoint(x: 116, y: 106))
    }

    @Test func thePlusMenuKeepsItsCardAboveATailPointingDown() {
        let colors = SiteControlCenterColors(theme: SpaceTheme()).menu
        let menu = SidebarPlusMenuView(rows: SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true,
                                                                       canCreateNote: true, canSplit: true),
                                       colors: colors) { _ in }
        let chrome = SidebarPlusMenuChrome(card: menu, tailX: 50)

        #expect(menu.frame.origin.y == SidebarPlusMenuPlacement.tailHeight)
        #expect(chrome.tailTip == NSPoint(x: 50, y: 0))
    }

    @Test func anActionAfterClosingAShownCardWaitsForTheNextTurn() {
        var scheduled: [@MainActor () -> Void] = []
        let dismissal = SiteControlCenterDismissal { scheduled.append($0) }
        var ran = 0

        dismissal.close(SiteControlCenterController(model: SiteControlCenterModel())) { ran += 1 }
        #expect(ran == 0)
        scheduled.forEach { $0() }

        #expect(ran == 1)
    }

    @Test func anActionWithNoCardToCloseRunsAtOnce() {
        let dismissal = SiteControlCenterDismissal { _ in }
        var ran = 0

        dismissal.close(nil) { ran += 1 }

        #expect(ran == 1)
    }

    @Test func aMismatchedImmediateAnchorCannotShow() {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let owner = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        let other = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let anchor = NSView(frame: frame)
        other.contentView?.addSubview(anchor)
        var ordered = false
        let presenter = SiteControlCenterController(model: SiteControlCenterModel(), orderPanel: { _, _ in ordered = true })
        var closed = 0
        presenter.onClose = { closed += 1 }

        presenter.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, expectedWindow: owner, when: { true })

        #expect(!ordered)
        #expect(!presenter.isShown)
        #expect(closed == 1)
    }

    @Test func theExtensionClickLayerIsTransparentWithoutASecondaryClick() {
        _ = NSApplication.shared
        let click = SiteControlCenterAlternateClick.ClickView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        #expect(click.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }
}

@MainActor
private final class ShownCard {
    let parent: NSWindow
    let anchor: NSView
    let model: SiteControlCenterModel
    let controller: SiteControlCenterController
    let panel: SiteControlCenterWindow
    var event: NSEvent? {
        get { pending.event }
        set { pending.event = newValue }
    }
    private let pending: Pending

    private final class Pending {
        var event: NSEvent?
        var focusChecks: [@MainActor () -> Void] = []
        var sizeChecks: [Timer] = []
    }
    var events: [String] = []

    init(model given: SiteControlCenterModel? = nil, anchorX: CGFloat = 280) throws {
        let model = given ?? SiteControlCenterModel()
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 600, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.appearance = NSAppearance(named: .darkAqua)
        let anchor = NSView(frame: NSRect(x: anchorX, y: 640, width: 32, height: 32))
        parent.contentView?.addSubview(anchor)
        var shown: NSWindow?
        let pending = Pending()
        self.pending = pending
        let controller = SiteControlCenterController(model: model, orderPanel: { panel, _ in shown = panel },
            currentEvent: { pending.event }, pressedMouseButtons: { 0 },
            checkFocusSoon: { work in pending.focusChecks.append(work) },
            addSizeCheck: { timer in pending.sizeChecks.append(timer) })
        self.parent = parent
        self.anchor = anchor
        self.model = model
        self.controller = controller
        controller.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, expectedWindow: parent, when: { true })
        self.panel = try #require(shown as? SiteControlCenterWindow)
        runSizeChecks()
        controller.onClose = { [unowned self] in events.append("close") }
        controller.onDidClose = { [unowned self] in events.append("did close") }
        controller.onDetach = { [unowned self] in events.append("detach") }
    }

    func runFocusChecks() {
        let work = pending.focusChecks
        pending.focusChecks.removeAll()
        work.forEach { $0() }
    }

    func runSizeChecks() {
        let timers = pending.sizeChecks
        pending.sizeChecks.removeAll()
        timers.forEach { $0.fire() }
    }

    func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow? = nil, number: Int = 77) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: (window ?? panel).windowNumber, context: nil, eventNumber: number,
                           clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    func escape() {
        panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
    }

    func dragBackground(by distance: CGFloat) {
        panel.sendEvent(mouse(.leftMouseDown, NSPoint(x: 3, y: 3)))
        panel.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 3 + distance, y: 3)))
        panel.sendEvent(mouse(.leftMouseUp, NSPoint(x: 3 + distance, y: 3)))
    }

    func tooltipAnchor(_ label: String) -> TooltipAnchorView? {
        func find(_ view: NSView) -> TooltipAnchorView? {
            if let anchor = view as? TooltipAnchorView, anchor.parcTooltip?.label == label { return anchor }
            return view.subviews.lazy.compactMap(find).first
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        return panel.contentView.flatMap(find)
    }
}

@MainActor
struct SiteControlCenterInteractionTests {
    @Test func aShownCardIsAPopoverHangingBelowItsButtonWithKeyboardFocus() throws {
        let card = try ShownCard()
        defer { card.controller.close() }

        #expect(card.controller.isShown)
        #expect(card.panel.canBecomeKey)
        #expect(card.panel.firstResponder is NSHostingView<SiteControlCenterView>)
        #expect(card.panel.frame.maxY <= card.parent.convertToScreen(card.anchor.frame).minY + 0.5)
    }

    enum Loss: CaseIterable { case resignKey, deactivate }

    @Test(arguments: Loss.allCases)
    func losingFocusClosesTheCardOnce(_ loss: Loss) throws {
        let card = try ShownCard()

        switch loss {
        case .resignKey:
            card.panel.resignKey()
            card.runFocusChecks()
        case .deactivate:
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        }

        #expect(card.events == ["close", "did close"])
        #expect(!card.controller.isShown)
    }

    @Test func escapeSentToTheCardClosesIt() throws {
        let card = try ShownCard()

        card.escape()

        #expect(card.events == ["close", "did close"])
    }

    @Test func aBackgroundDragPastThreePointsTearsTheCardOff() throws {
        let card = try ShownCard()
        defer { card.controller.close() }

        card.dragBackground(by: 6)

        #expect(card.controller.isDetached)
        #expect(card.events == ["detach"])
        #expect(card.panel.firstResponder is NSHostingView<SiteControlCenterView>)
        #expect(card.panel.contentView is SiteControlCenterCard)
    }

    @Test func aTwoPointDragDoesNotDetach() throws {
        let card = try ShownCard()
        defer { card.controller.close() }

        card.dragBackground(by: 2)

        #expect(!card.controller.isDetached)
        #expect(card.events.isEmpty)
    }

    @Test func aDetachedCardStaysOpenWhenItLosesFocusAndClosesOnEscape() throws {
        let card = try ShownCard()
        card.dragBackground(by: 6)

        card.panel.resignKey()
        card.runFocusChecks()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(card.controller.isShown)
        card.escape()

        #expect(card.events == ["detach", "close", "did close"])
        #expect(!card.controller.isShown)
    }

    @Test func aDragThatStartsOnATileNeitherDetachesNorTearsOff() throws {
        let model = SiteControlCenterModel()
        model.canShare = true
        let card = try ShownCard(model: model)
        defer { card.controller.close() }
        let tile = try #require(card.tooltipAnchor("Share"))
        let centre = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)

        #expect(SiteControlCenterWindow.isItem(at: centre, in: card.panel.contentView))
        #expect(!SiteControlCenterWindow.isItem(at: NSPoint(x: 3, y: 3), in: card.panel.contentView))
        card.panel.sendEvent(card.mouse(.leftMouseDown, centre))
        card.panel.sendEvent(card.mouse(.leftMouseDragged, NSPoint(x: centre.x, y: centre.y - 20)))
        card.panel.sendEvent(card.mouse(.leftMouseDragged, NSPoint(x: centre.x, y: centre.y - 60)))
        card.panel.sendEvent(card.mouse(.leftMouseUp, NSPoint(x: centre.x, y: centre.y - 60)))

        #expect(!card.controller.isDetached)
        #expect(card.controller.isShown)
    }

    @Test func aTallerCardFollowsItsMovedButtonAndKeepsFocus() throws {
        let model = SiteControlCenterModel()
        let card = try ShownCard(model: model, anchorX: 520)
        defer { card.controller.close() }
        let before = try #require(card.panel.contentView as? ParcMenuChrome)

        card.anchor.frame.origin.x = 560
        model.settings = [.init(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium,
                                title: "Developer Mode", subtitle: "Off", isOn: false, isEnabled: true)]
        card.panel.contentView?.layoutSubtreeIfNeeded()
        card.runSizeChecks()

        let after = try #require(card.panel.contentView as? ParcMenuChrome)
        #expect(after !== before)
        #expect(before.tailX == 168)
        #expect(after.tailX == 208)
        #expect(after.tailOnTop)
        #expect(card.panel.firstResponder is NSHostingView<SiteControlCenterView>)
    }

    @Test func thePressThatClosedTheCardDoesNotReopenIt() throws {
        let card = try ShownCard()
        let point = card.anchor.convert(NSPoint(x: 16, y: 16), to: nil)
        card.event = card.mouse(.leftMouseDown, point, in: card.parent, number: 4242)
        card.panel.resignKey()
        card.runFocusChecks()
        #expect(card.events == ["close", "did close"])

        let release = card.mouse(.leftMouseUp, point, in: card.parent, number: 4242)
        var ordered = false
        let reopened = SiteControlCenterController(model: SiteControlCenterModel(), orderPanel: { _, _ in ordered = true },
                                                   currentEvent: { release })
        var reopenedClosed = 0
        reopened.onClose = { reopenedClosed += 1 }
        reopened.show(relativeTo: card.anchor.bounds, of: card.anchor, preferredEdge: .minY,
                      expectedWindow: card.parent, when: { true })

        #expect(!ordered)
        #expect(!reopened.isShown)
        #expect(reopenedClosed == 1)
    }

    @Test func aLaterPressOnTheButtonOpensTheCardAgain() throws {
        let card = try ShownCard()
        let point = card.anchor.convert(NSPoint(x: 16, y: 16), to: nil)
        card.event = card.mouse(.leftMouseDown, point, in: card.parent, number: 4242)
        card.panel.resignKey()
        card.runFocusChecks()

        let later = card.mouse(.leftMouseUp, point, in: card.parent, number: 4243)
        var ordered = false
        let reopened = SiteControlCenterController(model: SiteControlCenterModel(), orderPanel: { _, _ in ordered = true },
                                                   currentEvent: { later })
        defer { reopened.close() }
        reopened.show(relativeTo: card.anchor.bounds, of: card.anchor, preferredEdge: .minY,
                      expectedWindow: card.parent, when: { true })

        #expect(ordered)
        #expect(reopened.isShown)
    }
}
