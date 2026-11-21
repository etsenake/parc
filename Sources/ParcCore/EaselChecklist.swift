import Foundation

package enum EaselChecklist {
    package enum Marker: Equatable {
        case open, done, divider
        package var isItem: Bool { self != .divider }
    }

    package static let openMarker = "\u{2610}"
    package static let doneMarker = "\u{2611}"
    package static let dividerMarker = "\u{2015}"

    package static func marker(_ value: String) -> Marker? {
        switch value {
        case openMarker: return .open
        case doneMarker: return .done
        case dividerMarker: return .divider
        default: return nil
        }
    }

    package static func value(_ marker: Marker) -> String {
        switch marker {
        case .open: return openMarker
        case .done: return doneMarker
        case .divider: return dividerMarker
        }
    }

    package static func prefix(_ marker: Marker) -> String { "\t" + value(marker) + "\t" }

    package static func boxSide(fontSize: Double) -> Double { min(18, max(10, (fontSize * 1.05).rounded())) }
}
