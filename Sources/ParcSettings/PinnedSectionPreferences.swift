import Foundation
import Combine

@MainActor
package final class PinnedSectionPreferences: ObservableObject {
    package static let shared = PinnedSectionPreferences()
    package struct State: Codable, Equatable {
        var version = 1
        package var showsCollapsedIcons = true
    }
    @Published package private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.pinnedSection.v1"
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
    package func setShowsCollapsedIcons(_ shows: Bool) throws {
        guard !loadError else { throw Failure.unavailable }
        guard state.showsCollapsedIcons != shows else { return }
        var next = state; next.showsCollapsedIcons = shows
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }
    package enum Failure: LocalizedError {
        case unavailable
        package var errorDescription: String? { "Pinned section preferences are unavailable. The existing preferences have been preserved." }
    }
}
