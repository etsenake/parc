import Foundation

struct AppVersion: Codable, Equatable {
    var version: String
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

struct ReleaseNotesLaunch: Codable, Equatable {
    var lastLaunched: AppVersion
    var pending: AppVersion?
    var lastShown: AppVersion? = nil
    var updatedFrom: AppVersion? = nil

    static func launching(_ current: AppVersion, previous: ReleaseNotesLaunch?, existingData: Bool) -> ReleaseNotesLaunch {
        guard let previous else { return .init(lastLaunched: current, pending: existingData ? current : nil) }
        let pending: AppVersion?, updatedFrom: AppVersion?
        if current.isNewer(than: previous.lastLaunched) {
            let seen = previous.lastShown.map { !current.isNewer(than: $0) } ?? false
            pending = seen ? nil : current
            updatedFrom = previous.pending == nil ? previous.lastLaunched : previous.updatedFrom
        }
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
