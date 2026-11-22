import AppKit
import Testing
import ParcCore
@testable import Parc

@MainActor
enum SpaceThemeColorPadTestsSupport {
    static var background: NSPoint { NSPoint(x: 12, y: 12) }

    static func emptySpot(_ f: SpaceThemeControlTests.Fixture) throws -> NSPoint {
        let knobs = try f.knobs().map { try f.drawn($0) }
        let candidates = stride(from: 60.0, through: f.pad.bounds.width - 60, by: 20).flatMap { x in
            stride(from: 80.0, through: f.pad.bounds.height - 80, by: 20).map { NSPoint(x: x, y: $0) }
        }
        return try #require(candidates.first { point in knobs.allSatisfy { SpaceThemeControlTests.distance($0, point) > 60 } })
    }
}
