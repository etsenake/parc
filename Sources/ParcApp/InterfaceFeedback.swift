import AppKit
import Combine

/// Application appearance preferences, shared by normal and private windows.
/// These do not control webpage audio, onboarding music or native error beeps.
@MainActor
final class InterfaceFeedbackPreferences: ObservableObject {
    static let shared = InterfaceFeedbackPreferences()
    struct State: Codable, Equatable {
        var version = 1
        var playsSoundEffects = true
        var reorderingHaptics = true
    }
    @Published private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.interfaceFeedback.v1"
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
    func setPlaysSoundEffects(_ enabled: Bool) throws { var next = state; next.playsSoundEffects = enabled; try commit(next) }
    func setReorderingHaptics(_ enabled: Bool) throws { var next = state; next.reorderingHaptics = enabled; try commit(next) }
    private func commit(_ next: State) throws {
        guard !loadError else { throw Failure.unavailable }
        guard next != state else { return }
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Feedback preferences are unavailable. The existing preferences have been preserved." }
    }
}

@MainActor
protocol InterfaceCaptureSound: AnyObject {
    var volume: Float { get set }
    @discardableResult func play() -> Bool
}
extension NSSound: InterfaceCaptureSound {}

/// One native cached sound; NSSound owns repeat/overlap behavior. No artificial
/// stop/restart, loop, fade, pending retry or fallback beep is added.
@MainActor
final class InterfaceSoundEffects {
    static let shared = InterfaceSoundEffects(preferences: .shared, isActive: { NSApp?.isActive == true }) {
        guard let url = Bundle.main.url(forResource: "capture", withExtension: "wav", subdirectory: "SoundEffects") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }
    private let preferences: InterfaceFeedbackPreferences
    private let isActive: () -> Bool
    private let load: () -> InterfaceCaptureSound?
    private var capture: InterfaceCaptureSound?
    private var hasPreloaded = false
    init(preferences: InterfaceFeedbackPreferences, isActive: @escaping () -> Bool,
         load: @escaping () -> InterfaceCaptureSound?) {
        self.preferences = preferences; self.isActive = isActive; self.load = load
    }
    func preload() {
        guard !hasPreloaded else { return }
        hasPreloaded = true
        if capture == nil { capture = load() }
    }
    func playCapture() {
        guard isActive(), !preferences.loadError, preferences.state.playsSoundEffects else { return }
        if capture == nil { capture = load() }
        capture?.volume = 0.7
        capture?.play()
    }
}

/// Mirrors the outline owner's distinct child-index stream combined with its
/// live enabled preference. Its history lasts for this sidebar's lifetime:
/// exiting/cancelling a drag does not manufacture another index or a cue.
@MainActor
final class SidebarReorderingFeedback {
    private let indices = PassthroughSubject<Int, Never>()
    private var subscription: AnyCancellable?
    convenience init() {
        self.init(preferences: .shared) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
    init(preferences: InterfaceFeedbackPreferences, perform: @escaping () -> Void) {
        subscription = indices.removeDuplicates()
            .combineLatest(preferences.$state.map { $0.reorderingHaptics && !preferences.loadError }.removeDuplicates())
            .filter { $0.1 }
            .sink { _ in perform() }
    }
    func propose(index: Int) { indices.send(index) }
}
