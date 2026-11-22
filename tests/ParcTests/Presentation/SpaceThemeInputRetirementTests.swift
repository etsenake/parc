import AppKit
import Testing
import ParcCore
@testable import Parc
@testable import ParcSidebar

extension SpaceThemeControlTests {
    private func padPoint(_ f: Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.width * 0.8, y: f.pad.bounds.midY) }

    private func cancelledPadThenRotation(_ f: Fixture) throws {
        try f.press(f.pad, padPoint(f))
        var restored = SpaceTheme()
        restored.intensity = 0.3
        f.view.synchronizeTheme(restored)
        f.commits = 0
        f.rotate(.began, 36)
    }

    @Test func aCancelledPadDragCannotEditInsideAFreshRotation() throws {
        let f = try Fixture()
        try cancelledPadThenRotation(f)
        let preview = f.view.theme
        try f.drag(f.pad, padPoint(f))
        #expect(f.view.theme == preview)
    }

    @Test func aCancelledPadReleaseCannotFinishAnotherControlsGesture() throws {
        let f = try Fixture()
        try cancelledPadThenRotation(f)
        try f.drag(f.pad, padPoint(f))
        try f.release(f.pad, padPoint(f))
        #expect(f.commits == 0)
    }

    @Test func theFreshRotationContinuesAndCommitsOnceAfterAStalePadRelease() throws {
        let f = try Fixture()
        try cancelledPadThenRotation(f)
        try f.drag(f.pad, padPoint(f))
        try f.release(f.pad, padPoint(f))
        f.rotate(.changed, 36)
        #expect(Self.near(f.view.theme.noise, 0.1))
        f.rotate(.ended)
        #expect(f.commits == 1)
    }

    enum PendingNoise: CaseIterable { case rotation, wheel }

    private func padAfterPendingNoise(_ f: Fixture, _ pending: PendingNoise) throws -> SpaceTheme {
        try f.hoverCenter()
        switch pending {
        case .rotation: f.rotate(.began, 0.5)
        case .wheel: f.scroll(phase: .began, 1)
        }
        try f.press(f.pad, padPoint(f))
        let preview = f.view.theme
        switch pending {
        case .rotation:
            f.rotate(.changed, 90)
            f.rotate(.ended)
        case .wheel:
            f.delivery.deliver()
        }
        return preview
    }

    @Test(arguments: PendingNoise.allCases)
    func pendingNoiseInputCannotTakeOverANewPadGesture(pending: PendingNoise) throws {
        let f = try Fixture()
        let preview = try padAfterPendingNoise(f, pending)
        #expect(f.view.theme == preview)
        #expect(f.commits == 0)
    }

    @Test(arguments: PendingNoise.allCases)
    func cancellingPendingNoiseKeepsThePadTransaction(pending: PendingNoise) throws {
        let f = try Fixture()
        _ = try padAfterPendingNoise(f, pending)
        try f.release(f.pad, padPoint(f))
        #expect(f.commits == 1)
    }

    @Test func aDiscreteNoiseStepAndTheRotationBeforeItAreSeparateTransactions() throws {
        let f = try Fixture()
        f.rotate(.began, 72)
        #expect(f.noise.accessibilityPerformIncrement())
        #expect(f.commits == 2)
    }

    @Test func aSecondUndoReversesTheWholeRotationBeforeADiscreteStep() throws {
        let f = try Fixture()
        f.rotate(.began, 72)
        _ = f.noise.accessibilityPerformIncrement()
        f.rotate(.changed, 72)
        f.rotate(.ended)
        f.view.undo(nil)
        f.view.undo(nil)
        #expect(f.view.theme.noise == 0)
    }

    private func intensityStepDuringDrag(_ f: Fixture) throws {
        let point = NSPoint(x: 20 + (f.intensity.bounds.width - 40) * 0.4, y: f.intensity.bounds.midY)
        try f.press(f.intensity, point)
        _ = f.intensity.accessibilityPerformIncrement()
    }

    @Test func anIntensityAccessibilityStepBeginsFromTheCompletedDrag() throws {
        let f = try Fixture()
        try intensityStepDuringDrag(f)
        #expect(Self.near(f.view.theme.intensity, 0.45))
    }

    @Test func anIntensityAccessibilityStepRetiresTheDragAndItsRelease() throws {
        let f = try Fixture()
        try intensityStepDuringDrag(f)
        try f.drag(f.intensity, .zero)
        try f.release(f.intensity, .zero)
        #expect(Self.near(f.view.theme.intensity, 0.45))
    }

    @Test func anIntensityAccessibilityStepHasItsOwnUndo() throws {
        let f = try Fixture()
        try intensityStepDuringDrag(f)
        f.view.undo(nil)
        #expect(Self.near(f.view.theme.intensity, 0.4))
    }

    private func arrowDuringPadDrag(_ f: Fixture) throws -> (before: SpaceTheme, after: SpaceTheme) {
        try f.press(f.pad, padPoint(f))
        let before = f.view.theme
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                                keyCode: 125))
        f.pad.keyDown(with: key)
        return (before, f.view.theme)
    }

    @Test func aPadArrowKeyAppliesItsOwnStepAfterAPhysicalDrag() throws {
        let f = try Fixture()
        let step = try arrowDuringPadDrag(f)
        #expect(step.after != step.before)
    }

    @Test func aPadArrowKeyRetiresTheInheritedPointerEvents() throws {
        let f = try Fixture()
        let step = try arrowDuringPadDrag(f)
        try f.drag(f.pad, .zero)
        try f.release(f.pad, .zero)
        #expect(f.view.theme == step.after)
    }

    @Test func aPadArrowKeyHasItsOwnUndo() throws {
        let f = try Fixture()
        let step = try arrowDuringPadDrag(f)
        f.view.undo(nil)
        #expect(f.view.theme == step.before)
    }

    enum NextInput: CaseIterable { case pad, dialDrag, rotation, accessibility }

    private func inputAfterRejectedCommit(_ next: NextInput) throws -> (fixture: Fixture, proposals: Int, continued: Bool) {
        let f = try Fixture()
        var authoritative = SpaceTheme()
        authoritative.noise = 0.2
        authoritative.intensity = 0.3
        var proposals = 0
        f.view.onCommitChange = { _, proposed in
            proposals += 1
            return proposals == 1 ? authoritative : proposed
        }
        try f.press(f.intensity, .zero)
        var continued = false
        switch next {
        case .pad:
            let point = padPoint(f)
            try f.press(f.pad, point)
            let started = f.view.theme
            try f.drag(f.pad, NSPoint(x: point.x, y: point.y + 30))
            continued = f.view.theme != started
            try f.release(f.pad, point)
        case .accessibility:
            _ = f.intensity.accessibilityPerformIncrement()
            continued = Self.near(f.view.theme.intensity, 0.35)
        case .rotation:
            f.rotate(.began, 36)
            f.rotate(.changed, 36)
            continued = Self.near(f.view.theme.noise, 0.3)
            f.rotate(.ended)
        case .dialDrag:
            try f.press(f.noise, NSPoint(x: f.noise.bounds.width - 2, y: f.noise.bounds.midY))
            try f.drag(f.noise, NSPoint(x: f.noise.bounds.midX, y: f.noise.bounds.height - 2))
            try f.drag(f.noise, NSPoint(x: 2, y: f.noise.bounds.midY))
            continued = Self.near(f.view.theme.noise, 0.75)
            try f.release(f.noise, NSPoint(x: f.noise.bounds.midX, y: f.noise.bounds.height - 2))
        }
        return (f, proposals, continued)
    }

    @Test(arguments: NextInput.allCases)
    func newInputContinuesFromTheAuthoritativeThemeAfterARejectedCommit(next: NextInput) throws {
        #expect(try inputAfterRejectedCommit(next).continued)
    }

    @Test(arguments: NextInput.allCases)
    func newInputKeepsItsOwnCommitAfterARejectedCommit(next: NextInput) throws {
        #expect(try inputAfterRejectedCommit(next).proposals == 2)
    }

    @Test(arguments: [NextInput.pad, .dialDrag, .rotation])
    func newInputKeepsTheAuthoritativeUnrelatedFieldsAfterARejectedCommit(next: NextInput) throws {
        #expect(Self.near(try inputAfterRejectedCommit(next).fixture.view.theme.intensity, 0.3))
    }
}
