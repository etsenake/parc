import Foundation

@main
struct SettingsPrettyJSONPersistSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() throws {
        typealias Skip = SettingsPrettyJSONPersistSkip

        let first = Data("{\"version\":1}\n".utf8)
        let same = Data("{\"version\":1}\n".utf8)
        let changed = Data("{\"version\":2}\n".utf8)

        expect(Skip.shouldSkip(previous: nil, next: first) == false,
               "First persist never skips")
        expect(Skip.shouldSkip(previous: first, next: same),
               "Identical encoded bytes are a true no-op skip")
        expect(Skip.shouldSkip(previous: first, next: changed) == false,
               "Changed encoded bytes must still write")
        expect(Skip.shouldSkip(previous: Data(), next: Data()),
               "Identical empty payloads skip")
        expect(Skip.shouldSkip(previous: Data(), next: first) == false,
               "Empty-to-nonempty must still write")

        print("\(assertions) settings pretty JSON persist skip assertions passed")
    }
}
