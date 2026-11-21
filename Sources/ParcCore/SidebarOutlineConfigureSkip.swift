import Foundation

package struct SidebarOutlineConfigureFingerprint: Equatable {
    package var contentIdentity: ObjectIdentifier?
    package var cellHeight: CGFloat
    package var spanMinY: CGFloat?
    package var spanHeight: CGFloat?
    package var level: Int
    package var isHidden: Bool
    package var expanded: Bool?
    package var isItem: Bool
    package var disclosesNothing: Bool
    package var disclosedByKey: AnyHashable?

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
