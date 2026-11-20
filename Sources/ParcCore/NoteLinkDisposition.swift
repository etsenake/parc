import Foundation

enum NoteLinkDisposition: Equatable, CaseIterable {
    case inPlace
    case foregroundTab
    case backgroundTab
    case newWindow
}

enum NoteLinkRoute: Equatable {
    case regularWindow
    case overPage
    case foregroundTab
    case backgroundTab
    case newWindow
}

extension NoteLinkDisposition {
    func routes(inRegularWindow: Bool) -> [NoteLinkRoute] {
        guard inRegularWindow else { return [.regularWindow] }
        switch self {
        case .inPlace: return [.overPage, .foregroundTab]
        case .foregroundTab: return [.foregroundTab]
        case .backgroundTab: return [.backgroundTab]
        case .newWindow: return [.newWindow]
        }
    }
}
