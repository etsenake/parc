import Foundation
@testable import ParcCore

enum DataFixtures {
    @MainActor
    final class DeferredSave {
        private(set) var work: [DispatchWorkItem] = []

        init(_ store: BrowserStore) {
            store.scheduleDeferredSave = { [weak self] _, item in self?.work.append(item) }
        }

        func run(on store: BrowserStore) {
            let pending = work
            work.removeAll()
            for item in pending where !item.isCancelled { item.perform() }
            store.flushPendingWrites()
        }
    }

    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}
