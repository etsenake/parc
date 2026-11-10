import Foundation

/// A bundle's version as its Info.plist states it.
struct AppVersion: Codable, Equatable {
    /// CFBundleShortVersionString.
    var version: String
    /// CFBundleVersion.
    var build: String

    init(version: String, build: String) { self.version = version; self.build = build }
    init?(infoDictionary info: [String: Any]?) {
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String else { return nil }
        self.init(version: version, build: build)
    }

    func isNewer(than other: AppVersion) -> Bool {
        switch version.compare(other.version, options: .numeric) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame: return build.compare(other.build, options: .numeric) == .orderedDescending
        }
    }
}

///
/// `pendingReleaseNotesVersionToShow` and `lastReleaseNotesVersionShown` (key
///
/// launched on this data, so a Sparkle update and a Homebrew upgrade both count.
/// The record lives in the data directory rather than the shared defaults
/// domain, so a disposable `--parc-profile` never reads or moves another's.
struct ReleaseNotesLaunch: Codable, Equatable {
    var lastLaunched: AppVersion
    /// The update whose Update Complete! banner hasn't been shown yet.
    var pending: AppVersion?
    /// The last update whose banner was shown, so going back and forth between
    /// two versions doesn't show the same one again.
    var lastShown: AppVersion? = nil
    ///
    /// so What's New can mark the releases in between; unknown when the data's
    /// last run predates this record.
    var updatedFrom: AppVersion? = nil

    /// `existingData` is data an earlier Parc run started on: with no record it
    /// was last run by a Parc older than this record, so this launch is an update.
    static func launching(_ current: AppVersion, previous: ReleaseNotesLaunch?, existingData: Bool) -> ReleaseNotesLaunch {
        guard let previous else { return .init(lastLaunched: current, pending: existingData ? current : nil) }
        let pending: AppVersion?, updatedFrom: AppVersion?
        if current.isNewer(than: previous.lastLaunched) {
            // Never for an update at or below one whose notes were already shown.
            let seen = previous.lastShown.map { !current.isNewer(than: $0) } ?? false
            pending = seen ? nil : current
            // An update over one whose banner never showed: neither one's notes have been seen.
            updatedFrom = previous.pending == nil ? previous.lastLaunched : previous.updatedFrom
        }
        // A relaunch keeps an unshown banner; a downgrade has no notes to show.
        else {
            pending = previous.pending == current ? current : nil
            updatedFrom = previous.updatedFrom
        }
        return .init(lastLaunched: current, pending: pending, lastShown: previous.lastShown,
                     updatedFrom: pending == nil ? nil : updatedFrom)
    }

    mutating func markShown() {
        guard let pending else { return }
        lastShown = pending
        self.pending = nil
        updatedFrom = nil
    }

    static func file(in directory: URL) -> URL { directory.appendingPathComponent("release-notes-launch.json") }
    static func read(in directory: URL) -> ReleaseNotesLaunch? {
        (try? Data(contentsOf: file(in: directory))).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    func write(in directory: URL) {
        try? JSONEncoder().encode(self).write(to: Self.file(in: directory), options: .atomic)
    }
}
