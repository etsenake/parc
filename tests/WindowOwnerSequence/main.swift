import Foundation

@main @MainActor struct WindowOwnerSequenceTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var live = true, key = true, secure = true
        var performed: [Int] = []
        func valid() -> Bool { live && key && secure }
        let complete = WindowOwnerSequence.run(while: valid, steps: [
            { performed.append(1) }, { performed.append(2) }
        ])
        precondition(complete && performed == [1, 2])
        performed = []; key = false
        precondition(!WindowOwnerSequence.run(while: valid, steps: [{ performed.append(1) }]))
        precondition(performed.isEmpty)
        key = true
        let shifted = WindowOwnerSequence.run(while: valid, steps: [
            { performed.append(1); key = false }, { performed.append(2) }
        ])
        precondition(!shifted && performed == [1])
        performed = []; key = true
        let reserved = WindowOwnerSequence.run(while: valid, steps: [
            { performed.append(1); secure = false }, { performed.append(2) }
        ])
        precondition(!reserved && performed == [1])
        performed = []; secure = true
        let retired = WindowOwnerSequence.run(while: valid, steps: [
            { performed.append(1); live = false }
        ])
        precondition(!retired && performed == [1])
        print("Window-owner sequence: completion and owner, key, security interruptions passed")
    }
}
