import Foundation
import ParcTestSupport
import Testing
@testable import ParcSettings

@MainActor
struct SharedQuotePreferencesTests {
    static let key = "parc.sharedQuotes.v1"

    final class Store {
        let defaults: UserDefaults

        init() { defaults = TestDefaults("Parc.SharedQuotes.Checks.")! }
    }

    @Test func anAbsentRecordFallsBackToEnabled() {
        let store = Store()
        let preferences = SharedQuotePreferences(defaults: store.defaults)
        #expect(preferences.state.isEnabled)
        #expect(!preferences.loadError)
    }

    @Test func readingDoesNotCreateStorage() {
        let store = Store()
        _ = SharedQuotePreferences(defaults: store.defaults)
        #expect(store.defaults.object(forKey: Self.key) == nil)
    }

    @Test func disablingPersists() throws {
        let store = Store()
        try SharedQuotePreferences(defaults: store.defaults).setEnabled(false)
        #expect(!SharedQuotePreferences(defaults: store.defaults).state.isEnabled)
    }

    @Test func committingTheSameValueTwiceIsIdempotent() throws {
        let store = Store()
        let preferences = SharedQuotePreferences(defaults: store.defaults)
        try preferences.setEnabled(false)
        let saved = store.defaults.data(forKey: Self.key)
        try preferences.setEnabled(false)
        #expect(store.defaults.data(forKey: Self.key) == saved)
    }

    @Test func enablingPersists() throws {
        let store = Store()
        let preferences = SharedQuotePreferences(defaults: store.defaults)
        try preferences.setEnabled(false)
        try preferences.setEnabled(true)
        #expect(SharedQuotePreferences(defaults: store.defaults).state.isEnabled)
    }

    nonisolated static let malformed: [Data] = [Data("bad".utf8), Data("{\"version\":99,\"isEnabled\":false}".utf8), Data("{}".utf8)]

    @Test(arguments: SharedQuotePreferencesTests.malformed)
    func anUnreadableOrFutureRecordIsReported(record: Data) {
        let store = Store()
        store.defaults.set(record, forKey: Self.key)
        #expect(SharedQuotePreferences(defaults: store.defaults).loadError)
    }

    @Test(arguments: SharedQuotePreferencesTests.malformed)
    func anUnreadableRecordIsPreservedNotOverwritten(record: Data) {
        let store = Store()
        store.defaults.set(record, forKey: Self.key)
        let before = store.defaults.object(forKey: Self.key) as! NSObject
        let unreadable = SharedQuotePreferences(defaults: store.defaults)
        #expect(throws: (any Error).self) { try unreadable.setEnabled(false) }
        #expect((store.defaults.object(forKey: Self.key) as! NSObject).isEqual(before))
    }
}

@MainActor
struct SharedQuoteSessionTests {
    final class Token { var valid = true }

    @MainActor final class Harness {
        var pending: [@MainActor @Sendable () -> Void] = []
        var displayed: Token?
        var session: SharedQuoteSession<Token>!

        init() {
            session = SharedQuoteSession<Token>(valid: { $0.valid }, schedule: { [unowned self] in self.pending.append($0) },
                                                display: { [unowned self] in self.displayed = $0 })
        }

        func drain() {
            let work = pending
            pending.removeAll()
            for item in work { item() }
        }

        func drag(_ token: Token) {
            session.pointer(down: true, tracksSelection: true)
            session.receive(token, reset: false)
        }

        func release() { session.pointer(down: false, tracksSelection: false) }
    }

    func enabled() -> (Harness, Token, Token) {
        let harness = Harness()
        harness.session.setEnabled(true)
        return (harness, Token(), Token())
    }

    @Test func keyboardOnlySelectionBeforeTrackingIsNotShown() {
        let (harness, a, _) = enabled()
        harness.session.receive(a, reset: false)
        harness.drain()
        #expect(harness.displayed == nil)
    }

    @Test func aSingleClickDoesNotInventSelectionTracking() {
        let (harness, a, _) = enabled()
        harness.session.pointer(down: true, tracksSelection: false)
        harness.session.receive(a, reset: false)
        harness.session.pointer(down: false, tracksSelection: false)
        harness.drain()
        #expect(harness.displayed == nil)
    }

