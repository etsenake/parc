import Foundation
import Combine

@MainActor
package final class SharedQuotePreferences: ObservableObject {
    package static let shared = SharedQuotePreferences()
    package struct State: Codable, Equatable {
        var version = 1
        package var isEnabled = true
    }
    @Published package private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.sharedQuotes.v1"
    package private(set) var loadError = false
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
    package func setEnabled(_ enabled: Bool) throws {
        guard !loadError else { throw Failure.unavailable }
        guard state.isEnabled != enabled else { return }
        var next = state; next.isEnabled = enabled
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }
    package enum Failure: LocalizedError {
        case unavailable
        package var errorDescription: String? { "Shared Quote preferences are unavailable. The existing preferences have been preserved." }
    }
}

@MainActor
package final class SharedQuoteSession<Token: AnyObject> {
    private(set) var selection: Token?
    private var offered: Token?
    private var mouseDown = false
    private var hasTrackedSelection = false
    private var enabled = false
    private var revision: UInt64 = 0
    private let valid: (Token) -> Bool
    private let schedule: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let display: (Token?) -> Void
    package init(valid: @escaping (Token) -> Bool,
         schedule: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void,
         display: @escaping (Token?) -> Void) {
        self.valid = valid; self.schedule = schedule; self.display = display
    }
    package func setEnabled(_ value: Bool) { enabled = value; update() }
    package func pointer(down: Bool, tracksSelection: Bool) {
        mouseDown = down
        if tracksSelection { hasTrackedSelection = true }
        update()
    }
    package func receive(_ token: Token?, reset: Bool) {
        if reset { hasTrackedSelection = false; mouseDown = false }
        selection = token; update()
    }
    package func reset() { selection = nil; hasTrackedSelection = false; mouseDown = false; update() }
    package func canPerform(_ token: Token) -> Bool { offered === token && isEligible(token) }
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
