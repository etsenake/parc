import Foundation
import Testing
@testable import ParcCore

enum SplitSeparateAllTestsSupport {
    @MainActor final class Fixture {
        let root: URL
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store: BrowserStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-separate-all-" + UUID().uuidString)
            let now = now
            store = try BrowserStore(directory: root, now: { now })
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func reopened() throws -> BrowserStore {
            let now = now
            return try BrowserStore(directory: root, now: { now })
        }
    }
}
