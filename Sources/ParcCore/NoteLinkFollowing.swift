import Foundation

enum NoteLinkClick: Equatable, CaseIterable {
    case plain
    case shift
    case modified
}

enum NoteLinkFollowRoute: Equatable {
    case peek
    case usual
}

extension NoteLinkClick {
    init(shift: Bool, command: Bool, option: Bool, control: Bool) {
        if command || option || control { self = .modified } else { self = shift ? .shift : .plain }
    }

    func route(for url: URL, automaticPeek: Bool, shiftPeek: Bool) -> NoteLinkFollowRoute {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return .usual }
        switch self {
        case .plain: return automaticPeek ? .peek : .usual
        case .shift: return shiftPeek ? .peek : .usual
        case .modified: return .usual
        }
    }
}
