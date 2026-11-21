import Foundation

enum DataFixtures {
    static let testsRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func fixture(_ path: String) -> URL {
        testsRoot.appendingPathComponent("Fixtures").appendingPathComponent(path)
    }

    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}
