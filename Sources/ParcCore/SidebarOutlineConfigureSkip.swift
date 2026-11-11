import Foundation

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

enum SidebarOutlineConfigureSkip {
    static func shouldSkip(
        previous: SidebarOutlineConfigureFingerprint?,
        next: SidebarOutlineConfigureFingerprint
    ) -> Bool {
        previous == next
    }
}
