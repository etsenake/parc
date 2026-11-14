import Foundation

@main struct NewSpaceWindowChoiceTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        typealias Choice = NewSpaceWindowChoice<Int>
        check(Choice.choose(from: []) == .openNew, "No windows opens a new regular window")
        check(Choice.choose(from: [(1, true, false)]) == .openNew, "Only private windows opens a new regular window")
        check(Choice.choose(from: [(1, false, true), (2, true, false)]) == .openNew, "Only popups and private windows opens a new regular window")
        check(Choice.choose(from: [(1, true, false), (2, false, false), (3, false, false)]) == .existing(2), "Frontmost regular window wins over private ones")
        check(Choice.choose(from: [(1, false, true), (2, false, false)]) == .existing(2), "Popups are skipped")
        check(Choice.choose(from: [(7, false, false)]) == .existing(7), "A single regular window is used")
        print("NewSpaceWindowChoiceTests: \(checks) assertions passed")
    }
}
