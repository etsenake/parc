import AppKit

struct PageSwitchHold<Pane: AnyObject> {
    static var cap: TimeInterval { 1 }

    private(set) var held: [Pane] = []
    private(set) var covered: [Pane] = []
    private(set) var waiting: [Pane] = []
    private(set) var began: TimeInterval?
    private(set) var hold = 0

    var isHolding: Bool { !held.isEmpty }
    var deadline: TimeInterval? { began.map { $0 + Self.cap } }

    mutating func rearrange(leaving: [Pane], arriving: [Pane], drawing: [Pane], canHold: Bool,
                            now: TimeInterval) -> [Pane] {
        let returning = arriving.filter { held.containsPane($0) }
        held.removeAll { returning.containsPane($0) }
        let unseen = leaving.filter { covered.containsPane($0) }
        let seen = leaving.filter { !covered.containsPane($0) }
        covered.removeAll { leaving.containsPane($0) }
        waiting.removeAll { leaving.containsPane($0) }
        let incoming = arriving.filter { !returning.containsPane($0) }
        let waits = waiting + incoming.filter { drawing.containsPane($0) }
        let expired = deadline.map { now >= $0 } ?? false
        guard canHold, !expired, !(held.isEmpty && seen.isEmpty), !waits.isEmpty else {
            return end() + leaving
        }
        held += seen
        covered += incoming
        waiting = waits
        if began == nil {
            began = now
            hold += 1
        }
        return unseen
    }

    mutating func presented(_ pane: Pane) -> [Pane] {
        guard isHolding, waiting.containsPane(pane) else { return [] }
        waiting.removeAll { $0 === pane }
        return waiting.isEmpty ? end() : []
    }

    mutating func expire(at now: TimeInterval) -> [Pane] {
        guard let deadline, now >= deadline else { return [] }
        return end()
    }

    mutating func end() -> [Pane] {
        defer { held = []; covered = []; waiting = []; began = nil }
        return held
    }
}

enum HeldPaneLayout {
    static let followsPageArea: NSView.AutoresizingMask =
        [.width, .height, .minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
    static func apply(_ held: Bool, to pane: NSView) {
        pane.wantsLayer = true
        pane.layer?.zPosition = held ? 1 : 0
        pane.autoresizingMask = held ? followsPageArea : []
    }
}

private extension Array where Element: AnyObject {
    func containsPane(_ pane: Element) -> Bool { contains { $0 === pane } }
}
