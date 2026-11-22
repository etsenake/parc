import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SplitLayoutStoreFlushTests {
    @Test(arguments: [false, true])
    func settingSplitLayoutSchedulesOnlyAChangedLayout(changed: Bool) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let saves = DataFixtures.DeferredSave(store)
            let tabs = [store.open("https://left.invalid"), store.open("https://right.invalid")]
            store.setSplit(tabs)
            saves.run(on: store)
            let original = try #require(store.activeSplitLayout)
            let factors = changed ? [0.25, 0.75] : original.widthFactors

            #expect(store.setSplitLayout(orientation: original.orientation, widthFactors: factors))

            #expect(saves.work.count == (changed ? 1 : 0))
            #expect(try BrowserStore(directory: directory).activeSplitLayout == original)
            saves.run(on: store)
            #expect(try BrowserStore(directory: directory).activeSplitLayout?.widthFactors == factors)
        }
    }
}
