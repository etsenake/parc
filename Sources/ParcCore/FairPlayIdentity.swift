import Foundation

/// One browsing context's sites for Safari's identity (docs/fairplay-identity.md).
/// `safari` holds the sites Parc learned need Apple FairPlay; `chrome` holds the
/// sites the user moved back to Chrome's identity, which learning never adds
/// again. A site is a registrable domain as the engine reports it ("netflix.com").
struct FairPlayIdentitySites: Codable, Equatable {
    enum Identity: Equatable {
        /// Pages of the site present Safari's identity.
        case safari
        /// The user chose Chrome's identity for the site.
        case chrome
        /// Neither list names the site; it is Chrome until Parc learns it.
        case undecided
    }

    private(set) var safari: [String]
    private(set) var chrome: [String]

    init(safari: [String] = [], chrome: [String] = []) {
        let chromeSites = Set(chrome.compactMap(Self.normalized))
        self.chrome = chromeSites.sorted()
        self.safari = Set(safari.compactMap(Self.normalized)).subtracting(chromeSites).sorted()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported FairPlay identity version")
        }
        self.init(safari: try container.decode([String].self, forKey: .safari),
                  chrome: try container.decode([String].self, forKey: .chrome))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(safari, forKey: .safari)
        try container.encode(chrome, forKey: .chrome)
    }

    private enum CodingKeys: String, CodingKey { case version, safari, chrome }

    /// A site as the engine compares it: a lowercased canonical host of at most
    /// 253 visible ASCII characters, without leading or trailing dots. Every
    /// host Chromium reports passes, so a site the engine learned is never
    /// dropped here; URL punctuation that can't be in a host is refused.
    static func normalized(_ site: String) -> String? {
        let value = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let refused = Set("/\\?#@ ")
        guard !value.isEmpty, value.count <= 253, !value.hasPrefix("."), !value.hasSuffix("."),
              value.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7f }),
              !value.contains(where: { refused.contains($0) }) else { return nil }
        return value
    }

    var isEmpty: Bool { safari.isEmpty && chrome.isEmpty }

    func identity(of site: String) -> Identity {
        guard let site = Self.normalized(site) else { return .undecided }
        if chrome.contains(site) { return .chrome }
        return safari.contains(site) ? .safari : .undecided
    }

    /// Records a site the engine learned. The user's Chrome choice wins, so a
    /// Chrome site stays Chrome. Returns whether the lists changed.
    @discardableResult
    mutating func learn(_ site: String) -> Bool {
        guard let site = Self.normalized(site), !chrome.contains(site), !safari.contains(site) else { return false }
        safari = (safari + [site]).sorted()
        return true
    }

    /// The user's choice of Chrome's identity for a site. Returns whether the
    /// lists changed.
    @discardableResult
    mutating func useChrome(_ site: String) -> Bool {
        guard let site = Self.normalized(site), !chrome.contains(site) else { return false }
        safari.removeAll { $0 == site }
        chrome = (chrome + [site]).sorted()
        return true
    }

    /// The user's choice of Safari's identity for a site they had moved to
    /// Chrome. Returns whether the lists changed.
    @discardableResult
    mutating func useSafari(_ site: String) -> Bool {
        guard let site = Self.normalized(site), !safari.contains(site) || chrome.contains(site) else { return false }
        chrome.removeAll { $0 == site }
        if !safari.contains(site) { safari = (safari + [site]).sorted() }
        return true
    }

    /// The lists a private window of a Profile uses: the window's own choices
    /// first, then the Profile's. Private choices are never written back.
    static func effective(profile: Self, privateChoices: Self) -> Self {
        let ownSafari = Set(privateChoices.safari), ownChrome = Set(privateChoices.chrome)
        let chromeSites = Set(profile.chrome).subtracting(ownSafari).union(ownChrome)
        let safariSites = Set(profile.safari).union(ownSafari).subtracting(chromeSites)
        return Self(safari: Array(safariSites), chrome: Array(chromeSites))
    }

    /// The file's bytes: pretty, sorted JSON with a version.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Nil for bytes this version cannot read.
    static func decoded(_ data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    /// A readable file written by a newer Parc: a JSON object whose version is
    /// above 1. Such a file is kept as it is, never moved aside or replaced.
    static func isNewerVersion(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int else { return false }
        return version > 1
    }
}
