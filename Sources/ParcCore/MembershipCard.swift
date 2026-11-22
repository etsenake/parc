import Foundation
import Combine

package struct MembershipCardState: Codable, Equatable {
    package var version = 1
    package var name: String
    package var createdAt: Date
    package var palette: Int
    package var shape: Int
    package var title: String
    package var backgroundBlobInfo: [Int]

    package init(version: Int = 1, name: String, createdAt: Date, palette: Int, shape: Int, title: String, backgroundBlobInfo: [Int]) {
        self.version = version
        self.name = name
        self.createdAt = createdAt
        self.palette = palette
        self.shape = shape
        self.title = title
        self.backgroundBlobInfo = backgroundBlobInfo
    }

    package static let palettes: [[String]] = [
        ["3139FB", "F25E6B", "F2EAE4"], ["C0009F", "25A677", "34E895"],
        ["666789", "6A2794", "F25E6B"], ["25A677", "6CBAD9", "F2EAE4"],
        ["6A2794", "C0009F", "FFD335"], ["A85901", "F29BBB", "FFD335"],
        ["D12D0F", "A85901", "F2EAE4"], ["1C3648", "6CBAD9", "F29BBB"]
    ]
    static let fallbackNumbers = [1, 6, 5, 4, 3, 2, 8, 7]
    package static func validatedName(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= 64,
              !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.union(.newlines).contains($0) }) else {
            throw MembershipCardFailure.invalidName
        }
        return result
    }
    package var isValid: Bool {
        version == 1 && (try? Self.validatedName(name)) == name &&
            Self.palettes.indices.contains(palette) && (1...4).contains(shape) &&
            createdAt.timeIntervalSince1970.isFinite && createdAt.timeIntervalSince1970 >= 0 &&
            !title.isEmpty && title.count <= 64 &&
            !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.union(.newlines).contains($0) }) &&
            backgroundBlobInfo.count == 15 && backgroundBlobInfo.allSatisfy { (1...14).contains($0) }
    }
    package static func make<R: RandomNumberGenerator>(name: String, date: Date, using random: inout R) -> Self {
        let shape = shapeForName(name)
        return Self(name: name, createdAt: date, palette: Int.random(in: 1...7, using: &random),
                    shape: shape, title: randomTitle(using: &random),
                    backgroundBlobInfo: (0..<15).map { _ in Int.random(in: 1...14, using: &random) })
    }
    static func shapeForName(_ name: String) -> Int {
        var lastWord: String?
        name.enumerateSubstrings(in: name.startIndex..<name.endIndex, options: .byWords) { word, _, _, _ in lastWord = word }
        return Int((lastWord?.unicodeScalars.first?.value ?? 0) % 4) + 1
    }
    func regenerated<R: RandomNumberGenerator>(using random: inout R) -> Self {
        var next = self
        let shapes = (1...4).filter { $0 != shape }
        next.shape = shapes[Int.random(in: shapes.indices, using: &random)]
        let palettes = (1...7).filter { $0 != palette }
        next.palette = palettes[Int.random(in: palettes.indices, using: &random)]
        next.title = Self.randomTitle(using: &random)
        next.backgroundBlobInfo = (0..<15).map { _ in Int.random(in: 1...14, using: &random) }
        return next
    }
    private static func randomTitle<R: RandomNumberGenerator>(using random: inout R) -> String {
        adjectives[Int.random(in: adjectives.indices, using: &random)] + " " +
            nouns[Int.random(in: nouns.indices, using: &random)]
    }
    private static let adjectives = [
        "RARE", "MAJESTIC", "SLEEPY", "MYSTERIOUS", "SUGARY", "WORRIED",
        "METHODICAL", "SHY", "MIGHTY", "SAVORY", "LIVELY", "CONFIDENT",
        "HALLOWED", "STATUESQUE", "BREEZY", "SUPREME", "PRECIOUS", "MALLEABLE",
        "HELPFUL", "STRICT", "EXCITED", "UNLIKELY", "NAIVE", "MELODIC",
        "EXUBERANT", "TOWERING", "VIBRANT", "EMO", "BRAVE", "ANCIENT",
        "DEFIANT", "GLOSSY", "SINCERE", "NIMBLE", "FLUFFY", "SPIKY",
        "SOGGY", "VAGUE", "GIFTED", "INDUSTRIOUS", "LOFTY", "BOUNCY",
        "FLASHY", "IMAGINARY", "DAZZLING", "PERSUASIVE", "CHATTY", "CURIOUS",
        "VIBE", "ARTSY",
    ]
    private static let nouns = [
        "CHARMER", "HUNTER", "READER", "ROBOT", "GUEST", "ARTISAN",
        "ROGUE", "PILOT", "TECHNICIAN", "SCHOLAR", "NINJA", "PSYCHIC",
        "TOURIST", "GUIDE", "LIBRARIAN", "DABBLER", "GATHERER", "FLORIST",
        "MAGICIAN", "TROUBLESHOOTER", "DREAMER", "STEWARD", "PERFECTIONIST", "BIG SHOT",
        "WANDERER", "ADVENTURER", "GUARDIAN", "TEACHER", "WIZARD", "CREATOR",
        "ARCHIVIST", "ENDORSER", "OPTIMIST", "INVENTOR", "TACTICIAN", "TINKERER",
        "WARRIOR", "GHOST", "ORACLE", "STRANGER", "GENIUS", "DIRECTOR",
        "CONNOISSEUR", "TRADER", "SPY", "MASTERMIND", "THINKER", "TUTOR",
        "STUDENT", "ARCHITECT",
    ]
}

