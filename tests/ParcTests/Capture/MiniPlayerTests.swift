import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class MiniPlayerFixture {
    let window: NSWindow
    let deck = MiniPlayerDeck(frame: CGRect(x: 0, y: 0, width: 212, height: 230))
    private(set) var engines: [String: ParcMiniPlayerEngineFixture] = [:]
    private(set) var revealed: [String] = []
    private(set) var collapses: [(delay: TimeInterval, job: @MainActor () -> Void)] = []
    var relinks = 0

    init(_ ids: [String]) throws {
        _ = NSApplication.shared
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 400),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(deck)
        deck.after = { [weak self] delay, job in self?.collapses.append((delay, job)) }
        deck.onKeyViewsChanged = { [weak self] in self?.relinks += 1 }
        try update(ids)
    }

    func engine(_ id: String) -> ParcMiniPlayerEngineFixture {
        if let fixture = engines[id] { return fixture }
        let new = ParcMiniPlayerEngineFixture(identifier: id, title: id)
        engines[id] = new
        return new
    }

    func update(_ ids: [String]) throws {
        let items = try ids.map { id in
            let engine = self.engine(id)
            let page = try #require(engine.page as? PCNativePage)
            let state = try #require(engine.state as? PCNativeMediaState)
            return MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window),
                valid: { true }, reveal: { [weak self] in self?.revealed.append(id) })
        }
        deck.update(items)
        layout()
    }

    func layout() {
        deck.frame.size.height = deck.desiredHeight
        deck.layoutSubtreeIfNeeded()
    }

    func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    func button(_ label: String, in root: NSView? = nil, visible: Bool = false) throws -> ActionButton {
        try #require(descendants(root ?? deck).compactMap { $0 as? ActionButton }.first {
            $0.accessibilityLabel() == label && (!visible || !$0.isHiddenOrHasHiddenAncestor)
        })
    }

    func row(_ id: String) throws -> MiniPlayerRow {
        try #require(descendants(deck).compactMap { $0 as? MiniPlayerRow }.first { row in
            descendants(row).contains { ($0 as? ActionButton)?.accessibilityLabel() == "Back to Tab — \(id)" }
        })
    }

    func toggleExpansion(_ label: String = "Show All Mini Players (2)") throws {
        let button = try button(label)
        button.actionBlock?()
        layout()
    }

    func toggleVolume(in id: String) throws {
        let button = try button("Adjust Tab Volume", in: row(id))
        button.actionBlock?()
        layout()
    }

    func volume(in id: String) throws -> NSSlider {
        let row = try row(id)
        return try #require(descendants(row).compactMap { $0 as? NSSlider }.first)
    }

    func key(_ code: UInt16, _ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
}

struct MiniPlayerAdmissionOrderTests {
    @MainActor @Test func aRemainingRowKeepsItsIdentityAcrossReadmission() throws {
        let fixture = try MiniPlayerFixture(["first", "second"])
        let second = try fixture.row("second")
        try fixture.update(["second"])
        try fixture.update(["first", "second"])
        #expect(try fixture.row("second") === second)
    }

    @MainActor @Test func readmittingAnEarlierEntryRestoresItsFrontPosition() throws {
        let fixture = try MiniPlayerFixture(["second"])
        try fixture.update(["first", "second"])
        #expect(try fixture.row("first").frame.minY > fixture.row("second").frame.minY)
    }

    @MainActor @Test func expandedKeyboardOrderFollowsAdmission() throws {
        let fixture = try MiniPlayerFixture(["second"])
        try fixture.update(["first", "second"])
        try fixture.toggleExpansion()
        let first = try fixture.row("first"), second = try fixture.row("second")
        let chain = SidebarAccessibility.keyViews(in: [fixture.deck], space: fixture.deck)
        SidebarAccessibility.link(chain, within: fixture.deck, exit: nil)
        let firstIndex = try #require(chain.firstIndex { $0 === first })
        let secondIndex = try #require(chain.firstIndex { $0 === second })
        try #require(firstIndex < secondIndex)
        #expect(chain[secondIndex - 1].nextKeyView === second)
    }
}

struct MiniPlayerAccessibilityTests {
    @MainActor private func checkName(_ button: ActionButton, name: String, help: String) {
        #expect(button.accessibilityLabel() == name)
        #expect(button.cell?.accessibilityLabel() == name)
        #expect(button.image?.accessibilityDescription == name)
        #expect(button.parcTooltip?.label == help)
        #expect(button.toolTip == nil && button.accessibilityHelp() == help)
    }

