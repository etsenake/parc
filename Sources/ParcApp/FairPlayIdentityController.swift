import AppKit

@MainActor
final class FairPlayIdentityController {
    static let shared = FairPlayIdentityController()
    static let fileName = "Parc FairPlay Identity.json"

    private var profiles: [String: FairPlayIdentitySites] = [:]
    private var privateChoices: [String: FairPlayIdentitySites] = [:]
    private var unreadable = Set<String>()

    func start(profilePaths: [String]) {
        for path in profilePaths { push(path) }
    }

    func identity(of site: String, profilePath: String, offTheRecord: Bool) -> FairPlayIdentitySites.Identity {
        lists(for: profilePath, offTheRecord: offTheRecord).identity(of: site)
    }

    func didLearn(_ site: String, profilePath: String, offTheRecord: Bool) {
        apply(.learn, site: site, profilePath: profilePath, offTheRecord: offTheRecord)
    }

    func useChromeIdentity(for site: String, profilePath: String, offTheRecord: Bool) {
        apply(.chrome, site: site, profilePath: profilePath, offTheRecord: offTheRecord)
    }

    func useSafariIdentity(for site: String, profilePath: String, offTheRecord: Bool) {
        apply(.safari, site: site, profilePath: profilePath, offTheRecord: offTheRecord)
    }

    func forgetPrivateChoices() {
        let paths = Set(privateChoices.keys).union(profiles.keys)
        privateChoices.removeAll()
        for path in paths.sorted() { push(path) }
    }

    private enum Change { case learn, chrome, safari }

    private func lists(for path: String, offTheRecord: Bool) -> FairPlayIdentitySites {
        let profile = profileSites(path)
        guard offTheRecord else { return profile }
        return .effective(profile: profile, privateChoices: privateChoices[path] ?? FairPlayIdentitySites())
    }

    private func apply(_ change: Change, site: String, profilePath path: String, offTheRecord: Bool) {
        guard !path.isEmpty else { return }
        if change == .learn, lists(for: path, offTheRecord: offTheRecord).identity(of: site) != .undecided { return }
        var sites = offTheRecord ? privateChoices[path] ?? FairPlayIdentitySites() : profileSites(path)
        let changed: Bool
        switch change {
        case .learn: changed = sites.learn(site)
        case .chrome: changed = sites.useChrome(site)
        case .safari: changed = sites.useSafari(site)
        }
        guard changed else { return }
        if offTheRecord {
            privateChoices[path] = sites
        } else {
            profiles[path] = sites
            save(sites, to: path)
        }
        push(path)
    }

    private func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(Self.fileName)
    }

    private func profileSites(_ path: String) -> FairPlayIdentitySites {
        if let sites = profiles[path] { return sites }
        var sites = FairPlayIdentitySites()
        let url = fileURL(path)
        if FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url) {
                if let decoded = FairPlayIdentitySites.decoded(data) {
                    sites = decoded
                } else if FairPlayIdentitySites.isNewerVersion(data) {
                    unreadable.insert(path)
                } else {
                    let stamp = Int(Date().timeIntervalSince1970)
                    let aside = url.appendingPathExtension("damaged-\(stamp)")
                    if (try? FileManager.default.moveItem(at: url, to: aside)) == nil { unreadable.insert(path) }
                }
            } else {
                unreadable.insert(path)
            }
        }
        profiles[path] = sites
        return sites
    }

    private func save(_ sites: FairPlayIdentitySites, to path: String) {
        guard !unreadable.contains(path) else { return }
        do {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try sites.encoded().write(to: fileURL(path), options: .atomic)
        } catch {
            NSLog("Parc could not save FairPlay identity sites: %@", error.localizedDescription)
        }
    }

    private func push(_ path: String) {
        guard !path.isEmpty else { return }
        let profile = profileSites(path)
        PCNativeBrowserApplication.setFairPlayIdentity(safariSites: profile.safari, chromeSites: profile.chrome,
                                                       profilePath: path, offTheRecord: false)
        let shown = lists(for: path, offTheRecord: true)
        PCNativeBrowserApplication.setFairPlayIdentity(safariSites: shown.safari, chromeSites: shown.chrome,
                                                       profilePath: path, offTheRecord: true)
    }
}
