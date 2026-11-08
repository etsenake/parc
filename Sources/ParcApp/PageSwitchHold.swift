import Foundation

///
/// so the outgoing page's picture stays up until the incoming page has drawn
/// (-[WebContentsPaneHostView attachWebContentsHostView:] 0x4737eb4 detaches
/// the previous page into the same overlay). Parc's panes are per tab, so the
/// outgoing panes stay on screen, live, over the incoming ones until each
/// incoming page reports its frame on screen or `cap` runs out.
struct PageSwitchHold<Pane: AnyObject> {
    /// The engine's own wait for an incoming page's frame is the same second.
    static var cap: TimeInterval { 1 }

    /// The outgoing panes still on screen.
    private(set) var held: [Pane] = []
    /// Arranged while the hold was up, so under it and never seen.
    private(set) var covered: [Pane] = []
    /// Incoming pages whose frame has not been reported yet.
    private(set) var waiting: [Pane] = []
    /// Advances with every arrangement, so a cap timer started for an earlier
    /// one cannot end the current hold.
    private(set) var generation = 0

    var isHolding: Bool { !held.isEmpty }

    /// One arrangement change: `leaving` were arranged and now are not,
    /// `arriving` were not arranged and now are, and `drawing` are the
    /// arriving panes whose page will report a frame. Returns the panes to
    /// park now.
    mutating func rearrange(leaving: [Pane], arriving: [Pane], drawing: [Pane], canHold: Bool) -> [Pane] {
        generation += 1
        // A held pane arranged again is simply on screen.
        let returning = arriving.filter { held.containsPane($0) }
        held.removeAll { returning.containsPane($0) }
        let unseen = leaving.filter { covered.containsPane($0) }
        let seen = leaving.filter { !covered.containsPane($0) }
        covered.removeAll { leaving.containsPane($0) }
        waiting.removeAll { leaving.containsPane($0) }
        let incoming = arriving.filter { !returning.containsPane($0) }
        let waits = waiting + incoming.filter { drawing.containsPane($0) }
        guard canHold, !(held.isEmpty && seen.isEmpty), !waits.isEmpty else {
            return end() + leaving
        }
        held += seen
        covered += incoming
        waiting = waits
        return unseen
    }

    /// The pane's page reported its frame on screen. Returns the held panes
    /// to park when that was the last one awaited.
    mutating func presented(_ pane: Pane) -> [Pane] {
        guard isHolding, waiting.containsPane(pane) else { return [] }
        waiting.removeAll { $0 === pane }
        return waiting.isEmpty ? end() : []
    }

    /// The cap started at `generation` ran out.
    mutating func expire(_ generation: Int) -> [Pane] {
        generation == self.generation ? end() : []
    }

    /// Ends the hold; returns the held panes to park.
    mutating func end() -> [Pane] {
        defer { held = []; covered = []; waiting = [] }
        return held
    }
}

private extension Array where Element: AnyObject {
    func containsPane(_ pane: Element) -> Bool { contains { $0 === pane } }
}
