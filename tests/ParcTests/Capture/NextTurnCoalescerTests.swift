import Testing
@testable import Parc

struct NextTurnCoalescerTests {
    @MainActor private final class Turn {
        var jobs: [@MainActor () -> Void] = []
        lazy var coalescer = NextTurnCoalescer { [weak self] in self?.jobs.append($0) }
        var delivered: [Int] = []

        func advance() {
            let ready = jobs
            jobs.removeAll()
            ready.forEach { $0() }
        }
    }

    @MainActor @Test func anUpdateWaitsForTheNextTurn() {
        let turn = Turn()
        turn.coalescer.schedule { turn.delivered.append(1) }
        #expect(turn.delivered.isEmpty)
        turn.advance()
        #expect(turn.delivered == [1])
    }

    @MainActor @Test func requestsInOneTurnCoalesceIntoTheFirstRefresh() {
        let turn = Turn()
        turn.coalescer.schedule { turn.delivered.append(1) }
        turn.coalescer.schedule { turn.delivered.append(2) }
        turn.advance()
        #expect(turn.delivered == [1])
    }

    @MainActor @Test func anIdleTurnDoesNotRepeatARefresh() {
        let turn = Turn()
        turn.coalescer.schedule { turn.delivered.append(1) }
        turn.advance()
        turn.advance()
        #expect(turn.delivered == [1])
    }

    @MainActor @Test func workRequestedDuringARefreshRunsOneTurnLater() {
        let turn = Turn()
        turn.coalescer.schedule {
            turn.delivered.append(1)
            turn.coalescer.schedule { turn.delivered.append(2) }
        }
        turn.advance()
        #expect(turn.delivered == [1])
        turn.advance()
        #expect(turn.delivered == [1, 2])
    }
}
