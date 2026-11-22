import Foundation
import Testing
@testable import ParcCore

enum BrowserStoreSplitTestsSupport {
    @MainActor static func withTwoSplitTabs(_ body: (BrowserStore, UUID, UUID) throws -> Void) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            try body(store, first, second)
        }
    }
}
