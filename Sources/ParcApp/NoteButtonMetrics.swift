import Foundation

enum NoteButtonMetrics {
    nonisolated static let verticalPadding: CGFloat = 4
    nonisolated static func pillHeight(scale: CGFloat) -> CGFloat { (32 * scale).rounded() }
    nonisolated static func height(scale: CGFloat) -> CGFloat { pillHeight(scale: scale) + verticalPadding * 2 }
}
