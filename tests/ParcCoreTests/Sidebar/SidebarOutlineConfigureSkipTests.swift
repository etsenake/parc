import Foundation
import Testing
@testable import ParcCore

struct SidebarOutlineConfigureSkipTests {
    typealias Skip = SidebarOutlineConfigureSkip

    let objectA = NSObject()
    let objectB = NSObject()
    var contentA: ObjectIdentifier { ObjectIdentifier(objectA) }
    var contentB: ObjectIdentifier { ObjectIdentifier(objectB) }
    var base: SidebarOutlineConfigureFingerprint { fingerprint(contentIdentity: contentA) }

    func fingerprint(
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

    @Test func theFirstConfigureAlwaysRuns() {
        #expect(Skip.shouldSkip(previous: nil, next: base) == false)
    }

    @Test func anIdenticalFingerprintIsATrueNoOp() {
        #expect(Skip.shouldSkip(previous: base, next: base))
    }

    @Test func aContentIdentityChangeStillSetsContent() {
        #expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentB)) == false)
    }

    @Test func aCellHeightChangeStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, cellHeight: 28)) == false)
    }

    @Test func aSpanChangeStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base,
                                next: fingerprint(contentIdentity: contentA, spanMinY: 0, spanHeight: 40)) == false)
    }

    @Test func aLevelChangeStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, level: 2)) == false)
    }

    @Test func hidingARowStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, isHidden: true)) == false)
    }

    @Test func expandingARowStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, expanded: true)) == false)
    }

    @Test func changingWhetherARowIsAnItemStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base, next: fingerprint(contentIdentity: contentA, isItem: false)) == false)
    }

    @Test func changingWhetherARowDisclosesNothingStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base,
                                next: fingerprint(contentIdentity: contentA, disclosesNothing: true)) == false)
    }

    @Test func changingTheDisclosingFolderStillLaysOut() {
        #expect(Skip.shouldSkip(previous: base,
                                next: fingerprint(contentIdentity: contentA, disclosedByKey: "folder")) == false)
    }

    @Test func identicalEmptyCellFingerprintsStayANoOp() {
        #expect(Skip.shouldSkip(previous: fingerprint(contentIdentity: nil), next: fingerprint(contentIdentity: nil)))
    }
}