    @MainActor @Test(arguments: [false, true])
    func theDeckControlExposesItsExpansionState(_ expanded: Bool) throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        if expanded { try fixture.toggleExpansion() }
        let title = expanded ? "Collapse Mini Players" : "Show All Mini Players (2)"
        let button = try fixture.button(title)
        checkName(button, name: title, help: title)
        #expect(button.isAccessibilityExpanded() == expanded)
        #expect(button.cell?.isAccessibilityExpanded() == expanded)
    }

    struct MediaLabel: Sendable {
        let active: Bool
        let name: String
        let help: String

        static let samples: [Self] = [
            .init(active: false, name: "Pause", help: "Pause"),
            .init(active: false, name: "Turn Camera On", help: "Toggle Camera"),
            .init(active: false, name: "Unmute Microphone", help: "Toggle Microphone"),
            .init(active: false, name: "Mute Tab", help: "Mute Tab"),
            .init(active: true, name: "Play", help: "Play"),
            .init(active: true, name: "Turn Camera Off", help: "Toggle Camera"),
            .init(active: true, name: "Mute Microphone", help: "Toggle Microphone"),
            .init(active: true, name: "Unmute Tab", help: "Unmute Tab"),
        ]
    }

    @MainActor @Test(arguments: MediaLabel.samples)
    func theTransportNamesTheActionAvailableNow(_ sample: MediaLabel) throws {
        let fixture = try MiniPlayerFixture(["episode"])
        let engine = fixture.engine("episode")
        engine.canToggleCamera = true
        engine.canToggleMicrophone = true
        engine.playing = !sample.active
        engine.cameraOn = sample.active
        engine.microphoneOn = sample.active
        engine.muted = sample.active
        try fixture.update(["episode"])
        fixture.deck.updateHover(true)
        fixture.layout()
        checkName(try fixture.button(sample.name), name: sample.name, help: sample.help)
    }

    @MainActor @Test(arguments: [0, 1, 2])
    func theVolumeButtonAndCellReportTheirExpansion(_ toggles: Int) throws {
        let fixture = try MiniPlayerFixture(["episode"])
        fixture.deck.updateHover(true)
        for _ in 0..<toggles { try fixture.toggleVolume(in: "episode") }
        let button = try fixture.button("Adjust Tab Volume")
        #expect(button.isAccessibilityExpanded() == (toggles == 1))
        #expect(button.cell?.isAccessibilityExpanded() == (toggles == 1))
    }

    @MainActor @Test(arguments: [(false, false), (false, true), (true, true)])
    func aRetiredEpisodeExposesAnUnavailableMessage(_ multiple: Bool, _ expanded: Bool) throws {
        let fixture = try MiniPlayerFixture(multiple ? ["episode", "other"] : ["episode"])
        if expanded { fixture.deck.updateHover(true); fixture.layout() }
        let pause = try fixture.button("Pause", in: fixture.row("episode"))
        fixture.engine("episode").available = false
        pause.actionBlock?()
        fixture.layout()
        let error = fixture.descendants(fixture.deck).compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "This media is no longer available." }
        #expect(error?.isHiddenOrHasHiddenAncestor == false)
    }

    @MainActor @Test func anUnavailableActionExpandsTheCollapsedDeck() throws {
        let fixture = try MiniPlayerFixture(["episode", "other"])
        fixture.engine("episode").available = false
        try fixture.button("Pause", in: fixture.row("episode")).actionBlock?()
        fixture.layout()
        #expect(try fixture.button("Collapse Mini Players").isAccessibilityExpanded())
    }
}

struct MiniPlayerPresentationTests {
    @MainActor @Test func collapsedCardsStackWithTheirOriginalOffsets() throws {
        let fixture = try MiniPlayerFixture(["a", "b", "c"])
        let front = try fixture.row("a"), middle = try fixture.row("b"), back = try fixture.row("c")
        #expect(fixture.deck.desiredHeight == 69)
        #expect([front, middle, back].map { $0.frame.height } == [33, 33, 33])
        #expect(front.frame.minY - middle.frame.minY == 7 && middle.frame.minY - back.frame.minY == 7)
        #expect(front.frame.width - middle.frame.width == 10 && middle.frame.width - back.frame.width == 10)
    }

