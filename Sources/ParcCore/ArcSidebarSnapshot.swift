import Foundation

package enum ArcSidebarSnapshot {
    package static func sidebarURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }
    package static func preferencesURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Preferences/company.thebrowser.Browser.plist")
    }

    package static func read(home: URL) throws -> (SidebarImport, [String: Any]) {
        try read(sidebarURL(home: home), preferences: preferencesURL(home: home))
    }
    static let maximumSize = 64 * 1024 * 1024

    package static func read(_ source: URL, preferences: URL) throws -> (SidebarImport, [String: Any]) {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("ParcArcImport-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("StorableSidebar.json")
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
            let arc = try SidebarImport(arcData: Data(contentsOf: copy))
            let settings = directory.appendingPathComponent("Preferences.plist")
            guard let size = (try? files.attributesOfItem(atPath: preferences.path))?[.size] as? Int, size <= maximumSize,
                  (try? files.copyItem(at: preferences, to: settings)) != nil,
                  let data = try? Data(contentsOf: settings),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return (arc, [:]) }
            return (arc, values)
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Arc kept changing its sidebar. Try again in a moment."])
    }
}
