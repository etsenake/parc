import Foundation

struct BrowserImportRestartIntent: Codable, Equatable {
    let spaceID: UUID
    let profileID: UUID
    let onboarding: Bool
    let replay: Bool
    let sourceBundleID: String
    private enum CodingKeys: String, CodingKey {
        case spaceID, profileID, onboarding, replay, sourceBundleID
    }

    init(destination: BrowserImportDestination, onboarding: Bool, replay: Bool = false,
         sourceBundleID: String = "com.apple.Safari") {
        spaceID = destination.spaceID; profileID = destination.profileID
        self.onboarding = onboarding; self.replay = replay
        self.sourceBundleID = sourceBundleID
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spaceID = try values.decode(UUID.self, forKey: .spaceID)
        profileID = try values.decode(UUID.self, forKey: .profileID)
        onboarding = try values.decode(Bool.self, forKey: .onboarding)
        replay = try values.decodeIfPresent(Bool.self, forKey: .replay) ?? false
        sourceBundleID = try values.decodeIfPresent(String.self, forKey: .sourceBundleID) ?? "com.apple.Safari"
    }
    var destination: BrowserImportDestination {
        BrowserImportDestination(spaceID: spaceID, profileID: profileID)
    }
    private static func file(in directory: URL) -> URL {
        directory.appendingPathComponent("PendingBrowserImportRestart.json")
    }
    func save(in directory: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.file(in: directory), options: .atomic)
    }
    static func take(from directory: URL) throws -> Self? {
        let file = file(in: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
    static func remove(from directory: URL) {
        try? FileManager.default.removeItem(at: file(in: directory))
    }
}