    @MainActor @Test func reorderingTheDeckRetainsTheRowsBackingLayer() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        let row = try fixture.row("a")
        let layer = try #require(row.layer)
        try fixture.update(["b", "a"])
        #expect(try fixture.row("a").layer === layer)
    }

    @MainActor @Test func collapsedChromeKeepsTransportAndHidesTheTitle() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        let front = try fixture.row("a")
        #expect(try fixture.button("Back to Tab — a", in: front).isHidden)
        #expect(try !fixture.button("Previous Track", in: front).isHidden)
        #expect(try !fixture.button("Adjust Tab Volume", in: front).isHidden)
    }

    @MainActor @Test func expandingTheDeckRelinksItsKeyboardViews() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        let relinks = fixture.relinks
        try fixture.toggleExpansion()
        #expect(fixture.relinks > relinks)
    }

    @MainActor @Test func expandedCardsUseTheirFullHeightAndShowTheirTitle() throws {
        let fixture = try MiniPlayerFixture(["a", "b", "c"])
        try fixture.toggleExpansion("Show All Mini Players (3)")
        #expect(fixture.deck.desiredHeight == 230)
        #expect(try fixture.row("b").frame.height == 66)
        #expect(try !fixture.button("Back to Tab — b").isHidden)
    }

    @MainActor @Test(arguments: [false, true])
    func theVolumeSliderOnlyAcceptsInteractionWhileOpen(_ open: Bool) throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        if open { try fixture.toggleVolume(in: "a") }
        fixture.layout()
        let slider = try fixture.volume(in: "a")
        #expect(slider.alphaValue == (open ? 1 : 0))
        #expect(slider.refusesFirstResponder != open)
        #expect(slider.isAccessibilityHidden() != open)
        if !open { #expect(slider.hitTest(CGPoint(x: slider.frame.midX, y: slider.frame.midY)) == nil) }
    }

    @MainActor @Test func losingVolumeCapabilityWithdrawsTheSliderAndItsButton() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        try fixture.toggleVolume(in: "a")
        fixture.engine("a").canSetVolume = false
        try fixture.update(["a"])
        let slider = try fixture.volume(in: "a")
        #expect(slider.isAccessibilityHidden() && slider.refusesFirstResponder)
        #expect(try fixture.button("Adjust Tab Volume").isHidden)
    }

    @MainActor @Test func restoredVolumeCapabilityStartsClosed() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        try fixture.toggleVolume(in: "a")
        fixture.engine("a").canSetVolume = false
        try fixture.update(["a"])
        fixture.engine("a").canSetVolume = true
        try fixture.update(["a"])
        #expect(try fixture.volume(in: "a").alphaValue == 0)
    }

    @MainActor @Test func collapsingWithTheSliderFocusedMovesFocusToTheCard() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        try fixture.toggleExpansion()
        try fixture.toggleVolume(in: "a")
        let slider = try fixture.volume(in: "a")
        try #require(fixture.window.makeFirstResponder(slider))
        try fixture.toggleExpansion("Collapse Mini Players")
        #expect(try fixture.window.firstResponder === fixture.row("a"))
        #expect(fixture.deck.desiredHeight == 62)
    }

    @MainActor @Test func leavingSchedulesOneCollapseAtTheHoverDelay() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        fixture.deck.updateHover(false)
        #expect(fixture.collapses.map(\.delay) == [2])
        #expect(fixture.deck.desiredHeight == 66)
    }

    @MainActor @Test func aStaleHoverOffCannotCloseTheNewHoverSession() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        try fixture.toggleVolume(in: "a")
        fixture.deck.updateHover(false)
        let stale = try #require(fixture.collapses.last)
        fixture.deck.updateHover(true)
        fixture.deck.updateHover(false)
        stale.job()
        fixture.layout()
        #expect(fixture.deck.desiredHeight == 99)
    }

    @MainActor @Test func theDueHoverOffClosesTheVolumeAndReturnsToCompactTransport() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        try fixture.toggleVolume(in: "a")
        fixture.deck.updateHover(false)
        let due = try #require(fixture.collapses.last)
        due.job()
        fixture.layout()
        #expect(fixture.deck.desiredHeight == 33)
        #expect(try fixture.volume(in: "a").alphaValue == 0)
    }

    @MainActor @Test func aDueHoverOffWaitsForFocusToLeaveTheDeck() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        try fixture.toggleExpansion()
        try fixture.toggleVolume(in: "a")
        try #require(fixture.window.makeFirstResponder(fixture.volume(in: "a")))
        fixture.deck.updateHover(false)
        try #require(fixture.collapses.last).job()
        let expandedHeight = fixture.deck.desiredHeight
        #expect(expandedHeight > 62)
        _ = fixture.window.makeFirstResponder(nil)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: fixture.window)
        #expect(fixture.deck.desiredHeight == 62)
    }

    @MainActor @Test func aNewEpisodeAfterDismissalStartsCollapsed() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        try fixture.toggleExpansion()
        try fixture.button("Close Mini Player", in: fixture.row("a")).actionBlock?()
        try fixture.update(["b", "new"])
        #expect(fixture.deck.desiredHeight == 62)
    }

    @MainActor @Test func thePictureInPictureButtonDoesNotRevealTheTab() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        fixture.layout()
        try fixture.button("Open Picture in Picture").actionBlock?()
        #expect(fixture.engine("a").actions.map(\.intValue) == [Int(PCNativeMediaAction.enterPictureInPicture.rawValue)])
        #expect(fixture.revealed.isEmpty)
    }
}

