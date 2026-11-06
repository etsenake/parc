import Foundation

/// Chromium finds an extension's desktop companion (1Password, Bitwarden,
/// Proton Pass) through a manifest in the browser's own NativeMessagingHosts
/// folder. Those apps install manifests only for browsers they know, so
/// Parc's folder stayed empty and 1Password could never reach its app: no app
/// unlock, and with no native port holding it, the extension's worker idled
/// out and reinitialised on every popup and fill. Link the manifests the
///
/// still checks each manifest's allowed extension origins.
enum NativeMessagingHosts {
    static func sourceDirectories(home: URL) -> [URL] {
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let browsers = ["Arc/User Data", "Google/Chrome", "Chromium", "BraveSoftware/Brave-Browser",
                        "Microsoft Edge", "Vivaldi"]
        return browsers.map {
            support.appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        } + ["/Library/Google/Chrome/NativeMessagingHosts", "/Library/Microsoft/Edge/NativeMessagingHosts"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Keeps one link per manifest, to the first source that has it. Real
    /// files and links into other places are the user's and stay untouched;
    /// so does a folder the user pointed elsewhere.
    static func link(engineRoot: URL, sources: [URL], fileManager: FileManager = .default) {
        let folder = engineRoot.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        if (try? fileManager.destinationOfSymbolicLink(atPath: folder.path)) != nil { return }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var wanted: [String: String] = [:]
        for source in sources {
            for name in (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []
            where name.hasSuffix(".json") && wanted[name] == nil {
                let manifest = source.appendingPathComponent(name).path
                if fileManager.fileExists(atPath: manifest) { wanted[name] = manifest }
            }
        }
        let sourcePaths = Set(sources.map(\.path))
        let homeRelative = sources.compactMap { source in
            source.path.range(of: "/Library/Application Support/").map { String(source.path[$0.lowerBound...]) }
        }
        var present = Set<String>()
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let path = folder.appendingPathComponent(name).path
            // Parc's own link names the same manifest in a source folder, or,
            // dangling, in that browser's folder under an old home folder.
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: path) as NSString,
                  destination.lastPathComponent == name,
                  sourcePaths.contains(destination.deletingLastPathComponent)
                    || (!fileManager.fileExists(atPath: path)
                        && homeRelative.contains { destination.deletingLastPathComponent.hasSuffix($0) }) else {
                present.insert(name); continue
            }
            if wanted[name] == destination as String { present.insert(name) } else { try? fileManager.removeItem(atPath: path) }
        }
        for (name, manifest) in wanted where !present.contains(name) {
            try? fileManager.createSymbolicLink(atPath: folder.appendingPathComponent(name).path, withDestinationPath: manifest)
        }
    }
}
