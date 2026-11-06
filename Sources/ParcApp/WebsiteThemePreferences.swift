import Foundation
import Combine

/// Application appearance policy, independent of website/profile preferences.
@MainActor
final class WebsiteThemePreferences: ObservableObject {
    static let shared = WebsiteThemePreferences()
    struct State: Codable, Equatable {
        var version = 1
        //
        //
        var isEnabled = true
    }
    @Published private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.websiteTheme.v1"
    private(set) var loadError = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data,
                  let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1 else {
                // Preserve unknown bytes and withhold sharing until the saved
                // policy is readable; do not silently replace an opt-out.
                state = State(isEnabled: false); loadError = true; return
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
            "The saved website theme preference could not be read. It has been preserved and theme sharing is disabled."
        }
    }
}