struct SidebarMiniPlayerFocusTests {
    @MainActor @Test func onlyTheFrontCollapsedCardTakesKeyboardFocus() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        #expect(try fixture.row("a").acceptsFirstResponder)
        #expect(try !fixture.row("b").acceptsFirstResponder)
        #expect(try !fixture.row("b").isHidden)
    }

    @MainActor @Test func focusingTheFrontCardMakesEveryExpandedRowReachable() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        let first = try fixture.row("a"), second = try fixture.row("b")
        try #require(fixture.window.makeFirstResponder(first))
        let chain = SidebarAccessibility.keyViews(in: [fixture.deck], space: fixture.deck)
        #expect(try chain.first === fixture.button("Collapse Mini Players"))
        #expect(chain.contains { $0 === second })
    }

    @MainActor @Test func returnOnTheFocusedRowRevealsItsOriginalTab() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        let row = try fixture.row("a")
        try #require(fixture.window.makeFirstResponder(row))
        row.keyDown(with: try fixture.key(36, "\r"))
        #expect(fixture.revealed == ["a"])
    }

    @MainActor @Test func spaceOnTheFocusedRowPausesItsOriginalMedia() throws {
        let fixture = try MiniPlayerFixture(["a", "b"])
        let row = try fixture.row("a")
        try #require(fixture.window.makeFirstResponder(row))
        row.keyDown(with: try fixture.key(49, " "))
        #expect(fixture.engine("a").actions.map(\.intValue) == [Int(PCNativeMediaAction.pause.rawValue)])
    }

    @MainActor @Test func clickingACardRevealsTheTabWithoutTakingKeyboardFocus() throws {
        let fixture = try MiniPlayerFixture(["a"])
        let row = try fixture.row("a")
        row.initiatingEventType = { .leftMouseDown }
        let former = fixture.window.firstResponder
        let accepted = row.becomeFirstResponder()
        #expect(!accepted)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        row.mouseDown(with: event)
        #expect(fixture.revealed == ["a"] && fixture.window.firstResponder === former)
    }

    @MainActor @Test func tabCanFocusACard() throws {
        let fixture = try MiniPlayerFixture(["a"])
        let row = try fixture.row("a")
        row.initiatingEventType = { .keyDown }
        #expect(fixture.window.makeFirstResponder(row))
        #expect(fixture.window.firstResponder === row)
    }

    @MainActor @Test func losingTheCameraHandsFocusToTheNextVisibleControl() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.engine("a").canToggleCamera = true
        try fixture.update(["a"])
        let camera = try fixture.button("Turn Camera On")
        try #require(fixture.window.makeFirstResponder(camera))
        fixture.engine("a").canToggleCamera = false
        try fixture.update(["a"])
        #expect(try fixture.window.firstResponder === fixture.button("Adjust Tab Volume"))
    }

    @MainActor @Test func theLastHiddenControlReturnsFocusToTheCard() throws {
        let fixture = try MiniPlayerFixture(["a"])
        let button = try fixture.button("Adjust Tab Volume")
        try #require(fixture.window.makeFirstResponder(button))
        fixture.engine("a").canSetVolume = false
        try fixture.update(["a"])
        #expect(try fixture.window.firstResponder === fixture.row("a"))
    }
}

