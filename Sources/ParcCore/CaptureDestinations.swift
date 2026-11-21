import Foundation

package struct CaptureEaselDestination: Equatable {
    package let id: UUID
    package let title: String
    package let lastActive: Date?
    package var modifiedAt: Date?

    package struct Activity {
        package let id: UUID
        package let profileID: UUID
        package let date: Date

        package init(id: UUID, profileID: UUID, date: Date) {
            self.id = id
            self.profileID = profileID
            self.date = date
        }
    }

    package static func catalog(documents: [EaselSummary], activity: [Activity], profileID: UUID) -> [Self] {
        var dates: [UUID: Date] = [:]
        for item in activity where item.profileID == profileID && item.date.timeIntervalSinceReferenceDate.isFinite {
            dates[item.id] = max(dates[item.id] ?? .distantPast, item.date)
        }
        return documents.map { Self(id: $0.id, title: $0.title, lastActive: dates[$0.id], modifiedAt: $0.modifiedAt) }
    }

    package static func ranked(_ destinations: [Self]) -> [Self] {
        destinations.sorted {
            let left = $0.lastActive ?? .distantPast, right = $1.lastActive ?? .distantPast
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
    }
}
