import AppKit
import Combine

///
/// full URLs are BoolKey 76. Appearance belongs to the app, including OTR windows.
@MainActor
final class BrowserToolbarPreferences: ObservableObject {
    static let shared = BrowserToolbarPreferences()
    struct State: Codable, Equatable {
        var version = 1
        var isVisible = false
        var showsFullURL = false
    }
    @Published private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.browserToolbar.v1"
    private(set) var loadError = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data else { state = State(); loadError = true; return }
            if let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1 { state = decoded }
            else { state = State(); loadError = true }
        } else { state = State() }
    }
    func setVisible(_ visible: Bool) throws { var next = state; next.isVisible = visible; try commit(next) }
    func setShowsFullURL(_ full: Bool) throws { var next = state; next.showsFullURL = full; try commit(next) }
    private func commit(_ next: State) throws {
        guard !loadError else { throw Failure.unavailable }
        guard state != next else { return }
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Toolbar preferences are unavailable. The existing preferences have been preserved." }
    }
}

/// Presentation only: the URL comes from the original native page. No display
/// string is used to navigate, copy, or identify a page or profile.
struct BrowserToolbarAddress: Equatable {
    let primary: String
    let suffix: String?
    let fullURL: String
    let isWebURL: Bool
    var title: String { primary + (suffix ?? "") }

    init(url: URL?, full: Bool) {
        fullURL = url?.absoluteString ?? ""
        isWebURL = ["http", "https"].contains(url?.scheme?.lowercased() ?? "")
        guard !fullURL.isEmpty else {
            primary = "Search or Enter URL…"; suffix = nil; return
        }
        let short: String
        if isWebURL, let host = url?.host, !host.isEmpty {
            short = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else { short = fullURL }
        let long = Self.longDisplay(fullURL)
        // The original producer splits only an actual prefix. Display strings
        // never become navigation, copy, origin or page-identity inputs.
        if full, !short.isEmpty, long.hasPrefix(short), long.count > short.count {
            primary = short; suffix = String(long.dropFirst(short.count))
        } else { primary = short; suffix = nil }
    }

    private static func longDisplay(_ original: String) -> String {
        var value = original
        if value.hasSuffix("?") { value.removeLast() }
        if value.hasSuffix("/") { value.removeLast() }
        if value.hasPrefix("https://") { value.removeFirst(8) }
        else if value.hasPrefix("http://") { value.removeFirst(7) }
        if value.hasPrefix("www.") { value.removeFirst(4) }
        return value.lowercased()
    }
}
