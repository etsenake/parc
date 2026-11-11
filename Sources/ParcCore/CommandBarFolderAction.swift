import Foundation

struct CommandBarFolderAction: Equatable, Identifiable {
    let folderID: UUID
    let reveal: SidebarItemReveal
    let name: String
    let path: [String]
    let ancestorIDs: [UUID]
    let spaceName: String

    var spaceID: UUID { reveal.spaceID }
    var profileID: UUID { reveal.profileID }
    var id: String {
        (["open-folder", profileID.uuidString, spaceID.uuidString, folderID.uuidString]
            + ancestorIDs.map(\.uuidString)).joined(separator: ":")
    }
    var title: String { "Open" }
    var detail: String { ([spaceName] + path).joined(separator: " › ") }

    func isCurrent(in state: BrowserState, profileID: UUID) -> Bool {
        guard self.profileID == profileID,
              let current = Self.make(folderID: folderID, state: state, profileID: profileID) else { return false }
        return current.reveal == reveal && current.ancestorIDs == ancestorIDs
    }

    static func snapshot(state: BrowserState, profileID: UUID) -> [Self] {
        var result: [Self] = [], seen = Set<UUID>()
        for space in state.spaces where space.profileID == profileID {
            func visit(_ parent: UUID?) {
                for item in SidebarHierarchy.children(in: .init(spaceID: space.id, folderID: parent, section: .pinned), state: state) {
                    guard case .folder(let id) = item, seen.insert(id).inserted else { continue }
                    if let action = make(folderID: id, state: state, profileID: profileID) { result.append(action) }
                    visit(id)
                }
            }
            visit(nil)
        }
        return result
    }

    static func matching(_ actions: [Self], query: String) -> [Self] {
        let query = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return actions.enumerated().filter { _, action in
            let text = normalized("Open Folder \(action.name) \(action.detail)")
            return words.allSatisfy { text.contains($0) }
        }.sorted { lhs, rhs in
            let left = normalized(lhs.element.name).hasPrefix(query)
            let right = normalized(rhs.element.name).hasPrefix(query)
            return left != right ? left : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func make(folderID: UUID, state: BrowserState, profileID: UUID) -> Self? {
        guard let folder = state.folders.first(where: { $0.id == folderID }),
              !folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let space = state.spaces.first(where: { $0.id == folder.spaceID && $0.profileID == profileID }),
              let reveal = SidebarItemReveal(item: .folder(folderID), spaceID: space.id, profileID: profileID, state: state) else { return nil }
        var names: [String] = [], ids: [UUID] = [], seen: Set<UUID> = [folderID]
        var parentID = folder.parentID
        while let id = parentID {
            guard seen.insert(id).inserted,
                  let parent = state.folders.first(where: { $0.id == id && $0.spaceID == space.id }) else { return nil }
            names.insert(parent.name, at: 0); ids.insert(id, at: 0); parentID = parent.parentID
        }
        return Self(folderID: folderID, reveal: reveal, name: folder.name, path: names, ancestorIDs: ids, spaceName: space.name)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
