import Foundation

struct CaptureEaselDestination: Equatable {
    let id: UUID
    let title: String
    let lastActive: Date?
    var modifiedAt: Date?

    struct Activity {
        let id: UUID
        let profileID: UUID
        let date: Date
    }

    static func catalog(documents: [EaselSummary], activity: [Activity], profileID: UUID) -> [Self] {
        var dates: [UUID: Date] = [:]
        for item in activity where item.profileID == profileID && item.date.timeIntervalSinceReferenceDate.isFinite {
            dates[item.id] = max(dates[item.id] ?? .distantPast, item.date)
        }
        return documents.map { Self(id: $0.id, title: $0.title, lastActive: dates[$0.id], modifiedAt: $0.modifiedAt) }
    }

    static func ranked(_ destinations: [Self]) -> [Self] {
        destinations.sorted {
            let left = $0.lastActive ?? .distantPast, right = $1.lastActive ?? .distantPast
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
    }
}
