import Foundation

struct TabPeekCandidate: Equatable {
    enum Holder: Equatable { case here, elsewhere(movable: Bool), nobody }
    enum Page: Equatable { case live(String), creating, unloaded(loadable: Bool), failed, closed }
    enum Shown: Equatable { case none, peek(canClose: Bool), tab(UUID, canClose: Bool) }
    enum Content: Equatable { case web, document, unsupported }

    var tabID: UUID
    var windowAdmits = true
    var parentCanHost = true
    var inActiveSpace = true
    var profileMatches = true
    var onScreen = false
    var busy = false
    var content = Content.web
    var holder = Holder.here
    var page = Page.unloaded(loadable: true)
    var shown = Shown.none
}

enum TabPeekRefusal: Error, Equatable {
    case window, parent, space, profile, onScreen, busy, unsupported, heldElsewhere, failed, closed, unloadable, peekBusy
}

enum TabPeekPlan: Equatable {
    case present(String)
    case load
    case moveHere
    case replaceShown
    case alreadyShown
}

enum TabPeekAdmission {
    static func plan(_ candidate: TabPeekCandidate) -> Result<TabPeekPlan, TabPeekRefusal> {
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

    static func offers(_ candidate: TabPeekCandidate) -> Bool {
        if case .success(let opening) = plan(candidate) { return opening != .alreadyShown }
        return false
    }
}

struct TabPeekHoldFacts: Equatable {
    var pageInCard = true
    var windowOpen = true
    var tabUsable = true
    var tabDisplayed = false
    var parentCurrent = true
}

enum TabPeekResolution: Equatable { case keep, promote, putBack, drop }

enum TabPeekHold {
    static func resolve(_ facts: TabPeekHoldFacts) -> TabPeekResolution {
        guard facts.pageInCard else { return .drop }
        guard facts.windowOpen, facts.tabUsable else { return .putBack }
        if facts.tabDisplayed { return .promote }
        return facts.parentCurrent ? .keep : .putBack
    }
}

struct TabPeekSession: Equatable {
    enum Phase: Equatable { case loading, shown, promoting, finished }
    enum Effect: Equatable {
        case createPage
        case presentPage(String)
        case returnPage(String)
        case exit
        case finish
    }

    let tabID: UUID
    private(set) var phase: Phase
    private(set) var page: String?
    private(set) var loads: Int

    init?(tabID: UUID, plan: TabPeekPlan) {
        self.tabID = tabID
        switch plan {
        case .present(let page): phase = .shown; self.page = page; loads = 0
        case .load: phase = .loading; page = nil; loads = 1
        case .moveHere, .replaceShown, .alreadyShown: return nil
        }
    }

    var opening: [Effect] {
        switch phase {
        case .loading: return [.createPage]
        case .shown: return page.map { [.presentPage($0)] } ?? []
        case .promoting, .finished: return []
        }
    }

    var holdsPage: Bool { phase == .shown }

    mutating func pageReady(_ page: String) -> [Effect] {
        guard phase == .loading else { return [] }
        phase = .shown
        self.page = page
        return [.presentPage(page)]
    }

    mutating func returnRequested() -> [Effect] {
        guard phase == .shown, let page else { return [] }
        phase = .finished
        return [.returnPage(page), .finish]
    }

    mutating func promote() -> [Effect] {
        guard phase == .shown, let page else { return [] }
        phase = .promoting
        return [.returnPage(page), .exit]
    }

    mutating func exitFinished() -> [Effect] {
        guard phase == .promoting else { return [] }
        phase = .finished
        return [.finish]
    }

    mutating func resolve(_ resolution: TabPeekResolution) -> [Effect] {
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

    mutating func pageClosed() -> [Effect] {
        switch phase {
        case .loading: phase = .finished; return []
        case .shown: phase = .finished; return [.finish]
        case .promoting, .finished: return []
        }
    }
}

struct TabPeekSplitFacts: Equatable {
    var peekInteractive = true
    var tabUsable = true
    var parentSelected = true
    var panes = 1
    var windowReady = true
}

enum TabPeekSplitRefusal: Equatable {
    case unavailable, full

    var toolTip: String {
        switch self {
        case .unavailable: return "Split View isn't available right now"
        case .full: return "Split View already shows four pages"
        }
    }
}

enum TabPeekSplit {
    static let paneLimit = 4

    static func refusal(_ facts: TabPeekSplitFacts) -> TabPeekSplitRefusal? {
        guard facts.peekInteractive, facts.tabUsable, facts.parentSelected else { return .unavailable }
        if facts.panes >= paneLimit { return .full }
        return facts.windowReady ? nil : .unavailable
    }
}
