import Foundation

package struct FairPlayIdentitySites: Codable, Equatable {
    package enum Identity: Equatable {
        case safari
        case chrome
        case undecided
    }

    package private(set) var safari: [String]
    package private(set) var chrome: [String]

    package init(safari: [String] = [], chrome: [String] = []) {
        let chromeSites = Set(chrome.compactMap(Self.normalized))
        self.chrome = chromeSites.sorted()
        self.safari = Set(safari.compactMap(Self.normalized)).subtracting(chromeSites).sorted()
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported FairPlay identity version")
        }
        self.init(safari: try container.decode([String].self, forKey: .safari),
                  chrome: try container.decode([String].self, forKey: .chrome))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(safari, forKey: .safari)
        try container.encode(chrome, forKey: .chrome)
    }

    private enum CodingKeys: String, CodingKey { case version, safari, chrome }

    static func normalized(_ site: String) -> String? {
        let value = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let refused = Set("/\\?#@ ")
        guard !value.isEmpty, value.count <= 253, !value.hasPrefix("."), !value.hasSuffix("."),
              value.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7f }),
              !value.contains(where: { refused.contains($0) }) else { return nil }
        return value
    }

    var isEmpty: Bool { safari.isEmpty && chrome.isEmpty }

    package func identity(of site: String) -> Identity {
        guard let site = Self.normalized(site) else { return .undecided }
        if chrome.contains(site) { return .chrome }
        return safari.contains(site) ? .safari : .undecided
    }

    @discardableResult
    package mutating func learn(_ site: String) -> Bool {
        guard let site = Self.normalized(site), !chrome.contains(site), !safari.contains(site) else { return false }
        safari = (safari + [site]).sorted()
        return true
    }

    @discardableResult
    package mutating func useChrome(_ site: String) -> Bool {
        guard let site = Self.normalized(site), !chrome.contains(site) else { return false }
        safari.removeAll { $0 == site }
        chrome = (chrome + [site]).sorted()
        return true
    }

    @discardableResult
    package mutating func useSafari(_ site: String) -> Bool {
        guard let site = Self.normalized(site), !safari.contains(site) || chrome.contains(site) else { return false }
        chrome.removeAll { $0 == site }
        if !safari.contains(site) { safari = (safari + [site]).sorted() }
        return true
    }

    package static func effective(profile: Self, privateChoices: Self) -> Self {
        let ownSafari = Set(privateChoices.safari), ownChrome = Set(privateChoices.chrome)
        let chromeSites = Set(profile.chrome).subtracting(ownSafari).union(ownChrome)
        let safariSites = Set(profile.safari).union(ownSafari).subtracting(chromeSites)
        return Self(safari: Array(safariSites), chrome: Array(chromeSites))
    }

    package func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    package static func decoded(_ data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    package static func isNewerVersion(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int else { return false }
        return version > 1
    }
}
