import Foundation

package struct TabPeekCandidate: Equatable {
    package enum Holder: Equatable { case here, elsewhere(movable: Bool), nobody }
    package enum Page: Equatable { case live(String), creating, unloaded(loadable: Bool), failed, closed }
    package enum Shown: Equatable { case none, peek(canClose: Bool), tab(UUID, canClose: Bool) }
    package enum Content: Equatable { case web, document, unsupported }

    package var tabID: UUID
    package var windowAdmits = true
    package var parentCanHost = true
    package var inActiveSpace = true
    package var profileMatches = true
    package var onScreen = false
    package var busy = false
    package var content = Content.web
    package var holder = Holder.here
    package var page = Page.unloaded(loadable: true)
    package var shown = Shown.none
    package init(tabID: UUID, windowAdmits: Bool = true, parentCanHost: Bool = true, inActiveSpace: Bool = true, profileMatches: Bool = true, onScreen: Bool = false, busy: Bool = false, content: Content = Content.web, holder: Holder = Holder.here, page: Page = Page.unloaded(loadable: true), shown: Shown = Shown.none) {
        self.tabID = tabID
        self.windowAdmits = windowAdmits
        self.parentCanHost = parentCanHost
        self.inActiveSpace = inActiveSpace
        self.profileMatches = profileMatches
        self.onScreen = onScreen
        self.busy = busy
        self.content = content
        self.holder = holder
        self.page = page
        self.shown = shown
    }
}

package enum TabPeekRefusal: Error, Equatable {
    case window, parent, space, profile, onScreen, busy, unsupported, heldElsewhere, failed, closed, unloadable, peekBusy
}

package enum TabPeekPlan: Equatable {
    case present(String)
    case load
    case moveHere
    case replaceShown
    case alreadyShown
}

package enum TabPeekAdmission {
    package static func plan(_ candidate: TabPeekCandidate) -> Result<TabPeekPlan, TabPeekRefusal> {
        if case .tab(let id, _) = candidate.shown, id == candidate.tabID { return .success(.alreadyShown) }
        guard candidate.windowAdmits else { return .failure(.window) }
        guard candidate.parentCanHost else { return .failure(.parent) }
        guard candidate.inActiveSpace else { return .failure(.space) }
        guard candidate.profileMatches else { return .failure(.profile) }
        guard candidate.content != .unsupported else { return .failure(.unsupported) }
        guard !candidate.onScreen else { return .failure(.onScreen) }
        guard !candidate.busy else { return .failure(.busy) }
        let opening: TabPeekPlan
        switch candidate.holder {
        case .elsewhere(let movable):
            guard movable else { return .failure(.heldElsewhere) }
            opening = .moveHere
        case .here, .nobody:
            switch candidate.page {
            case .live(let page): opening = .present(page)
            case .creating: return .failure(.busy)
            case .unloaded(let loadable):
                guard loadable else { return .failure(.unloadable) }
                opening = .load
            case .failed: return .failure(.failed)
            case .closed: return .failure(.closed)
            }
        }
        switch candidate.shown {
        case .none: return .success(opening)
        case .peek(let canClose), .tab(_, let canClose):
            return canClose ? .success(.replaceShown) : .failure(.peekBusy)
        }
    }

    package static func offers(_ candidate: TabPeekCandidate) -> Bool {
        if case .success(let opening) = plan(candidate) { return opening != .alreadyShown }
        return false
    }
}

package struct TabPeekHoldFacts: Equatable {
    package var pageInCard = true
    package var windowOpen = true
    package var tabUsable = true
    package var tabDisplayed = false
    package var parentCurrent = true
    package init(pageInCard: Bool = true, windowOpen: Bool = true, tabUsable: Bool = true, tabDisplayed: Bool = false, parentCurrent: Bool = true) {
        self.pageInCard = pageInCard
        self.windowOpen = windowOpen
        self.tabUsable = tabUsable
        self.tabDisplayed = tabDisplayed
        self.parentCurrent = parentCurrent
    }
}

