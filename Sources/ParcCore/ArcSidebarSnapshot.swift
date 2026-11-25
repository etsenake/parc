import Foundation

package enum ArcSidebarSnapshot {
    package static func sidebarURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }
    package static func preferencesURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Preferences/company.thebrowser.Browser.plist")
    }
    package static func windowsURL(home: URL) -> URL { sibling("StorableWindows.json", home: home) }
    package static func archiveURL(home: URL) -> URL { sibling("StorableArchiveItems.json", home: home) }
    package static func routingURL(home: URL) -> URL { sibling("StorableLinkRouting.json", home: home) }

    private static func sibling(_ name: String, home: URL) -> URL {
        sidebarURL(home: home).deletingLastPathComponent().appendingPathComponent(name)
    }

    package static func read(home: URL) throws -> (SidebarImport, [String: Any]) {
        try read(sidebarURL(home: home), preferences: preferencesURL(home: home), windows: windowsURL(home: home),
                 archive: archiveURL(home: home), routing: routingURL(home: home))
    }
    static let maximumSize = 64 * 1024 * 1024

    package static func read(_ source: URL, preferences: URL, windows: URL? = nil, archive: URL? = nil,
                             routing: URL? = nil) throws -> (SidebarImport, [String: Any]) {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("ParcArcImport-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let sidebar = try stableCopy(of: source, in: directory)
        func optional(_ url: URL?) -> Data? {
            guard let url, files.fileExists(atPath: url.path) else { return nil }
            return try? stableCopy(of: url, in: directory)
        }
        let arc = try SidebarImport(arcData: sidebar, windows: optional(windows), archive: optional(archive),
                                    routing: optional(routing))
        let settings = directory.appendingPathComponent("Preferences.plist")
        guard let size = (try? files.attributesOfItem(atPath: preferences.path))?[.size] as? Int, size <= maximumSize,
              (try? files.copyItem(at: preferences, to: settings)) != nil,
              let data = try? Data(contentsOf: settings),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return (arc, [:]) }
        return (arc, values)
    }

    private static func stableCopy(of source: URL, in directory: URL) throws -> Data {
        let files = FileManager.default
        let copy = directory.appendingPathComponent(source.lastPathComponent)
        func stamp() throws -> [FileAttributeKey: AnyHashable] {
            let attributes = try files.attributesOfItem(atPath: source.path)
            guard (attributes[.size] as? Int ?? .max) <= maximumSize else { throw CocoaError(.fileReadTooLarge) }
            return attributes.filter { [.size, .modificationDate, .systemFileNumber].contains($0.key) }
                .compactMapValues { $0 as? AnyHashable }
        }
        for attempt in 0..<5 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.2) }
            let before = try stamp()
            try? files.removeItem(at: copy)
            try files.copyItem(at: source, to: copy)
            guard try stamp() == before else { continue }
            return try Data(contentsOf: copy)
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Arc kept changing its sidebar. Try again in a moment."])
    }
}
