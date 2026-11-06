import Foundation

/// Capture ranks the original local documents by Sidebar activity, independently
/// of the document's modification date. Missing activity sorts at distantPast.
struct CaptureEaselDestination: Equatable {
    let id: UUID
    let title: String
    let lastActive: Date?

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
        return documents.map { Self(id: $0.id, title: $0.title, lastActive: dates[$0.id]) }
    }

    static func ranked(_ destinations: [Self]) -> [Self] {
        destinations.sorted {
            let left = $0.lastActive ?? .distantPast, right = $1.lastActive ?? .distantPast
            // Local UUID order makes equal/unknown activity deterministic.
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
    }
}

enum CaptureDestinationAction: Equatable {
    case library, copy, save, message, edit, crop, frame, removeFrame, retake, newEasel, expand
    case easel(UUID, String)

    var id: String {
        switch self {
        case .easel(let id, _): return "easel:" + id.uuidString
        case .library: return "library"
        case .copy: return "copy"
        case .save: return "save"
        case .message: return "message"
        case .edit: return "edit"
        case .crop: return "crop"
        case .frame: return "frame"
        case .removeFrame: return "removeFrame"
        case .retake: return "retake"
        case .newEasel: return "newEasel"
        case .expand: return "expand"
        }
    }
    var title: String {
        switch self {
        case .library: return "Save to Library"
        case .copy: return "Copy"
        case .save: return "Save…"
        case .message: return "Send via iMessage…"
        case .edit: return "Edit"
        case .crop: return "Crop"
        case .frame: return "Frame in Portrait Mode"
        case .removeFrame: return "Remove Frame"
        case .retake: return "Retake"
        case .newEasel: return "New Easel"
        case .expand: return "Show More"
        case .easel(_, let title): return title
        }
    }
    var symbol: String {
        switch self {
        case .library: return "circle"
        case .copy: return "doc.on.doc"
        case .save: return "square.and.arrow.down"
        case .message: return "message"
        case .edit: return "pencil"
        case .crop: return "crop"
        case .frame: return "rectangle.inset.filled"
        case .removeFrame: return "rectangle"
        case .retake: return "camera"
        case .newEasel: return "plus.rectangle"
        case .expand: return "chevron.down"
        case .easel: return "rectangle.on.rectangle"
        }
    }
    var group: Int {
        switch self {
        case .library, .copy, .save, .message: return 0
        case .edit, .crop, .frame, .removeFrame, .retake: return 1
        case .newEasel, .easel, .expand: return 2
        }
    }
    func title(librarySaved: Bool, framed: Bool) -> String {
        if self == .library && librarySaved { return "Saved to Library" }
        if self == .frame && framed { return "Edit Portrait Frame" }
        return title
    }
}

enum CaptureDestinationMenu {
    static let collapsedCount = 2

    static func actions(destinations: [CaptureEaselDestination], query: String,
                        expanded: Bool, framed: Bool, librarySaved: Bool,
                        persistentDestinations: Bool = true, easelDestinationsAvailable: Bool = true) -> [CaptureDestinationAction] {
        var actions: [CaptureDestinationAction] = persistentDestinations ? [.library] : []
        actions += [.copy, .save, .message, .edit, .crop, .frame]
        if framed { actions.append(.removeFrame) }
        actions.append(.retake)
        if persistentDestinations && easelDestinationsAvailable { actions.append(.newEasel) }
        let easels = persistentDestinations && easelDestinationsAvailable ? CaptureEaselDestination.ranked(destinations).map { CaptureDestinationAction.easel($0.id, $0.title) } : []
        if !query.isEmpty {
            // Search recurses through the complete expandable section and only
            // matches the current displayed toggle text, preserving row order.
            let query = query.lowercased()
            return (actions + easels).filter {
                $0.title(librarySaved: librarySaved, framed: framed).lowercased().contains(query)
            }
        }
        actions += expanded ? easels : Array(easels.prefix(collapsedCount))
        if !expanded && easels.count > collapsedCount { actions.append(.expand) }
        return actions
    }

    static func selectedIndex(actions: [CaptureDestinationAction], previousID: String?,
                              enabled: (CaptureDestinationAction) -> Bool) -> Int? {
        if let previousID, let index = actions.firstIndex(where: { $0.id == previousID }), enabled(actions[index]) { return index }
        return actions.firstIndex(where: enabled)
    }
}
