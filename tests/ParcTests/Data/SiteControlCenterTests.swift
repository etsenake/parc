import AppKit
import Testing
@testable import Parc

struct SiteControlCenterTests {
    @MainActor @Test(arguments: [false, true])
    func captureAvailabilityChoosesTheQuickActions(_ captureAvailable: Bool) {
        let model = SiteControlCenterModel()
        model.captureAvailable = captureAvailable

        let expected: [SiteControlCenterModel.Button] = captureAvailable
            ? [.share, .captureVisiblePage, .capture, .captureFullPage] : [.share, .copyURL]
        #expect(model.buttons == expected)
    }

    @MainActor @Test func theQuickActionsUseTheirOwnAvailabilityAndShortcut() {
        let model = SiteControlCenterModel()
        model.canCopy = true
        model.shortcuts = [.copyURL: "⇧⌘C"]

        #expect(model.isEnabled(.copyURL))
        #expect(!model.isEnabled(.share))
        #expect(!model.isEnabled(.capture))
        #expect(model.help(.copyURL) == "Copy URL  ⇧⌘C")
    }

    @MainActor @Test(arguments: [(nil as String?, 1, "a"), (nil, -1, "a"), ("a", -1, "c"), ("c", 1, "a")])
    func extensionFocusStartsAtTheFirstItemAndWrapsInEitherDirection(_ focus: String?, _ step: Int, _ expected: String) {
        let model = SiteControlCenterModel()
        model.extensions = ["a", "b", "c"].map {
            .init(id: $0, name: $0, tooltip: "", accessibilityLabel: "", icon: nil, isPinned: false, canChangePin: true)
        }
        model.focusedExtension = focus

        model.moveFocus(step)

        #expect(model.focusedExtension == expected)
    }

    typealias Input = SiteControlCenterController.PickerInput

    @MainActor @Test(arguments: [(123, Input.previous), (126, .previous), (124, .next), (125, .next), (14, .next),
                                 (36, .select), (53, .cancel), (76, .cancel), (0, .cancel), (48, .cancel)])
    func pickerKeyYieldsTheMatchingAction(_ code: Int, _ action: Input) {
        #expect(Input.resolve(type: .keyDown, keyCode: UInt16(code), modifiers: .command) == action)
    }

    @MainActor @Test(arguments: [false, true])
    func releasingCommandSelectsTheFocusedExtension(_ commandHeld: Bool) {
        let modifiers: NSEvent.ModifierFlags = commandHeld ? [.command, .shift] : []
        let action = Input.resolve(type: .flagsChanged, keyCode: 55, modifiers: modifiers)
        #expect(action == (commandHeld ? .cancel : .select))
    }

    @MainActor @Test(arguments: [(700, true, 394), (100, false, 132)])
    func theCardHangsFromItsButtonOnTheSideWithRoom(_ y: Int, _ below: Bool, _ expectedY: Int) {
        let parent = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let anchor = CGRect(x: 500, y: CGFloat(y), width: 32, height: 32)
        let placement = SiteControlCenterPlacement.windowFrame(anchor: anchor, card: CGSize(width: 232, height: 300),
                                                                below: true, parent: parent, screen: parent)

        #expect(placement.below == below)
        #expect(placement.frame == CGRect(x: 400, y: CGFloat(expectedY), width: 232, height: 306))
        #expect(placement.tailX == 116)
    }

    @MainActor @Test func anUnshownCardClearsItsCallbacksExactlyOnceWhenClosed() {
        _ = NSApplication.shared
        let model = SiteControlCenterModel()
        model.onButton = { _ in }
        let presenter = SiteControlCenterController(model: model)
        var closed = 0
        presenter.onClose = { closed += 1 }

        presenter.close()
        presenter.close()

        #expect(closed == 1)
        #expect(model.onButton == nil)
        #expect(!presenter.isAwaitingNativeClose)
    }

    @MainActor
    private final class Closing: SiteControlCenterPresentation {
        var isAwaitingNativeClose = true
        var onDidClose: (() -> Void)?
        func close() {}

        func finishClosing() {
            isAwaitingNativeClose = false
            let callback = onDidClose
            onDidClose = nil
            callback?()
        }
    }

    @MainActor
    private final class Fixture {
        var actions: [String] = []
        private var callbacks: [@MainActor () -> Void] = []
        lazy var dismissal = SiteControlCenterDismissal { [weak self] in self?.callbacks.append($0) }

        func trackClosingCard() -> Closing {
            let card = Closing()
            dismissal.track(card)
            return card
        }

        func runScheduledWork() {
            let work = callbacks
            callbacks.removeAll()
            work.forEach { $0() }
        }
    }

    @MainActor @Test func theLatestGestureWaitsForOriginalNativeClose() {
        let fixture = Fixture()
        let card = fixture.trackClosingCard()
        fixture.dismissal.close(nil) { fixture.actions.append("Old") }
        fixture.dismissal.close(nil) { fixture.actions.append("New") }

        fixture.runScheduledWork()
        #expect(fixture.actions.isEmpty)
        card.finishClosing()
        #expect(fixture.actions.isEmpty)
        fixture.runScheduledWork()
        #expect(fixture.actions == ["New"])
    }

