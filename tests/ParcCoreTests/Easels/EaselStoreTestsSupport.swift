import Foundation
import Testing
@testable import ParcCore

enum EaselStoreTestsSupport {
    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static func expectThrows(_ message: String, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Void) {
        var threw = false
        do { try body() } catch { threw = true }
        #expect(threw, Comment(rawValue: "Expected error: " + message), sourceLocation: sourceLocation)
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let frame = EaselRect(x: 20, y: 30, width: 120, height: 80)

    static func file(_ directory: URL, _ id: UUID) -> URL {
        directory.appendingPathComponent("documents/" + id.uuidString.lowercased() + ".json")
    }
}
