import Foundation

package struct SidebarOutlineConfigureFingerprint: Equatable {
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

    package init(contentIdentity: ObjectIdentifier? = nil, cellHeight: CGFloat, spanMinY: CGFloat? = nil, spanHeight: CGFloat? = nil, level: Int, isHidden: Bool, expanded: Bool? = nil, isItem: Bool, disclosesNothing: Bool, disclosedByKey: AnyHashable? = nil) {
        self.contentIdentity = contentIdentity
        self.cellHeight = cellHeight
        self.spanMinY = spanMinY
        self.spanHeight = spanHeight
        self.level = level
        self.isHidden = isHidden
        self.expanded = expanded
        self.isItem = isItem
        self.disclosesNothing = disclosesNothing
        self.disclosedByKey = disclosedByKey
    }
}

package enum SidebarOutlineConfigureSkip {
    package static func shouldSkip(
        previous: SidebarOutlineConfigureFingerprint?,
        next: SidebarOutlineConfigureFingerprint
    ) -> Bool {
        previous == next
    }
}
