import Foundation

@main @MainActor struct Coalescing {
    static func turn() { RunLoop.main.run(until: Date()) }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        let refresh = NextTurnCoalescer()
        var runs = 0
        refresh.schedule { runs += 1 }
        turn()
        precondition(runs == 1, "a single change refreshes on the next turn (\(runs))")
        for _ in 0..<20 { refresh.schedule { runs += 1 } }
        precondition(runs == 1, "nothing runs inside the burst's own turn")
        turn()
        precondition(runs == 2, "a burst refreshes once (\(runs))")
        turn()
        precondition(runs == 2, "an idle turn does nothing")
        refresh.schedule { runs += 1; refresh.schedule { runs += 1 } }
        turn()
        precondition(runs == 3, "a change during the refresh waits for the next turn (\(runs))")
        turn()
        precondition(runs == 4, "and then runs (\(runs))")
        print("Browser view media coalescing: checks passed")
    }
}