    @Test func draggingHoldsPublication() {
        let (harness, a, _) = enabled()
        harness.drag(a)
        harness.drain()
        #expect(harness.displayed == nil)
        #expect(!harness.session.canPerform(a))
    }

    @Test func releaseSchedulesTheDebounceWithoutAcceptingAnUndisplayedAction() {
        let (harness, a, _) = enabled()
        harness.drag(a)
        harness.release()
        #expect(harness.displayed == nil)
        #expect(harness.pending.count == 1)
        #expect(!harness.session.canPerform(a))
    }

    @Test func aReleasedCurrentTokenIsOffered() {
        let (harness, a, _) = enabled()
        harness.drag(a)
        harness.release()
        harness.drain()
        #expect(harness.displayed === a)
        #expect(harness.session.canPerform(a))
    }

    func displaying(_ harness: Harness, _ token: Token) {
        harness.drag(token)
        harness.release()
        harness.drain()
    }

    @Test func anOldSelectionIsRevokedImmediately() {
        let (harness, a, b) = enabled()
        displaying(harness, a)
        harness.session.receive(b, reset: false)
        #expect(harness.displayed == nil)
        #expect(!harness.session.canPerform(a))
    }

    @Test func aNewSelectionWins() {
        let (harness, a, b) = enabled()
        displaying(harness, a)
        harness.session.receive(b, reset: false)
        a.valid = false
        harness.drain()
        #expect(harness.displayed === b)
    }

    @Test func aNativeInvalidTokenIsNeverPublished() {
        let (harness, a, b) = enabled()
        displaying(harness, a)
        harness.session.receive(b, reset: false)
        a.valid = false
        harness.drain()
        harness.session.receive(a, reset: false)
        harness.drain()
        #expect(harness.displayed == nil)
    }

    @Test func disablingCancelsQueuedOutput() {
        let (harness, a, _) = enabled()
        displaying(harness, a)
        harness.session.receive(a, reset: false)
        harness.session.setEnabled(false)
        harness.drain()
        #expect(harness.displayed == nil)
        #expect(!harness.session.canPerform(a))
    }

    @Test func reenablingCanDisplayARetainedValidSelection() {
        let (harness, a, _) = enabled()
        displaying(harness, a)
        harness.session.setEnabled(false)
        harness.drain()
        harness.session.setEnabled(true)
        harness.drain()
        #expect(harness.displayed === a)
    }

    @Test func anOwnerResetCancelsEveryQueuedRevision() {
        let (harness, a, b) = enabled()
        displaying(harness, b)
        harness.session.receive(a, reset: false)
        harness.session.receive(b, reset: false)
        harness.session.reset()
        harness.drain()
        #expect(harness.displayed == nil)
        #expect(!harness.session.canPerform(b))
    }

    @Test func aNewOwnerNeedsItsOwnSelectionGesture() {
        let (harness, _, b) = enabled()
        displaying(harness, b)
        harness.session.reset()
        harness.session.receive(b, reset: false)
        harness.drain()
        #expect(harness.displayed == nil)
    }

    @Test func invalidationDuringTheDelayIsRespected() {
        let (harness, _, b) = enabled()
        harness.drag(b)
        harness.release()
        b.valid = false
        harness.drain()
        #expect(harness.displayed == nil)
    }

    @Test func aNativeLifetimeResetClearsTheRetainedSelection() {
        let (harness, _, b) = enabled()
        displaying(harness, b)
        harness.session.receive(nil, reset: true)
        harness.drain()
        #expect(harness.displayed == nil)
        #expect(harness.session.selection == nil)
    }

    @Test func aNativeResetAlsoClearsTheTrackedGesture() {
        let (harness, _, b) = enabled()
        displaying(harness, b)
        harness.session.receive(nil, reset: true)
        harness.session.receive(b, reset: false)
        harness.drain()
        #expect(harness.displayed == nil)
    }

    @Test func coalescedSelectionInvalidationPreservesActiveDragTracking() {
        let (harness, a, b) = enabled()
        harness.drag(a)
        harness.session.receive(nil, reset: false)
        harness.session.receive(b, reset: false)
        harness.release()
        harness.drain()
        #expect(harness.displayed === b)
    }
}