    @MainActor @Test(arguments: [false, true])
    func anUnrelatedDismissalCancelsBothPendingAndScheduledActions(_ nativeCloseAlreadyFinished: Bool) {
        let fixture = Fixture()
        let card = fixture.trackClosingCard()
        fixture.dismissal.close(nil) { fixture.actions.append("Capture") }
        if nativeCloseAlreadyFinished { card.finishClosing() }

        fixture.dismissal.close(nil)
        if !nativeCloseAlreadyFinished { card.finishClosing() }
        fixture.runScheduledWork()

        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func aReplacementMustAlsoWaitForTheOlderCardsNativeClose() {
        let fixture = Fixture()
        let first = fixture.trackClosingCard()
        let second = fixture.trackClosingCard()
        fixture.dismissal.close(nil) { fixture.actions.append("Capture") }

        second.finishClosing()
        fixture.runScheduledWork()
        #expect(fixture.actions.isEmpty)
        first.finishClosing()
        fixture.runScheduledWork()

        #expect(fixture.actions == ["Capture"])
    }

    @MainActor @Test(arguments: [false, true])
    func aChangedOwnerLosesItsQueuedActionEvenAfterNativeClose(_ nativeCloseAlreadyFinished: Bool) {
        let fixture = Fixture()
        let card = fixture.trackClosingCard()
        var ownerIsCurrent = true
        fixture.dismissal.close(nil, when: { ownerIsCurrent }) { fixture.actions.append("Capture") }
        if nativeCloseAlreadyFinished { card.finishClosing() }

        ownerIsCurrent = false
        if !nativeCloseAlreadyFinished { card.finishClosing() }
        fixture.runScheduledWork()

        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func anEmptySnapshotClearsTheOriginalExtensionTarget() {
        let model = SiteControlCenterModel()
        model.focusedExtension = "retired"

        model.moveFocus(1)

        #expect(model.focusedExtension == nil)
    }

    @MainActor @Test func theCardHandlesEscapeWithoutAWindow() {
        _ = NSApplication.shared
        let model = SiteControlCenterModel()
        let card = SiteControlCenterCard(content: NSView(frame: .zero), colors: model.colors.menu)
        var escaped = 0
        card.onEscape = { escaped += 1 }

        card.cancelOperation(nil)

        #expect(escaped == 1)
        #expect(card.acceptsFirstResponder)
    }

    enum StaleAnchor: CaseIterable { case owner, detached, moved, cancelled }

    @MainActor @Test(arguments: StaleAnchor.allCases)
    func aDelayedCardRequestCannotOpenAfterItsAnchorIsStale(_ stale: StaleAnchor) throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let original = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        original.isReleasedWhenClosed = false
        let replacement = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        let anchor = NSView(frame: frame)
        original.contentView?.addSubview(anchor)
        var ownerIsCurrent = true
        var scheduled: (@MainActor () -> Void)?
        var ordered = false
        let presenter = SiteControlCenterController(model: SiteControlCenterModel(),
            scheduleShow: { _, show in scheduled = show }, orderPanel: { _, _ in ordered = true })
        var closed = 0
        presenter.onClose = { closed += 1 }
        presenter.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY,
                       after: .seconds(1), expectedWindow: original, when: { ownerIsCurrent })
        #expect(presenter.isShown)

        switch stale {
        case .owner: ownerIsCurrent = false
        case .detached: anchor.removeFromSuperview()
        case .moved:
            anchor.removeFromSuperview()
            replacement.contentView?.addSubview(anchor)
        case .cancelled: presenter.close()
        }
        let show = try #require(scheduled)
        show()

        #expect(!ordered)
        #expect(!presenter.isShown)
        #expect(closed == 1)
    }

    @MainActor
    private final class CardFixture {
        let parent: NSWindow
        let anchor: NSView
        let presenter: SiteControlCenterController
        let panel: NSWindow

        init() throws {
            _ = NSApplication.shared
            let parent = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            parent.appearance = NSAppearance(named: .darkAqua)
            let anchor = NSView(frame: CGRect(x: 280, y: 420, width: 32, height: 32))
            parent.contentView?.addSubview(anchor)
            var panel: NSWindow?
            let presenter = SiteControlCenterController(model: SiteControlCenterModel(), orderPanel: { created, _ in panel = created })
            presenter.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY,
                           expectedWindow: parent, when: { true })
            self.parent = parent
            self.anchor = anchor
            self.presenter = presenter
            self.panel = try #require(panel)
        }

        func card(in view: NSView?) -> SiteControlCenterCard? {
            guard let view else { return nil }
            return (view as? SiteControlCenterCard) ?? view.subviews.lazy.compactMap { self.card(in: $0) }.first
        }
    }

    @MainActor @Test func aCardUsesItsParentsAppearanceAndAnnouncesItselfAsAPopover() throws {
        let fixture = try CardFixture()
        defer { fixture.presenter.close() }

        #expect(fixture.presenter.isAnchored(to: fixture.anchor))
        #expect(fixture.panel.accessibilityRole() == .popover)
        #expect(fixture.panel.accessibilityLabel() == "Site Control Center")
        #expect(fixture.panel.appearance?.name == .darkAqua)
        #expect(!fixture.panel.isVisible)
    }

    enum CloseSignal: CaseIterable { case escape, parentClosing }

    @MainActor @Test(arguments: CloseSignal.allCases)
    func theCardRunsBothCloseCallbacksOnce(_ signal: CloseSignal) throws {
        let fixture = try CardFixture()
        defer { fixture.presenter.close() }
        var events: [String] = []
        fixture.presenter.onClose = { events.append("close") }
        fixture.presenter.onDidClose = { events.append("did close") }

        switch signal {
        case .escape:
            let card = try #require(fixture.card(in: fixture.panel.contentView))
            card.cancelOperation(nil)
        case .parentClosing:
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: fixture.parent)
        }

        #expect(events == ["close", "did close"])
        fixture.presenter.close()
        #expect(events == ["close", "did close"])
        #expect(!fixture.presenter.isShown)
        #expect(!fixture.presenter.isAwaitingNativeClose)
    }
}