struct MiniPlayerRoutingTests {
    @MainActor @Test(arguments: ["cast", "airplay"])
    func theRouteButtonUsesItsOwnChooser(_ route: String) throws {
        let fixture = try MiniPlayerFixture(["a"])
        let engine = fixture.engine("a")
        if route == "cast" { engine.castState = Int(PCNativeCastState.available.rawValue) }
        else { engine.airPlayState = Int(PCNativeAirPlayState.available.rawValue) }
        try fixture.update(["a"])
        let button = try fixture.button(route == "cast" ? "Cast" : "AirPlay", visible: true)
        button.actionBlock?()
        #expect(engine.chooserRequests == [route])
        #expect(button.showsSelectedFill)
    }

    @MainActor @Test func dismissingTheChooserReleasesTheSelectedRouteButton() throws {
        let fixture = try MiniPlayerFixture(["a"])
        let engine = fixture.engine("a")
        engine.castState = Int(PCNativeCastState.available.rawValue)
        try fixture.update(["a"])
        let button = try fixture.button("Cast")
        button.actionBlock?()
        engine.dismissChooser()
        #expect(!button.showsSelectedFill)
    }

    @MainActor @Test(arguments: [(false, "Connecting to Living Room TV"), (true, "Casting to Living Room TV")])
    func anActiveCastNamesItsReceiver(_ connected: Bool, _ label: String) throws {
        let fixture = try MiniPlayerFixture(["a"])
        let engine = fixture.engine("a")
        engine.castState = Int((connected ? PCNativeCastState.connected : .connecting).rawValue)
        engine.castDeviceName = "Living Room TV"
        try fixture.update(["a"])
        let button = try fixture.button(label, visible: true)
        if connected { #expect(button.accessibilityValue() as? String == "Connected") }
    }

    @MainActor @Test func aRefusedActionDoesNotShowAnUnavailableMessageForActiveMedia() throws {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.engine("a").refusesActions = true
        try fixture.button("Pause").actionBlock?()
        #expect(!fixture.descendants(fixture.deck).contains { view in
            (view as? NSTextField)?.stringValue == "This media is no longer available." && !view.isHidden
        })
    }

    @MainActor @Test func theUnavailableMessageClearsWhenTheEpisodeReturns() throws {
        let fixture = try MiniPlayerFixture(["a"])
        let engine = fixture.engine("a"), pause = try fixture.button("Pause")
        engine.available = false
        pause.actionBlock?()
        engine.available = true
        try fixture.update(["a"])
        #expect(!fixture.descendants(fixture.deck).contains { view in
            (view as? NSTextField)?.stringValue == "This media is no longer available." && !view.isHidden
        })
    }
}

struct MiniPlayerVolumeDismissalTests {
    @MainActor private func open() throws -> MiniPlayerFixture {
        let fixture = try MiniPlayerFixture(["a"])
        fixture.deck.updateHover(true)
        try fixture.toggleVolume(in: "a")
        return fixture
    }

    @MainActor private func click(in view: NSView, window: NSWindow) throws -> NSEvent {
        let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @MainActor @Test(arguments: [false, true])
    func aClickOnTheVolumeControlsLeavesDismissalToTheControl(_ slider: Bool) throws {
        let fixture = try open()
        let row = try fixture.row("a")
        let control: NSView = slider ? try fixture.volume(in: "a") : try fixture.button("Adjust Tab Volume")
        var didSchedule = false
        row.scheduleVolumeLayout = { _ in didSchedule = true }
        row.closeVolume(clickedBy: try click(in: control, window: fixture.window))
        #expect(!didSchedule)
        #expect(fixture.deck.desiredHeight == 99)
    }

    @MainActor @Test func clickingAwayKeepsTheVolumeLayoutUntilTheDispatchFinishes() throws {
        let fixture = try open()
        let row = try fixture.row("a")
        let title = try fixture.button("Back to Tab — a")
        var pending: (@MainActor () -> Void)?
        row.scheduleVolumeLayout = { pending = $0 }
        row.closeVolume(clickedBy: try click(in: title, window: fixture.window))
        #expect(fixture.deck.desiredHeight == 99)
        let apply = try #require(pending)
        apply()
        fixture.layout()
        #expect(fixture.deck.desiredHeight == 66)
    }

    @MainActor @Test func escapeClosesTheVolume() throws {
        let fixture = try open()
        let row = try fixture.row("a")
        try #require(fixture.window.makeFirstResponder(row))
        #expect(try row.closeVolume(escape: fixture.key(53, "\u{1b}")))
        fixture.layout()
        #expect(fixture.deck.desiredHeight == 66)
    }
}
