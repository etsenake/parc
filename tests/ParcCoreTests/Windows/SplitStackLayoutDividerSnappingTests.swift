import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutDividerSnappingTests {
    private struct SnapStep { let distance: Double; let x: CGFloat; let y: CGFloat }

    private static func run(_ steps: [SnapStep], horizontal: Bool = false) -> (state: SplitDividerSnapState, haptics: [Bool]) {
        var state = SplitDividerSnapState()
        let haptics = steps.map { step in
            state.update(distance: step.distance,
                         velocity: SplitDividerSnapState.velocity(CGPoint(x: step.x, y: step.y), movingHorizontally: horizontal))
        }
        return (state, haptics)
    }

    struct VelocityCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let movingHorizontally: Bool
        let expected: Double
    }

    @Test(arguments: [
        VelocityCase(testDescription: "Sideways speed", movingHorizontally: true, expected: -80),
        VelocityCase(testDescription: "Vertical speed", movingHorizontally: false, expected: 500),
    ])
    func aDividerReadsVelocityAlongItsTravelAxis(_ axis: VelocityCase) {
        #expect(SplitDividerSnapState.velocity(CGPoint(x: -80, y: 500), movingHorizontally: axis.movingHorizontally) == axis.expected)
    }

    @Test func anUpAndDownDividerEasedDownOntoTheCentreSnapsWithOneHaptic() {
        let fromAbove = Self.run([SnapStep(distance: -30, x: 2, y: 400), SnapStep(distance: -6, x: -1, y: 80)])
        #expect(fromAbove.state.isSnapped)
        #expect(fromAbove.haptics == [false, true])
    }

    @Test func easedUpOntoTheCentreFromBelowItSnapsToo() {
        let fromBelow = Self.run([SnapStep(distance: 30, x: -2, y: -400), SnapStep(distance: 6, x: 3, y: -80)])
        #expect(fromBelow.state.isSnapped)
        #expect(fromBelow.haptics == [false, true])
    }

    enum Approach: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case fromBelow = "From below"
        case fromAbove = "From above"

        var testDescription: String { rawValue }
    }

    @Test(arguments: Approach.allCases)
    func oneTwentyPointsPerSecondAlongTheDividersOwnAxisStillSnaps(_ approach: Approach) {
        let fromBelow = approach == .fromBelow
        let steps = fromBelow ? [SnapStep(distance: 30, x: 0, y: -400), SnapStep(distance: 6, x: 0, y: -120)]
                              : [SnapStep(distance: -30, x: 0, y: 400), SnapStep(distance: -6, x: 0, y: 120)]
        #expect(Self.run(steps).state.isSnapped)
    }

    @Test(arguments: Approach.allCases)
    func aQuickDragThroughTheCentrePassesStraightThrough(_ approach: Approach) {
        let fromBelow = approach == .fromBelow
        let steps = fromBelow ? [SnapStep(distance: 30, x: 0, y: -400), SnapStep(distance: 6, x: 0, y: -121)]
                              : [SnapStep(distance: -30, x: 0, y: 400), SnapStep(distance: -6, x: 0, y: 121)]
        let result = Self.run(steps)
        #expect(!result.state.isSnapped)
        #expect(result.haptics == [false, false])
    }

    @Test(arguments: Approach.allCases)
    func easingAwayFromTheCentreNeverSnaps(_ approach: Approach) {
        let up = approach == .fromBelow
        let steps = up ? [SnapStep(distance: -30, x: 0, y: 900), SnapStep(distance: -4, x: 0, y: 900), SnapStep(distance: -6, x: 0, y: -50)]
                       : [SnapStep(distance: 30, x: 0, y: -900), SnapStep(distance: 4, x: 0, y: -900), SnapStep(distance: 6, x: 0, y: 50)]
        let result = Self.run(steps)
        #expect(!result.state.isSnapped)
        #expect(result.haptics == [false, false, false])
    }

    @Test func snappingWaitsUntilTheDividerHasMovedFourteenPointsAway() {
        #expect(!Self.run([SnapStep(distance: -6, x: 0, y: 30)]).state.isSnapped)
    }

    @Test func aSnappedDividerHoldsInsideTheBandThenReleasesWithOneHapticAsItLeaves() {
        var held = Self.run([SnapStep(distance: 30, x: -2, y: -400), SnapStep(distance: 6, x: 3, y: -80)]).state
        let velocity = SplitDividerSnapState.velocity(CGPoint(x: 0, y: -900), movingHorizontally: false)
        let stay = held.update(distance: -10, velocity: velocity)
        let release = held.update(distance: -14, velocity: velocity)
        let beyond = held.update(distance: -40, velocity: velocity)
        #expect(!stay)
        #expect(release)
        #expect(!beyond)
        #expect(!held.isSnapped)
    }

    @Test func aSideBySideDividerSnapsOnItsSidewaysSpeedAlone() {
        let sideways = Self.run([SnapStep(distance: 30, x: -400, y: 0), SnapStep(distance: 6, x: -80, y: 900)], horizontal: true)
        #expect(sideways.state.isSnapped)
        #expect(sideways.haptics == [false, true])
    }

    @Test func aSideBySideDividerEasingAwayDoesNotSnap() {
        let away = Self.run([SnapStep(distance: -30, x: 900, y: 0), SnapStep(distance: -4, x: 900, y: 0), SnapStep(distance: -6, x: -50, y: 900)], horizontal: true)
        #expect(!away.state.isSnapped)
    }
}
