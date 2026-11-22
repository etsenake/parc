import AppKit
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeDriverTestsEventsAndRows {
    struct PhaseMapping: CustomTestStringConvertible {
        let label: String
        let rawPhase: UInt
        let phase: HistorySwipeEventPhase

        var testDescription: String { label }
    }

    @Test(arguments: [
        PhaseMapping(label: "began", rawPhase: NSEvent.Phase.began.rawValue, phase: .began),
        PhaseMapping(label: "changed", rawPhase: NSEvent.Phase.changed.rawValue, phase: .changed),
        PhaseMapping(label: "mayBegin", rawPhase: NSEvent.Phase.mayBegin.rawValue, phase: .mayBegin),
        PhaseMapping(label: "stationary", rawPhase: NSEvent.Phase.stationary.rawValue, phase: .stationary),
        PhaseMapping(label: "ended", rawPhase: NSEvent.Phase.ended.rawValue, phase: .ended),
        PhaseMapping(label: "cancelled", rawPhase: NSEvent.Phase.cancelled.rawValue, phase: .cancelled),
        PhaseMapping(label: "No phase", rawPhase: 0, phase: .none),
        PhaseMapping(label: "Began and changed together", rawPhase: NSEvent.Phase([.began, .changed]).rawValue, phase: .none),
    ])
    func appKitPhasesMapToSwipePhases(_ sample: PhaseMapping) {
        #expect(HistorySwipeEvents.phase(NSEvent.Phase(rawValue: sample.rawPhase)) == sample.phase)
    }

    @Test
    func historyRowsStartWithTheAdjacentEntry() {
        let rows = HistorySwipeRows(entries: ["a", "b", "c", "d", "e"], currentIndex: 3)
        #expect(rows.current == "d")
        #expect(rows.back == ["c", "b", "a"])
        #expect(rows.forward == ["e"])
    }

    @Test
    func aSingleHistoryEntryHasNoNeighbours() {
        let rows = HistorySwipeRows(entries: ["a"], currentIndex: 0)
        #expect(rows.current == "a")
        #expect(rows.back.isEmpty)
        #expect(rows.forward.isEmpty)
    }

    @Test
    func anInvalidHistoryIndexHasNoRows() {
        let rows = HistorySwipeRows(entries: ["a"], currentIndex: 4)
        #expect(rows.current == nil)
        #expect(rows.back.isEmpty)
        #expect(rows.forward.isEmpty)
    }
}
