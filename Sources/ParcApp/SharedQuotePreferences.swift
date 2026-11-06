import Foundation
import Combine

///
/// Copy URL as Quote command, onboarding audio, or page/script clipboard policy.
@MainActor
final class SharedQuotePreferences: ObservableObject {
    static let shared = SharedQuotePreferences()
    struct State: Codable, Equatable {
        var version = 1
        // Enabled in the installed reference. Factory registration is unrecovered.
        var isEnabled = true
    }
    @Published private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.sharedQuotes.v1"
    private(set) var loadError = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data,
                  let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1 else {
                state = State(); loadError = true; return
            }
            state = decoded
        } else { state = State() }
    }
    func setEnabled(_ enabled: Bool) throws {
        guard !loadError else { throw Failure.unavailable }
        guard state.isEnabled != enabled else { return }
        var next = state; next.isEnabled = enabled
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Shared Quote preferences are unavailable. The existing preferences have been preserved." }
    }
}

/// The recovered controller admits drag/multiple-click selection, waits for
/// mouse release, then debounces on the main queue for 200 ms. It never consumes
/// input. Tokens contain no selected text and are revalidated at delivery/action.
@MainActor
final class SharedQuoteSession<Token: AnyObject> {
    private(set) var selection: Token?
    private var offered: Token?
    private var mouseDown = false
    private var hasTrackedSelection = false
    private var enabled = false
    private var revision: UInt64 = 0
    private let valid: (Token) -> Bool
    private let schedule: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let display: (Token?) -> Void
    init(valid: @escaping (Token) -> Bool,
         schedule: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void,
         display: @escaping (Token?) -> Void) {
        self.valid = valid; self.schedule = schedule; self.display = display
    }
    func setEnabled(_ value: Bool) { enabled = value; update() }
    func pointer(down: Bool, tracksSelection: Bool) {
        mouseDown = down
        if tracksSelection { hasTrackedSelection = true }
        update()
    }
    func receive(_ token: Token?, reset: Bool) {
        if reset { hasTrackedSelection = false; mouseDown = false }
        selection = token; update()
    }
    func reset() { selection = nil; hasTrackedSelection = false; mouseDown = false; update() }
    func canPerform(_ token: Token) -> Bool { offered === token && isEligible(token) }
    private func isEligible(_ token: Token) -> Bool {
        enabled && hasTrackedSelection && !mouseDown && selection === token && valid(token)
    }
    private func update() {
        revision &+= 1
        let generation = revision
        offered = nil; display(nil)
        guard enabled, hasTrackedSelection, !mouseDown, let selection, valid(selection) else { return }
        schedule { [weak self, weak selection] in
            guard let self, let selection, self.revision == generation, self.isEligible(selection) else { return }
            self.offered = selection; self.display(selection)
        }
    }
}
