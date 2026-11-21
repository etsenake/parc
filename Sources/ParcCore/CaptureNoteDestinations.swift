import Foundation

package struct CaptureNoteDestination: Equatable, Identifiable {
    package static let catalogLimit = 50

    package let url: URL
    package let title: String
    package let icon: String?
    package let lastActive: Date?
    package let modifiedAt: Date

    package var id: String { "note:" + NoteFilePaths.key(for: url) }

    package struct Activity {
        package let url: URL
        package let profileID: UUID
        package let date: Date

        package init(url: URL, profileID: UUID, date: Date) {
            self.url = url
            self.profileID = profileID
            self.date = date
        }
    }

    package static func catalog(notes: [NoteReference], activity: [Activity], profileID: UUID, limit: Int = catalogLimit) -> [Self] {
        var dates: [String: Date] = [:]
        for item in activity where item.profileID == profileID && item.date.timeIntervalSinceReferenceDate.isFinite {
            let key = NoteFilePaths.key(for: item.url)
            dates[key] = max(dates[key] ?? .distantPast, item.date)
        }
        var seen = Set<String>()
        let destinations = notes.compactMap { note -> Self? in
            let key = NoteFilePaths.key(for: note.url)
            guard seen.insert(key).inserted else { return nil }
            return Self(url: note.url, title: note.title, icon: note.icon, lastActive: dates[key], modifiedAt: note.modifiedAt)
        }
        return Array(ranked(destinations).prefix(max(0, limit)))
    }

    package static func ranked(_ destinations: [Self]) -> [Self] {
        destinations.sorted {
            let left = $0.lastActive ?? .distantPast, right = $1.lastActive ?? .distantPast
            if left != right { return left > right }
            if $0.lastActive == nil, $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.id < $1.id
        }
    }

    package static func search(_ destinations: [Self], query: String) -> [Self] {
        guard !query.isEmpty else { return destinations }
        let query = query.lowercased()
        return destinations.filter { $0.title.lowercased().contains(query) }
    }

    package static func reselect(_ previousID: String?, in destinations: [Self]) -> Self? {
        guard let previousID else { return nil }
        return destinations.first { $0.id == previousID }
    }
}

package enum CaptureNoteTarget: Equatable {
    case newNote
    case note(URL)

    package static let newNoteTitle = "New Note"
    package static let newNoteSymbol = "square.and.pencil"
    package static let noteSymbol = "doc.text"

    package var id: String {
        switch self {
        case .newNote: return "newNote"
        case .note(let url): return "note:" + NoteFilePaths.key(for: url)
        }
    }
}
