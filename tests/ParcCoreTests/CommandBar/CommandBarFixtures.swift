import Foundation
@testable import ParcCore

enum CommandBarFixtures {
    static func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("parc-\(name)-\(UUID().uuidString)")
    }
}
