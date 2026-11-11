import Foundation
import Combine

@MainActor
final class QuitWarningPreferences: ObservableObject {
    static let shared = QuitWarningPreferences()
    struct State: Codable, Equatable {
        var version = 1
        var isEnabled = true
    }
    @Published private(set) var state: State
    private(set) var loadError = false
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

    func setEnabled(_ enabled: Bool) throws {
        guard !loadError else { throw Failure.unavailable }
        guard state.isEnabled != enabled else { return }
        var next = state; next.isEnabled = enabled
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }

    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "The saved quit warning preference could not be read. It has been preserved."
        }
    }
}
