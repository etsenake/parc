import Foundation
import Testing
@testable import ParcCore

struct SettingsPrettyJSONPersistSkipTests {
    typealias Skip = SettingsPrettyJSONPersistSkip

    let first = Data("{\"version\":1}\n".utf8)
    let same = Data("{\"version\":1}\n".utf8)
    let changed = Data("{\"version\":2}\n".utf8)

    @Test func theFirstPersistNeverSkips() {
        #expect(Skip.shouldSkip(previous: nil, next: first) == false)
    }

    @Test func identicalEncodedBytesAreATrueNoOpSkip() {
        #expect(Skip.shouldSkip(previous: first, next: same))
    }

    @Test func changedEncodedBytesMustStillWrite() {
        #expect(Skip.shouldSkip(previous: first, next: changed) == false)
    }

    @Test func identicalEmptyPayloadsSkip() {
        #expect(Skip.shouldSkip(previous: Data(), next: Data()))
    }

    @Test func emptyToNonEmptyMustStillWrite() {
        #expect(Skip.shouldSkip(previous: Data(), next: first) == false)
    }
}
