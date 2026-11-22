import AppKit
import ParcCore
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SiteControlCenterPanelInteractionTests {
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

    enum Loss: CaseIterable { case resignKey, deactivate }

    @Test func aShownCardIsAPopoverHangingBelowItsButtonWithKeyboardFocus() throws {
        let card = try ShownCard()
        defer { card.controller.close() }

        #expect(card.controller.isShown)
        #expect(card.panel.canBecomeKey)
        #expect(card.panel.firstResponder is NSHostingView<SiteControlCenterView>)
        #expect(card.panel.frame.maxY <= card.parent.convertToScreen(card.anchor.frame).minY + 0.5)
    }

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

    @Test func aDetachedCardStaysOpenWhenItLosesFocus() throws {
        let card = try ShownCard()
        card.dragBackground(by: 6)

        card.panel.resignKey()
        card.runFocusChecks()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(card.controller.isShown)
    }

    @Test func escapeClosesADetachedCard() throws {
        let card = try ShownCard()
        card.dragBackground(by: 6)
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
