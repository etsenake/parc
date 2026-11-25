import Foundation

package struct SidebarImportProfile: Equatable {
    package let key: SidebarImport.ProfileKey
    package let directory: URL
    package let name: String

    package init(key: SidebarImport.ProfileKey, directory: URL, name: String) {
        self.key = key
        self.directory = directory
        self.name = name
    }
}

package enum SidebarEncryptedFormat: Equatable, Sendable { case chromiumSession, diaTabs(profileFolder: String) }

package typealias SidebarDecryptor = @Sendable (URL, SidebarEncryptedFormat) throws -> Data

package enum ChromiumFlavor: Equatable { case chrome, chromium, brave, edge, vivaldi, opera, operaGX, comet, helium }

package enum SidebarImportSource: Equatable {
    case arc, zen, firefox, safari, dia, chromium(ChromiumFlavor)

    package init?(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "company.thebrowser.Browser": self = .arc
        case "app.zen-browser.zen": self = .zen
        case "org.mozilla.firefox": self = .firefox
        case "com.apple.Safari": self = .safari
        case "company.thebrowser.dia": self = .dia
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary":
            self = .chromium(.chrome)
        case "org.chromium.Chromium": self = .chromium(.chromium)
        case "com.brave.Browser": self = .chromium(.brave)
        case "com.microsoft.edgemac": self = .chromium(.edge)
        case "com.vivaldi.Vivaldi": self = .chromium(.vivaldi)
        case "com.operasoftware.Opera": self = .chromium(.opera)
        case "com.operasoftware.OperaGX": self = .chromium(.operaGX)
        case "ai.perplexity.comet": self = .chromium(.comet)
        case "net.imput.helium": self = .chromium(.helium)
        default: return nil
        }
    }

    static let roots: [String: String] = [
        "com.google.Chrome": "Library/Application Support/Google/Chrome",
        "com.google.Chrome.beta": "Library/Application Support/Google/Chrome Beta",
        "com.google.Chrome.dev": "Library/Application Support/Google/Chrome Dev",
        "com.google.Chrome.canary": "Library/Application Support/Google/Chrome Canary",
        "org.chromium.Chromium": "Library/Application Support/Chromium",
        "com.brave.Browser": "Library/Application Support/BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Library/Application Support/Microsoft Edge",
        "com.vivaldi.Vivaldi": "Library/Application Support/Vivaldi",
        "com.operasoftware.Opera": "Library/Application Support/com.operasoftware.Opera",
        "com.operasoftware.OperaGX": "Library/Application Support/com.operasoftware.OperaGX",
        "ai.perplexity.comet": "Library/Application Support/Comet",
        "net.imput.helium": "Library/Application Support/net.imput.helium",
        "company.thebrowser.dia": "Library/Application Support/Dia/User Data",
        "company.thebrowser.Browser": "Library/Application Support/Arc/User Data",
        "app.zen-browser.zen": "Library/Application Support/zen",
        "org.mozilla.firefox": "Library/Application Support/Firefox",
        "com.apple.Safari": "Library/Safari",
    ]

    package static func root(bundleIdentifier: String, home: URL) -> URL? {
        roots[bundleIdentifier].map { home.appendingPathComponent($0, isDirectory: true) }
    }

    package static func profileDirectory(bundleIdentifier: String, directoryName: String, home: URL) -> URL? {
        guard let root = root(bundleIdentifier: bundleIdentifier, home: home),
              !directoryName.isEmpty, !directoryName.contains("/"), directoryName != ".", directoryName != ".." else { return nil }
        let files = FileManager.default
        switch SidebarImportSource(bundleIdentifier: bundleIdentifier) {
        case .zen?, .firefox?:
            return FirefoxProfiles.paths(root: root).first { $0.lastPathComponent == directoryName }
        case .safari?:
            return root
        case .some:
            if directoryName == root.lastPathComponent, files.fileExists(atPath: root.appendingPathComponent("Preferences").path) {
                return root
            }
            let side = root.appendingPathComponent("_side_profiles", isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
            if files.fileExists(atPath: side.path) {
                let nested = side.appendingPathComponent("Default", isDirectory: true)
                return files.fileExists(atPath: nested.appendingPathComponent("Preferences").path) ? nested : side
            }
            return root.appendingPathComponent(directoryName, isDirectory: true)
        case nil:
            return nil
        }
    }

    package func read(bundleIdentifier: String, home: URL, profiles: [SidebarImportProfile],
                      decrypt: SidebarDecryptor?) throws -> SidebarImport {
        switch self {
        case .arc:
            let (arc, preferences) = try ArcSidebarSnapshot.read(home: home)
            var result = arc
            result.autoArchiveHours = SidebarImport.autoArchiveHours(preferences: preferences, profiles: profiles.map(\.key))
            return result
        case .zen: return try ZenSidebarReader.read(profiles: profiles)
        case .firefox: return try FirefoxSidebarReader.read(profiles: profiles)
        case .safari: return try SafariSidebarReader.read(home: home, profiles: profiles)
        case .dia: return try DiaSidebarReader.read(profiles: profiles, decrypt: decrypt)
        case .chromium(let flavor):
            guard let root = Self.root(bundleIdentifier: bundleIdentifier, home: home) else { throw CocoaError(.fileNoSuchFile) }
            return try ChromiumSidebarReader.read(flavor: flavor, root: root, profiles: profiles, decrypt: decrypt)
        }
    }
}
