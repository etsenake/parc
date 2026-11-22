import Foundation
import Combine

@MainActor
package final class QuitWarningPreferences: ObservableObject {
    package static let shared = QuitWarningPreferences()
    package struct State: Codable, Equatable {
        var version = 1
        package var isEnabled = true
    }
    @Published package private(set) var state: State
    package private(set) var loadError = false
    private let defaults: UserDefaults
    private let key = "parc.quitWarning.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data,
                  let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1 else {
                state = State(isEnabled: true); loadError = true; return
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
        package var errorDescription: String? {
            "The saved quit warning preference could not be read. It has been preserved."
        }
    }
}
