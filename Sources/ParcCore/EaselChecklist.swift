import Foundation

enum EaselChecklist {
    enum Marker: Equatable {
        case open, done, divider
        var isItem: Bool { self != .divider }
    }

    static let openMarker = "\u{2610}"
    static let doneMarker = "\u{2611}"
    static let dividerMarker = "\u{2015}"

    static func marker(_ value: String) -> Marker? {
        switch value {
        case openMarker: return .open
        case doneMarker: return .done
        case dividerMarker: return .divider
        default: return nil
        }
    }

    static func value(_ marker: Marker) -> String {
        switch marker {
        case .open: return openMarker
        case .done: return doneMarker
        case .divider: return dividerMarker
        }
    }

    static func prefix(_ marker: Marker) -> String { "\t" + value(marker) + "\t" }

    static func boxSide(fontSize: Double) -> Double { min(18, max(10, (fontSize * 1.05).rounded())) }
}
