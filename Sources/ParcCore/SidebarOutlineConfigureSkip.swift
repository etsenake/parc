import Foundation

/// Fingerprint of one `SidebarOutlineRow.configure` apply: content identity plus
/// the size/appearance inputs that force row layout. Membership rebuilds still
/// allocate new content; identical reconfigure of the same cell is a true no-op.
struct SidebarOutlineConfigureFingerprint: Equatable {
    var contentIdentity: ObjectIdentifier?
    var cellHeight: CGFloat
    var spanMinY: CGFloat?
    var spanHeight: CGFloat?
    var level: Int
    var isHidden: Bool
    var expanded: Bool?
    var isItem: Bool
    var disclosesNothing: Bool
    var disclosedByKey: AnyHashable?
}

/// Gate for `SidebarOutlineRow.configure` setContent / needsLayout. Skip only
/// when the configured content fingerprint already matches the last apply;
/// membership, appearance, and size deltas still configure and dirty layout.
enum SidebarOutlineConfigureSkip {
    /// True no-op: identical content identity and layout/appearance inputs.
    /// Nil previous never skips.
    static func shouldSkip(
        previous: SidebarOutlineConfigureFingerprint?,
        next: SidebarOutlineConfigureFingerprint
    ) -> Bool {
        previous == next
    }
}