package enum TabPeekResolution: Equatable { case keep, promote, putBack, drop }

package enum TabPeekHold {
    package static func resolve(_ facts: TabPeekHoldFacts) -> TabPeekResolution {
        guard facts.pageInCard else { return .drop }
        guard facts.windowOpen, facts.tabUsable else { return .putBack }
        if facts.tabDisplayed { return .promote }
        return facts.parentCurrent ? .keep : .putBack
    }
}

package struct TabPeekSession: Equatable {
    package enum Phase: Equatable { case loading, shown, promoting, finished }
    package enum Effect: Equatable {
        case createPage
        case presentPage(String)
        case returnPage(String)
        case exit
        case finish
    }

    package let tabID: UUID
    package private(set) var phase: Phase
    package private(set) var page: String?
    package private(set) var loads: Int

    package init?(tabID: UUID, plan: TabPeekPlan) {
        self.tabID = tabID
        switch plan {
        case .present(let page): phase = .shown; self.page = page; loads = 0
        case .load: phase = .loading; page = nil; loads = 1
        case .moveHere, .replaceShown, .alreadyShown: return nil
        }
    }

    package var opening: [Effect] {
        switch phase {
        case .loading: return [.createPage]
        case .shown: return page.map { [.presentPage($0)] } ?? []
        case .promoting, .finished: return []
        }
    }

    package var holdsPage: Bool { phase == .shown }

    package mutating func pageReady(_ page: String) -> [Effect] {
        guard phase == .loading else { return [] }
        phase = .shown
        self.page = page
        return [.presentPage(page)]
    }

    package mutating func returnRequested() -> [Effect] {
        guard phase == .shown, let page else { return [] }
        phase = .finished
        return [.returnPage(page), .finish]
    }

    package mutating func promote() -> [Effect] {
        guard phase == .shown, let page else { return [] }
        phase = .promoting
        return [.returnPage(page), .exit]
    }

    package mutating func exitFinished() -> [Effect] {
        guard phase == .promoting else { return [] }
        phase = .finished
        return [.finish]
    }

    package mutating func resolve(_ resolution: TabPeekResolution) -> [Effect] {
        switch resolution {
        case .keep: return []
        case .promote:
            if phase == .loading { phase = .finished; return [] }
            return promote()
        case .putBack:
            if phase == .loading { phase = .finished; return [] }
            return returnRequested()
        case .drop: return pageClosed()
        }
    }

    package mutating func pageClosed() -> [Effect] {
        switch phase {
        case .loading: phase = .finished; return []
        case .shown: phase = .finished; return [.finish]
        case .promoting, .finished: return []
        }
    }
}

package struct TabPeekSplitFacts: Equatable {
    package var peekInteractive = true
    package var tabUsable = true
    package var parentSelected = true
    package var panes = 1
    package var windowReady = true
    package init(peekInteractive: Bool = true, tabUsable: Bool = true, parentSelected: Bool = true, panes: Int = 1, windowReady: Bool = true) {
        self.peekInteractive = peekInteractive
        self.tabUsable = tabUsable
        self.parentSelected = parentSelected
        self.panes = panes
        self.windowReady = windowReady
    }
}

package enum TabPeekSplitRefusal: Equatable {
    case unavailable, full

    package var toolTip: String {
        switch self {
        case .unavailable: return "Split View isn't available right now"
        case .full: return "Split View already shows four pages"
        }
    }
}

package enum TabPeekSplit {
    package static let paneLimit = 4

    package static func refusal(_ facts: TabPeekSplitFacts) -> TabPeekSplitRefusal? {
        guard facts.peekInteractive, facts.tabUsable, facts.parentSelected else { return .unavailable }
        if facts.panes >= paneLimit { return .full }
        return facts.windowReady ? nil : .unavailable
    }
}
