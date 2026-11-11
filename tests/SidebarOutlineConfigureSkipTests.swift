import Foundation

@main
struct SidebarOutlineConfigureSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func fingerprint(
        contentIdentity: ObjectIdentifier? = nil,
        cellHeight: CGFloat = 40,
        spanMinY: CGFloat? = 2,
        spanHeight: CGFloat? = 36,
        level: Int = 0,
        isHidden: Bool = false,
        expanded: Bool? = nil,
        isItem: Bool = true,
        disclosesNothing: Bool = false,
        disclosedByKey: AnyHashable? = nil
    ) -> SidebarOutlineConfigureFingerprint {
        SidebarOutlineConfigureFingerprint(
            contentIdentity: contentIdentity,
            cellHeight: cellHeight,
            spanMinY: spanMinY,
            spanHeight: spanHeight,
            level: level,
            isHidden: isHidden,
            expanded: expanded,
            isItem: isItem,
            disclosesNothing: disclosesNothing,
            disclosedByKey: disclosedByKey
        )
    }

    static func main() {
        typealias Skip = SidebarOutlineConfigureSkip
        let objectA = NSObject(), objectB = NSObject()
        let contentA = ObjectIdentifier(objectA), contentB = ObjectIdentifier(objectB)
        let base = fingerprint(contentIdentity: contentA)

        expect(Skip.shouldSkip(previous: nil, next: base) == false,
               "First configure apply must run setContent/needsLayout")
        expect(Skip.shouldSkip(previous: base, next: base),
               "Identical configured content fingerprint is a true no-op skip")
        expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentB)) == false,
               "Content identity change must still setContent/needsLayout")
        expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, cellHeight: 28)) == false,
               "Size (cellHeight) change must still layout")
        expect(Skip.shouldSkip(previous: base,
                               next: fingerprint(contentIdentity: contentA, spanMinY: 0, spanHeight: 40)) == false,
               "Size (span) change must still layout")
        expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, level: 2)) == false,
               "Level/indent change must still layout")
        expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, isHidden: true)) == false,
               "Appearance (isHidden) change must still layout")
        expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, expanded: true)) == false,
               "Appearance (expanded) change must still layout")
        expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, isItem: false)) == false,
               "Appearance (isItem) change must still layout")
        expect(Skip.shouldSkip(previous: base,
                               next: fingerprint(contentIdentity: contentA, disclosesNothing: true)) == false,
               "Appearance (disclosesNothing) change must still layout")
        expect(Skip.shouldSkip(previous: base,
                               next: fingerprint(contentIdentity: contentA, disclosedByKey: "folder")) == false,
               "Membership (disclosedByKey) change must still layout")
        expect(Skip.shouldSkip(previous: fingerprint(contentIdentity: nil),
                               next: fingerprint(contentIdentity: nil)),
               "Identical empty-cell fingerprints remain a true no-op")

        print("\(assertions) sidebar outline configure skip assertions passed")
    }
}
