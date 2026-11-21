import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct ParcContextMenuPresenterTests {
    @MainActor final class Session {
        enum Step { case event(NSEvent), run(@MainActor () -> Void) }
        typealias M = ParcContextMenuMetrics
        let menus = ParcContextMenuLayoutTests.Menus()
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
        let anchor = NSRect(x: 40, y: 600, width: 48, height: 32)
        let colors = ParcMenuColors(theme: SpaceTheme())
        var parentShowing = true
        private(set) var presenter: ParcContextMenu?
        private var steps: [Step] = []
        private(set) var timers: [Timer] = []
        private(set) var delays: [TimeInterval] = []
        private(set) var shown: [NSWindow] = []
        private(set) var removed: [NSWindow] = []
        private(set) var ranOut = false

        init() { parent.isReleasedWhenClosed = false }

        func makePresenter() -> ParcContextMenu {
            let presenter = ParcContextMenu(anchor: anchor, regions: [], parent: parent, colors: colors)
            presenter.host.isShowing = { [weak self] _ in self?.parentShowing ?? false }
            presenter.host.nextEvent = { [weak self] in self?.next() }
            presenter.host.postEvent = { [weak self] in guard let self else { return }; steps.insert(.event($0), at: 0) }
            presenter.host.showCard = { [weak self] card, _ in guard let self else { return }; shown.append(card) }
            presenter.host.removeCard = { [weak self] in guard let self else { return }; removed.append($0) }
            presenter.host.animateClose = { _, _, _ in false }
            presenter.host.schedule = { [weak self] interval, body in
                let timer = Timer(timeInterval: interval, repeats: false) { _ in MainActor.assumeIsolated { body() } }
                self?.timers.append(timer)
                self?.delays.append(interval)
                return timer
            }
            self.presenter = presenter
            return presenter
        }

        private func next() -> NSEvent? {
            while !steps.isEmpty {
                switch steps.removeFirst() {
                case .event(let event): return event
                case .run(let body): body()
                }
            }
            ranOut = true
            return key(53)
        }

        func run(_ menu: NSMenu, _ steps: [Step]) -> [String] {
            menus.recorder.log.removeAll()
            self.steps = steps
            let shown = makePresenter().present(menu)
            #expect(shown)
            #expect(!ranOut)
            return menus.recorder.log
        }

        var cardsAreGone: Bool { Set(shown.map(ObjectIdentifier.init)) == Set(removed.map(ObjectIdentifier.init)) }

        func fireTimers() -> Step {
            .run { [weak self] in for timer in self?.timers ?? [] where timer.isValid { timer.fire(); timer.invalidate() } }
        }

        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        func press(_ code: UInt16) -> Step { .event(key(code)) }
        func mouse(_ type: NSEvent.EventType, _ screen: NSPoint) -> Step {
            .event(NSEvent.mouseEvent(with: type, location: screen, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                      context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
        }
        func screenRow(_ view: ParcContextMenuView, _ row: Int, beside: NSRect) -> NSPoint {
            let frame = M.frame(card: view.card.size, reach: view.reach, beside: beside, right: true, regions: []).frame
            return NSPoint(x: frame.minX - M.shadowMargin + view.rows[row].midX, y: frame.minY - M.shadowMargin + view.rows[row].midY)
        }

        lazy var sample = ParcContextMenuView(menu: menus.extensionMenu(), colors: colors)
        var options: NSPoint { screenRow(sample, 4, beside: anchor) }
        var disabled: NSPoint { screenRow(sample, 7, beside: anchor) }
        var siteRow: NSPoint { screenRow(sample, 2, beside: anchor) }
        var rootFrame: NSRect { M.frame(card: sample.card.size, reach: sample.reach, beside: anchor, right: true, regions: []).frame }
        var allSites: NSPoint {
            let siteRect = sample.submenuAnchor(2).offsetBy(dx: rootFrame.minX - M.shadowMargin, dy: rootFrame.minY - M.shadowMargin)
            return screenRow(ParcContextMenuView(menu: sample.items[2].submenu!, colors: colors), 2, beside: siteRect)
        }
        var aim: NSPoint { NSPoint(x: rootFrame.maxX - M.inset - 2, y: options.y) }
        var outside: NSPoint { NSPoint(x: anchor.minX - 200, y: anchor.minY) }
    }

    @Test func arrowsWalkIntoTheSubmenuAndReturnChoosesAfterTheMenuHasClosed() {
        let session = Session()
        let keyed = session.menus.extensionMenu()
        keyed.items[2].submenu?.delegate = session.menus.recorder
        #expect(session.run(keyed, [session.press(125), session.press(125), session.press(124), session.press(125), session.press(36)])
                == ["open root", "open access", "close access", "close root", "perform Always on example.com"])
    }

    @Test func upFromNothingStartsAtTheLastRowSkippingTheSeparatorAndTheDisabledRow() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.press(126), session.press(126), session.press(126), session.press(36)])
                == ["open root", "close root", "perform Unpin"])
    }

    @Test func escapeClosesWithoutChoosing() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.press(53)]) == ["open root", "close root"])
    }

    @Test func aPressOutsideTheCardClosesItWithoutChoosing() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.leftMouseDown, session.outside)]) == ["open root", "close root"])
    }

    @Test func theEnginesCancelEndsTheMenuFromBetweenEvents() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [.run { session.presenter?.cancel() }]) == ["open root", "close root"])
    }

    @Test func itsCardsAreGoneOnceItReturns() {
        let session = Session()
        let keyed = session.menus.extensionMenu()
        _ = session.run(keyed, [session.press(125), session.press(125), session.press(124), session.press(53)])
        #expect(session.shown.count == 2)
        #expect(session.cardsAreGone)
    }

    @Test func noTooltipOutlivesTheMenu() {
        let session = Session()
        _ = session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.disabled), session.fireTimers(), session.press(53)])
        #expect(!NSApp.windows.contains { $0.isVisible && NSStringFromClass(type(of: $0)).hasSuffix("TooltipWindow") })
    }

    @Test func releasingOverARowChoosesIt() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.options), session.mouse(.leftMouseUp, session.options)])
                == ["open root", "close root", "perform Options"])
    }

    @Test func aDisabledRowDoesNothing() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.leftMouseUp, session.disabled), session.press(53)])
                == ["open root", "close root"])
    }

    @Test func draggingFromTheTileIntoTheSubmenuAndReleasingChoosesThere() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.rightMouseDragged, session.siteRow),
                                                            session.mouse(.rightMouseDragged, session.allSites),
                                                            session.mouse(.rightMouseUp, session.allSites)])
                == ["open root", "close root", "perform Always on All Sites"])
    }

    @Test func headingIntoTheSubmenuAcrossTheNextRowKeepsItOpen() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.siteRow), session.mouse(.mouseMoved, session.aim),
                                                            session.mouse(.mouseMoved, session.allSites), session.mouse(.leftMouseUp, session.allSites)])
                == ["open root", "close root", "perform Always on All Sites"])
    }

    @Test func movingStraightToAnotherRowClosesTheSubmenuAtOnce() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.siteRow), session.mouse(.mouseMoved, session.options),
                                                            session.mouse(.leftMouseUp, session.options)])
                == ["open root", "close root", "perform Options"])
    }

    @Test func headingTowardTheSubmenuWaitsTheAimDelayBeforeSwitchingRows() {
        let session = Session()
        _ = session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.siteRow), session.mouse(.mouseMoved, session.aim),
                                                        session.press(53)])
        #expect(session.delays == [ParcContextMenuMetrics.submenuAimDelay])
    }

    @Test func pausingOnTheNextRowSwitchesToIt() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.siteRow), session.mouse(.mouseMoved, session.aim),
                                                            session.fireTimers(), session.mouse(.leftMouseUp, session.aim)])
                == ["open root", "close root", "perform Options"])
    }

    @Test func downMovesInTheParentAndClosesTheHoveredSubmenu() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.siteRow), session.press(125), session.press(36)])
                == ["open root", "close root", "perform Options"])
    }

    @Test func rightGoesIntoTheHoveredSubmenu() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.siteRow), session.press(124), session.press(36)])
                == ["open root", "close root", "perform Ask on Every Visit"])
    }

    @Test func aRowsReasonTooltipWaitsForThePointerToStopAndItsIdleDelay() throws {
        let session = Session()
        _ = session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.disabled), session.press(53)])
        let delay = try #require(session.delays.first)
        guard case .onMouseIdle(let idle) = TooltipConfiguration("reason").behavior else { Issue.record("an idle tooltip"); return }
        #expect(delay == TooltipTiming.pointerStopDelay + idle)
    }

    @Test func aRowsReasonTooltipLeavesTheMenuWorking() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [session.mouse(.mouseMoved, session.disabled), session.fireTimers(),
                                                            session.mouse(.mouseMoved, session.options), session.mouse(.leftMouseUp, session.options)])
                == ["open root", "close root", "perform Options"])
    }

    @Test func aVoiceOverPressOnARowChoosesItAtOnce() {
        let session = Session()
        #expect(session.run(session.menus.extensionMenu(), [.run {
            let card = session.shown.first?.contentView as? ParcContextMenuView
            let element = card?.accessibilityChildren()?.lazy.compactMap { $0 as? NSAccessibilityElement }
                .first { $0.accessibilityLabel() == "Options" }
            _ = element?.accessibilityPerformPress()
        }]) == ["open root", "close root", "perform Options"])
    }

    @Test func aRowWhoseLabelStillHoldsActsOnTheFirstClick() {
        let session = Session()
        let row = session.screenRow(ParcContextMenuView(menu: session.menus.sidePanelMenu(), colors: session.colors), 1, beside: session.anchor)
        #expect(session.run(session.menus.sidePanelMenu(), [session.mouse(.mouseMoved, row), session.mouse(.leftMouseUp, row)])
                == ["open root", "close root", "perform Open Side Panel"])
    }

    @Test func aClickOnARowWhoseLabelJustChangedShowsTheNewLabelFirstAndTheNextClickDoesWhatItSays() {
        let session = Session()
        let row = session.screenRow(ParcContextMenuView(menu: session.menus.sidePanelMenu(), colors: session.colors), 1, beside: session.anchor)
        #expect(session.run(session.menus.sidePanelMenu(), [session.mouse(.mouseMoved, row), .run { session.menus.toggle.open = true },
                                                            session.mouse(.leftMouseUp, row), session.mouse(.leftMouseUp, row)])
                == ["open root", "close root", "perform Close Side Panel"])
    }

    @Test func pointingAtARowPicksUpItsNewLabelSoOneClickDoesWhatItNowSays() {
        let session = Session()
        let row = session.screenRow(ParcContextMenuView(menu: session.menus.sidePanelMenu(), colors: session.colors), 1, beside: session.anchor)
        #expect(session.run(session.menus.sidePanelMenu(), [session.mouse(.mouseMoved, session.outside), .run { session.menus.toggle.open = true },
                                                            session.mouse(.mouseMoved, row), session.mouse(.leftMouseUp, row)])
                == ["open root", "close root", "perform Close Side Panel"])
    }

    @Test func aHiddenParentShowsNothing() {
        let session = Session()
        session.parentShowing = false
        #expect(!session.makePresenter().present(session.menus.extensionMenu()))
        #expect(session.shown.isEmpty)
    }
}