package enum MembershipCardFailure: LocalizedError {
    case invalidName, unreadable, changed
    package var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a name of 1–64 characters on one line."
        case .unreadable: return "The saved card could not be read. Its existing file has been preserved."
        case .changed: return "The saved card changed. Reload it before trying again."
        }
    }
}

@MainActor
package final class MembershipCardStore: ObservableObject {
    private final class Weak { weak var value: MembershipCardStore?; init(_ value: MembershipCardStore) { self.value = value } }
    private static var owners: [URL: Weak] = [:]
    package static func shared(directory: URL, name: String) -> MembershipCardStore {
        let url = directory.appendingPathComponent("MembershipCard.json").standardizedFileURL
        if let owner = owners[url]?.value { return owner }
        owners = owners.filter { $0.value.value != nil }
        let owner = MembershipCardStore(url: url, initialName: name)
        owners[url] = Weak(owner)
        return owner
    }
    @Published package private(set) var state: MembershipCardState?
    @Published package private(set) var error: String?
    private let url: URL
    private let initialName: String
    private let now: () -> Date
    private let write: (Data, URL) throws -> Void
    private var savedData: Data?

    package init(url: URL, initialName: String, now: @escaping () -> Date = Date.init,
         write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.url = url
        self.initialName = (try? MembershipCardState.validatedName(initialName)) ?? "You"
        self.now = now; self.write = write
        reload()
    }
    package func reload() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(MembershipCardState.self, from: data)
                guard decoded.isValid else { throw MembershipCardFailure.unreadable }
                savedData = data; state = decoded
            } else {
                var random = SystemRandomNumberGenerator()
                let initial = MembershipCardState.make(name: initialName, date: now(), using: &random)
                let data = try JSONEncoder().encode(initial)
                try write(data, url)
                savedData = data; state = initial
            }
            error = nil
        } catch {
            state = nil; self.error = error.localizedDescription
        }
    }
    package func rename(_ name: String, expected: MembershipCardState) throws {
        guard state == expected else { throw MembershipCardFailure.changed }
        var next = expected
        next.name = try MembershipCardState.validatedName(name)
        next.shape = MembershipCardState.shapeForName(next.name)
        try commit(next)
    }
    package func regenerate() throws {
        guard let state else { throw MembershipCardFailure.unreadable }
        var random = SystemRandomNumberGenerator()
        try commit(state.regenerated(using: &random))
    }
    private func commit(_ next: MembershipCardState) throws {
        guard state != nil, next.isValid else { throw MembershipCardFailure.unreadable }
        guard try Data(contentsOf: url) == savedData else { throw MembershipCardFailure.changed }
        let data = try JSONEncoder().encode(next)
        try write(data, url)
        savedData = data; state = next; error = nil
    }
}
