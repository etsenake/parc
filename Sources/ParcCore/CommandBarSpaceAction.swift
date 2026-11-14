import Foundation

struct CommandBarSpaceAction: Equatable, Identifiable {
    let spaceID: UUID
    let profileID: UUID
    let name: String
    let symbol: String
    let position: Int
    let needsPositionLabel: Bool

    var id: String { "focus-space:\(profileID.uuidString):\(spaceID.uuidString)" }
    var title: String { "Focus on" }
    var detail: String { needsPositionLabel ? "Space \(position)" : "" }

    func isCurrent(spaces: [BrowserSpace], profiles: [BrowserProfile]) -> Bool {
        profiles.contains { $0.id == profileID }
            && spaces.contains { $0.id == spaceID && $0.profileID == profileID }
    }

    static func snapshot(spaces: [BrowserSpace], profiles: [BrowserProfile]) -> [Self] {
        let names = Dictionary(grouping: spaces, by: { normalized($0.name) })
        return spaces.enumerated().compactMap { offset, space in
            guard profiles.contains(where: { $0.id == space.profileID }) else { return nil }
            return Self(spaceID: space.id, profileID: space.profileID, name: space.name,
                        symbol: space.symbol, position: offset + 1,
                        needsPositionLabel: (names[normalized(space.name)]?.count ?? 0) > 1)
        }
    }

    static func matching(_ actions: [Self], query: String) -> [Self] {
        let query = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return actions.enumerated().filter { _, action in
            let text = normalized("Focus on Space \(action.name)")
            return words.allSatisfy { text.contains($0) }
        }.sorted { lhs, rhs in
            let left = normalized(lhs.element.name).hasPrefix(query)
            let right = normalized(rhs.element.name).hasPrefix(query)
            return left != right ? left : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
