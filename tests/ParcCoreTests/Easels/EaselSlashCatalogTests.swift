import Foundation
import Testing
@testable import ParcCore

struct EaselSlashPlacementTests {
    private static let text = EaselRect(x: 100, y: 100, width: 200, height: 60)
    private static let rightBlock = EaselRect(x: 320, y: 90, width: 200, height: 200)

    @Test func objectsLandToTheRightOfTheText() {
        let right = EaselSlashPlacement.frame(size: (100, 80), beside: Self.text, occupied: [Self.text])
        #expect(right.x == 332 && right.y == 100)
    }

    @Test func aCrowdedRightSideDropsTheObjectBelow() {
        let blocked = EaselSlashPlacement.frame(size: (100, 80), beside: Self.text, occupied: [Self.text, Self.rightBlock])
        #expect(blocked.x == 100 && blocked.y == 192)
    }

    @Test func withNoRoomAnywhereTheObjectStillLandsOnTheRight() {
        let crowded = EaselSlashPlacement.frame(size: (100, 80), beside: Self.text,
                                                occupied: [Self.text, Self.rightBlock, EaselRect(x: 90, y: 170, width: 300, height: 200)])
        #expect(crowded.x == 332 && crowded.y == 100)
    }

    @Test func badNumbersFallBackToTheOrigin() {
        #expect(EaselSlashPlacement.frame(size: (10, 10), beside: EaselRect(x: .nan, y: 0, width: 1, height: 1), occupied: []).x == 0)
    }
}
