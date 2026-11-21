import Foundation
import Testing
@testable import ParcCore

private final class FakePage {
    let identifier: String
    init(_ identifier: String) { self.identifier = identifier }
}

private struct FakeWindow {
    var pane: FakePage?
    var card: FakePage?
    var cardShown = false
    var exits = 0
    var created = 0

    mutating func apply(_ effects: [TabPeekSession.Effect]) {
        for effect in effects {
            switch effect {
            case .createPage:
                #expect(pane == nil && card == nil, "a page is created only for a tab that has none")
                created += 1
                pane = FakePage("created-\(created)")
            case .presentPage(let id):
                #expect(pane?.identifier == id && card == nil, "the card takes the tab's own page \(id)")
                card = pane; pane = nil; cardShown = true
            case .returnPage(let id):
                #expect(card?.identifier == id && pane == nil, "the tab gets back the page \(id) from the card")
                pane = card; card = nil
            case .exit:
                #expect(cardShown, "only a shown card plays the dismissal motion")
                exits += 1
            case .finish:
                #expect(card == nil, "a card is never removed while it still holds the tab's page")
                cardShown = false
            }
        }
    }
}

struct TabPeekTests {
    @Test static func admission() {
        let id = UUID()
        func plan(_ edit: (inout TabPeekCandidate) -> Void) -> Result<TabPeekPlan, TabPeekRefusal> {
            var candidate = TabPeekCandidate(tabID: id, page: .live("page-a"))
            edit(&candidate)
            return TabPeekAdmission.plan(candidate)
        }
        #expect(plan { _ in } == .success(.present("page-a")), "a live tab presents its own page")
        #expect(plan { $0.page = .unloaded(loadable: true); $0.holder = .nobody } == .success(.load),
               "an unloaded tab loads straight into the Peek")
        #expect(plan { $0.page = .unloaded(loadable: true) } == .success(.load), "an unloaded tab claimed here loads too")
        #expect(plan { $0.page = .unloaded(loadable: false) } == .failure(.unloadable), "a tab with no address can't load")
        #expect(plan { $0.page = .creating } == .failure(.busy), "a page still being created is left alone")
        #expect(plan { $0.page = .failed } == .failure(.failed), "a failed page opens normally, not in Peek")
        #expect(plan { $0.page = .closed } == .failure(.closed), "a closed page can't be shown")
        #expect(plan { $0.holder = .elsewhere(movable: true) } == .success(.moveHere),
               "a page in another window moves here through the transfer first")
        #expect(plan { $0.holder = .elsewhere(movable: false) } == .failure(.heldElsewhere),
               "a page another window can't give up is refused")
        #expect(plan { $0.onScreen = true } == .failure(.onScreen), "a tab already on screen isn't peeked")
        #expect(plan { $0.busy = true } == .failure(.busy), "a closing or moving tab is refused")
        #expect(plan { $0.content = .unsupported } == .failure(.unsupported), "an internal page that isn't a note or Easel is refused")
        #expect(plan { $0.content = .document; $0.page = .live("document") } == .success(.present("document")),
               "an open note or Easel presents its own editor")
        #expect(plan { $0.content = .document; $0.page = .unloaded(loadable: true) } == .success(.load),
               "a note or Easel that isn't open yet opens straight into the Peek")
        #expect(plan { $0.content = .document; $0.page = .failed } == .failure(.failed),
               "a note or Easel that failed to open opens normally, not in Peek")
        #expect(plan { $0.content = .document; $0.onScreen = true } == .failure(.onScreen),
               "a note or Easel already on screen isn't peeked")
        #expect(plan { $0.content = .document; $0.parentCanHost = false } == .failure(.parent),
               "a note or Easel needs a page to float over too")
        #expect(plan { $0.content = .document; $0.holder = .elsewhere(movable: true) } == .success(.moveHere),
               "a note or Easel in another window moves here through the transfer first")
        #expect(plan { $0.content = .document; $0.shown = .peek(canClose: true) } == .success(.replaceShown),
               "a note or Easel replaces a shown Peek")
        #expect(plan { $0.content = .unsupported; $0.shown = .peek(canClose: true) } == .failure(.unsupported),
               "a shown Peek is never closed for a page Peek can't show")
        #expect(plan { $0.inActiveSpace = false } == .failure(.space), "a tab from another Space is refused")
        #expect(plan { $0.profileMatches = false } == .failure(.profile), "a tab from another Profile is refused")
        #expect(plan { $0.parentCanHost = false } == .failure(.parent), "there must be a page to float over")
        #expect(plan { $0.windowAdmits = false } == .failure(.window), "a busy window refuses")
        #expect(plan { $0.windowAdmits = false; $0.shown = .tab(id, canClose: false) } == .success(.alreadyShown),
               "asking again for the shown tab is a no-op")
        #expect(plan { $0.shown = .peek(canClose: true) } == .success(.replaceShown), "a shown Peek is replaced")
        #expect(plan { $0.shown = .tab(UUID(), canClose: true) } == .success(.replaceShown), "another tab's Peek is replaced")
        #expect(plan { $0.shown = .peek(canClose: false) } == .failure(.peekBusy), "a Peek that can't close now keeps its place")
        #expect(plan { $0.shown = .peek(canClose: true); $0.page = .closed } == .failure(.closed),
               "a shown Peek is never closed for a tab that can't open anyway")
        var offered = TabPeekCandidate(tabID: id, page: .live("page-a"))
        #expect(TabPeekAdmission.offers(offered), "the menu offers Open in Peek for a live tab")
        offered.shown = .tab(id, canClose: true)
        #expect(!TabPeekAdmission.offers(offered), "the menu doesn't offer the tab that's already in Peek")
        offered.shown = .none; offered.onScreen = true
        #expect(!TabPeekAdmission.offers(offered), "the menu doesn't offer a refused tab")
        #expect(TabPeekSession(tabID: id, plan: .moveHere) == nil && TabPeekSession(tabID: id, plan: .replaceShown) == nil
               && TabPeekSession(tabID: id, plan: .alreadyShown) == nil, "only present and load start a session")
    }

    @Test static func holdResolution() {
        func resolve(_ edit: (inout TabPeekHoldFacts) -> Void) -> TabPeekResolution {
            var facts = TabPeekHoldFacts()
            edit(&facts)
            return TabPeekHold.resolve(facts)
        }
        #expect(resolve { _ in } == .keep, "a steady Peek stays")
        #expect(resolve { $0.tabDisplayed = true } == .promote, "opening the tab normally promotes the Peek")
        #expect(resolve { $0.parentCurrent = false } == .putBack, "leaving the page underneath puts the tab's page back")
        #expect(resolve { $0.tabUsable = false } == .putBack, "a tab that's closing or moving gets its page back first")
        #expect(resolve { $0.tabUsable = false; $0.tabDisplayed = true } == .putBack, "an unusable tab is never promoted")
        #expect(resolve { $0.windowOpen = false; $0.tabDisplayed = true } == .putBack, "a closing window puts the page back")
        #expect(resolve { $0.pageInCard = false; $0.windowOpen = false } == .drop,
               "a page that left the card is never pulled back by the Peek")
    }

    @Test static func liveRoundTrip() {
        let original = FakePage("page-a")
        var window = FakeWindow(pane: original)
        guard var session = TabPeekSession(tabID: UUID(), plan: .present(original.identifier)) else {
            Issue.record("a live plan starts a session"); return
        }
        window.apply(session.opening)
        #expect(window.card === original && window.pane == nil, "the card shows the very same page object")
        #expect(session.holdsPage && session.loads == 0, "opening a live tab loads nothing")
        window.apply(session.returnRequested())
        #expect(window.pane === original && window.card == nil && !window.cardShown,
               "closing the Peek hands the same page back to its tab")
        #expect(session.loads == 0 && window.created == 0, "the round trip never loads or creates a page")
        #expect(session.returnRequested().isEmpty && session.promote().isEmpty && session.pageReady("page-a").isEmpty,
               "a finished session ignores late requests")
    }

    @Test static func promotion() {
        let original = FakePage("page-a")
        var window = FakeWindow(pane: original)
        guard var session = TabPeekSession(tabID: UUID(), plan: .present(original.identifier)) else {
            Issue.record("a live plan starts a session"); return
        }
        window.apply(session.opening)
        #expect(session.holdsPage, "a shown tab Peek presents its page as a Peek")
        let promoting = session.resolve(.promote)
        #expect(promoting == [.returnPage("page-a"), .exit], "the page returns before the card plays its exit")
        #expect(!session.holdsPage, "an expanded tab Peek stops presenting its page as a Peek in the same step")
        window.apply(promoting)
        #expect(window.pane === original && window.cardShown && window.exits == 1,
               "the tab shows its page while the empty card exits")
        #expect(session.returnRequested().isEmpty && session.resolve(.putBack).isEmpty,
               "a promoting session can't hand the page back twice")
        window.apply(session.exitFinished())
        #expect(!window.cardShown && session.phase == .finished, "the exit's end removes the card")
        #expect(session.exitFinished().isEmpty, "a late exit timer does nothing")
        #expect(window.created == 0 && session.loads == 0, "promotion never reloads")
    }

    @Test static func unloadedLoad() {
        var window = FakeWindow()
        guard var session = TabPeekSession(tabID: UUID(), plan: .load) else {
            Issue.record("an unloaded plan starts a session"); return
        }
        window.apply(session.opening)
        #expect(window.created == 1 && session.loads == 1 && !window.cardShown, "the tab's page is created once")
        #expect(session.returnRequested().isEmpty && session.promote().isEmpty, "nothing returns before the page exists")
        guard let created = window.pane else { Issue.record("the created page belongs to the tab"); return }
        window.apply(session.pageReady(created.identifier))
        #expect(window.card === created && window.cardShown, "the new page goes straight into the card")
        #expect(session.pageReady("page-z").isEmpty, "a second ready signal is ignored")
        window.apply(session.returnRequested())
        #expect(window.pane === created && window.created == 1, "the loaded page stays the tab's page afterwards")

        var abandoned = FakeWindow()
        guard var waiting = TabPeekSession(tabID: UUID(), plan: .load) else { Issue.record("load session"); return }
        abandoned.apply(waiting.opening)
        #expect(waiting.resolve(.putBack).isEmpty && waiting.phase == .finished,
               "leaving before the page is ready abandons the Peek and leaves the page with its tab")
        #expect(waiting.pageReady("created-1").isEmpty && abandoned.pane != nil && !abandoned.cardShown,
               "a page that arrives after abandonment never opens a card")
        guard var selected = TabPeekSession(tabID: UUID(), plan: .load) else { Issue.record("load session"); return }
        #expect(selected.resolve(.promote).isEmpty && selected.phase == .finished,
               "opening the tab normally while it loads just shows it in its tab")
    }

    @Test static func forcedReturns() {
        let original = FakePage("page-a")
        var window = FakeWindow(pane: original)
        guard var session = TabPeekSession(tabID: UUID(), plan: .present(original.identifier)) else {
            Issue.record("a live plan starts a session"); return
        }
        window.apply(session.opening)
        window.apply(session.resolve(.keep))
        #expect(window.card === original, "keep changes nothing")
        window.apply(session.resolve(.putBack))
        #expect(window.pane === original && !window.cardShown && window.exits == 0,
               "a forced return puts the page back without a motion")

        var closing = FakeWindow(pane: FakePage("page-b"))
        guard var closed = TabPeekSession(tabID: UUID(), plan: .present("page-b")) else { Issue.record("session"); return }
        closing.apply(closed.opening)
        closing.card = nil
        closing.apply(closed.resolve(.drop))
        #expect(!closing.cardShown && closing.pane == nil, "a page that closed in the card just removes the card")
        #expect(closed.pageClosed().isEmpty, "a second close signal is ignored")
    }

    @Test static func handBackNeedsAShownCard() {
        func shown() -> (TabPeekSession, FakeWindow)? {
            var window = FakeWindow(pane: FakePage("page-a"))
            guard let session = TabPeekSession(tabID: UUID(), plan: .present("page-a")) else { return nil }
            window.apply(session.opening)
            return (session, window)
        }
        guard var control = shown() else { Issue.record("a live plan starts a session"); return }
        #expect(!control.0.returnRequested().isEmpty, "a shown card's hand-back returns the page")

        let ways: [(String, (inout TabPeekSession) -> [TabPeekSession.Effect])] = [
            ("its hand-back", { $0.returnRequested() }),
            ("a forced return", { $0.resolve(.putBack) }),
            ("its page closing", { $0.pageClosed() }),
            ("its page dropping out of the card", { $0.resolve(.drop) }),
            ("opening its tab", { $0.resolve(.promote) }),
        ]
        for (way, leave) in ways {
            guard var (session, window) = shown() else { Issue.record("a live plan starts a session"); return }
            if way == "its page dropping out of the card" || way == "its page closing" { window.card = nil }
            let effects = leave(&session)
            window.apply(effects)
            #expect(!session.holdsPage, "\(way) ends the shown session")
            #expect(effects.contains(.finish) || effects.contains(.exit),
                   "\(way) removes the card or plays its exit in the same step, so no card outlives its session")
            #expect(window.card == nil, "\(way) never leaves the page in the card")
            #expect(session.returnRequested().isEmpty, "a late hand-back after \(way) has nothing to return")
            window.apply(session.exitFinished())
            #expect(!window.cardShown, "after \(way) the card is gone once any exit ends")
        }
    }

    @Test static func splitAvailability() {
        func refusal(_ edit: (inout TabPeekSplitFacts) -> Void) -> TabPeekSplitRefusal? {
            var facts = TabPeekSplitFacts()
            edit(&facts)
            return TabPeekSplit.refusal(facts)
        }
        #expect(refusal { _ in } == nil, "a tab-backed Peek over a single page offers Split View")
        #expect(refusal { $0.panes = 3 } == nil, "a tab-backed Peek over a three-page split still offers Split View")
        #expect(refusal { $0.panes = 4 } == .full, "four pages is as full as Split View gets, as on the card")
        #expect(refusal { $0.panes = 4; $0.windowReady = false } == .full, "a full split says so even while the window is busy")
        #expect(refusal { $0.peekInteractive = false } == .unavailable, "a Peek that isn't the window's live Peek can't split")
        #expect(refusal { $0.tabUsable = false } == .unavailable, "a tab that's closing, moving or gone can't join the split")
        #expect(refusal { $0.parentSelected = false } == .unavailable, "the page underneath must be on screen to split with")
        #expect(refusal { $0.windowReady = false } == .unavailable, "a popup, full screen page or open Library refuses")
        #expect(refusal { $0.peekInteractive = false; $0.panes = 4 } == .unavailable,
               "a Peek that can't act is unavailable before it is full")
        #expect(TabPeekSplitRefusal.full.toolTip.contains("four pages"), "the full tooltip says why")
        #expect(!TabPeekSplitRefusal.unavailable.toolTip.isEmpty
               && TabPeekSplitRefusal.unavailable.toolTip != TabPeekSplitRefusal.full.toolTip,
               "each refusal has its own tooltip")
    }

    @Test static func replacement() {
        let id = UUID()
        var candidate = TabPeekCandidate(tabID: id, page: .live("page-a"), shown: .peek(canClose: true))
        #expect(TabPeekAdmission.plan(candidate) == .success(.replaceShown), "the shown Peek closes first")
        candidate.shown = .none
        #expect(TabPeekAdmission.plan(candidate) == .success(.present("page-a")),
               "once it's gone the tab's page opens in the single Peek")
        candidate.shown = .tab(UUID(), canClose: true)
        candidate.page = .unloaded(loadable: true)
        #expect(TabPeekAdmission.plan(candidate) == .success(.replaceShown), "another tab's Peek returns first")
    }
}
