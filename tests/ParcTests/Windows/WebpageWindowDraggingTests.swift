import AppKit
import Testing
@testable import Parc

private let preferenceKey = "parc.webpageWindowDragging.v1"

@MainActor private final class Defaults {
    let suite = "Parc.WindowDragging.Tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: suite)! }

    deinit { defaults.removePersistentDomain(forName: suite) }
}

struct WebpageWindowDraggingTests {
    @MainActor @Test func anAbsentPreferenceFallsBackToEnabledWithoutAnError() {
        let d = Defaults()
        let preferences = WebpageWindowDraggingPreferences(defaults: d.defaults)
        #expect(preferences.state.isEnabled)
        #expect(!preferences.loadError)
    }

    @MainActor @Test func readingDoesNotMaterializeThePreference() {
        let d = Defaults()
        _ = WebpageWindowDraggingPreferences(defaults: d.defaults)
        #expect(d.defaults.object(forKey: preferenceKey) == nil)
    }

    @MainActor @Test func aDisabledPreferencePersists() throws {
        let d = Defaults()
        try WebpageWindowDraggingPreferences(defaults: d.defaults).setEnabled(false)
        #expect(!WebpageWindowDraggingPreferences(defaults: d.defaults).state.isEnabled)
    }

    @MainActor @Test func writingTheSameValueTwiceIsIdempotent() throws {
        let d = Defaults()
        let preferences = WebpageWindowDraggingPreferences(defaults: d.defaults)
        try preferences.setEnabled(false)
        let saved = d.defaults.data(forKey: preferenceKey)
        try preferences.setEnabled(false)
        #expect(d.defaults.data(forKey: preferenceKey) == saved)
    }

    @MainActor @Test func anEnabledPreferencePersists() throws {
        let d = Defaults()
        let preferences = WebpageWindowDraggingPreferences(defaults: d.defaults)
        try preferences.setEnabled(false)
        try preferences.setEnabled(true)
        #expect(WebpageWindowDraggingPreferences(defaults: d.defaults).state.isEnabled)
    }

    private static let malformed: [Any] = ["bad", Data("{\"version\":99,\"isEnabled\":false}".utf8), Data("{}".utf8)]

    @MainActor @Test(arguments: 0..<3)
    func anUnreadableRecordIsReported(_ index: Int) {
        let d = Defaults()
        d.defaults.set(Self.malformed[index], forKey: preferenceKey)
        #expect(WebpageWindowDraggingPreferences(defaults: d.defaults).loadError)
    }

    @MainActor @Test(arguments: 0..<3)
    func malformedOrFutureBytesArePreserved(_ index: Int) {
        let d = Defaults()
        d.defaults.set(Self.malformed[index], forKey: preferenceKey)
        let before = d.defaults.object(forKey: preferenceKey) as! NSObject
        let unreadable = WebpageWindowDraggingPreferences(defaults: d.defaults)
        #expect(throws: (any Error).self) { try unreadable.setEnabled(false) }
        #expect((d.defaults.object(forKey: preferenceKey) as! NSObject).isEqual(before))
    }

    private static let rect = NSRect(x: 0, y: 0, width: 900, height: 600)

    @Test func aPlainPageHasATopDragBand() {
        #expect(WebpageWindowDragState.region(in: Self.rect, topStripHeight: 0) == NSRect(x: 0, y: 0, width: 886, height: 60))
    }

    @Test func aToolbarReducesTheBand() {
        #expect(WebpageWindowDragState.region(in: Self.rect, topStripHeight: 40) == NSRect(x: 0, y: 40, width: 886, height: 20))
    }

    @Test func aSplitHeaderIsExcluded() {
        #expect(WebpageWindowDragState.region(in: Self.rect, topStripHeight: 31).height == 29)
    }

    @Test func aStripThatConsumesTheDragAreaLeavesNoRegion() {
        #expect(WebpageWindowDragState.region(in: Self.rect, topStripHeight: 64).isEmpty)
    }

    @Test func aTinyViewCannotCreateANegativeRegion() {
        #expect(WebpageWindowDragState.region(in: NSRect(x: 0, y: 0, width: 8, height: 12), topStripHeight: 0).isEmpty)
    }

    @Test func plainAndOptionInputPermitDragging() {
        #expect(WebpageWindowDragState.permitsModifiers([]))
        #expect(WebpageWindowDragState.permitsModifiers(.option))
    }

    @Test(arguments: 0..<5)
    func otherModifiersPreserveWebpageInteraction(_ index: Int) {
        let flags: [NSEvent.ModifierFlags] = [.command, .shift, .control, .capsLock, [.option, .shift]]
        #expect(!WebpageWindowDragState.permitsModifiers(flags[index]))
    }

    @Test func anInactiveUpPasses() {
        var state = WebpageWindowDragState()
        let consumed1 = state.consume(.leftMouseUp, deltaX: 0, deltaY: 0)
        #expect(!consumed1)
    }

    @Test func anUncommittedDragIsNotSwallowed() {
        var state = WebpageWindowDragState()
        state.begin(eligible: true)
        #expect(state.phase == .began)
        let consumed2 = state.consume(.leftMouseDragged, deltaX: 5, deltaY: 0)
        #expect(!consumed2)
    }

    @Test func aCommittedDragIsConsumed() {
        var state = WebpageWindowDragState()
        state.begin(eligible: true)
        state.commit()
        let consumed3 = state.consume(.leftMouseDragged, deltaX: 0.6, deltaY: 0.8)
        #expect(consumed3)
    }

    @Test func exactlyOnePointOfMovementPermitsTheUpAndCompletesTheSequence() {
        var state = WebpageWindowDragState()
        state.begin(eligible: true)
        state.commit()
        _ = state.consume(.leftMouseDragged, deltaX: 0.6, deltaY: 0.8)
        let consumed4 = state.consume(.leftMouseUp, deltaX: 0, deltaY: 0)
        #expect(!consumed4)
        #expect(state.phase == .inactive)
    }

    @Test func reversalAccumulatesAbsoluteMovementSoMoreThanOnePointConsumesTheUp() {
        var state = WebpageWindowDragState()
        state.commit()
        let consumed5 = state.consume(.leftMouseDragged, deltaX: -1, deltaY: 0)
        #expect(consumed5)
        let consumed6 = state.consume(.leftMouseDragged, deltaX: 1, deltaY: 0)
        #expect(consumed6)
        let consumed7 = state.consume(.leftMouseUp, deltaX: 0, deltaY: 0)
        #expect(consumed7)
    }

    @Test func otherButtonsAreUnaffected() {
        var state = WebpageWindowDragState()
        state.commit()
        let consumed8 = state.consume(.rightMouseUp, deltaX: 40, deltaY: 0)
        #expect(!consumed8)
    }

    @Test func cancelTerminatesTheAccounting() {
        var state = WebpageWindowDragState()
        state.begin(eligible: true)
        state.cancel()
        #expect(state.phase == .inactive)
    }
}
