import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsHeaderGeometryTests {
    private func geometry() -> NotePageHeaderGeometry {
        let column = CGRect(x: 140, y: 0, width: 720, height: 0)
        var base = NotePageHeaderGeometry(width: 1000, column: column, titleHeight: 55)
        base.titleCapInset = 12
        base.iconInkInset = 11
        base.affordanceHeight = 26
        return base
    }

    private func coveredGeometry() -> NotePageHeaderGeometry {
        var both = geometry()
        both.coverHeight = 228
        both.hasIcon = true
        return both
    }

    @Test func theCoverFillsTheWidthAndTheIconOverlapsIt() throws {
        let both = coveredGeometry()
        let column = CGRect(x: 140, y: 0, width: 720, height: 0)
        let full = both.layout()
        #expect(full.cover == CGRect(x: 0, y: 0, width: 1000, height: 228), "the cover runs edge to edge")
        let icon = try #require(full.icon, "an icon is laid out")
        #expect(icon.minY == 228 - icon.height / 2 && icon.height == NotePageHeaderGeometry.iconSide, "the icon overlaps the cover by half")
        #expect(icon.minX == column.minX - NotePageHeaderGeometry.iconLead, "the icon sits on the text column")
        let inkGap = (full.title.minY + 12) - (icon.maxY - 11)
        #expect(inkGap >= 12 && inkGap <= 16, "the title's caps sit 12 to 16 pt under the icon's ink (got \(inkGap))")
        #expect(full.title.minY - icon.maxY < 8, "the title hugs the icon box (gap \(full.title.minY - icon.maxY))")
        #expect(full.affordances.minX >= icon.maxX && full.affordances.minY >= 228 && full.affordances.maxY <= icon.maxY, "the hover row sits beside the icon's foot, below the cover")
        #expect(full.height == (full.title.maxY + NotePageHeaderGeometry.bottomPadding).rounded(.up), "the header ends just under the title")
    }

    @Test func anIconWithoutACoverStartsAtTopPadding() throws {
        let base = geometry()
        let full = coveredGeometry().layout()
        let icon = try #require(full.icon, "an icon is laid out")
        var iconOnly = base
        iconOnly.hasIcon = true
        let plainIcon = iconOnly.layout()
        #expect(plainIcon.cover == nil && plainIcon.icon?.minY == NotePageHeaderGeometry.topPadding, "without a cover the icon starts at the top padding")
        #expect(plainIcon.title.minY - (plainIcon.icon?.maxY ?? 0) == full.title.minY - icon.maxY, "the icon to title rhythm holds without a cover")
    }

    @Test func aCoverWithoutAnIconKeepsTheTitleAndHoverRowClose() {
        let base = geometry()
        var coverOnly = base
        coverOnly.coverHeight = 228
        let banner = coverOnly.layout()
        #expect(banner.icon == nil && banner.affordances.minY > 228 && banner.affordances.maxY < banner.title.minY + 12, "with only a cover, the hover row rests between the cover and the title's caps")
        #expect(banner.title.minY - 228 < 60, "the title stays close under a bare cover (gap \(banner.title.minY - 228))")
    }

    @Test func anUndecoratedHeaderStartsItsHoverRowAtTopPadding() {
        let base = geometry()
        let neither = base.layout()
        #expect(neither.icon == nil && neither.cover == nil && neither.affordances.minY == NotePageHeaderGeometry.topPadding, "a bare page keeps its hover row in the top padding")
        #expect(neither.title.minY + 12 - neither.affordances.maxY == NotePageHeaderGeometry.inkGap, "the bare title sits one ink gap under the row")
    }

    @Test func anErrorFitsUnderTheTitleWithoutMovingIt() {
        let column = CGRect(x: 140, y: 0, width: 720, height: 0)
        let both = coveredGeometry()
        let full = both.layout()
        var withError = both
        withError.errorHeight = 20
        let erring = withError.layout()
        #expect(erring.title == full.title, "an error never moves the title")
        #expect(erring.error == CGRect(x: column.minX, y: full.title.maxY + NotePageHeaderGeometry.errorGap, width: 720, height: 20), "the error sits right under the title")
        #expect(erring.height == full.height + 20 + NotePageHeaderGeometry.errorGap, "the error makes room for itself")
    }

    @Test func headerPropertiesFollowTheErrorAndHangIntoTheGutter() {
        let column = CGRect(x: 140, y: 0, width: 720, height: 0)
        let both = coveredGeometry()
        var withError = both
        withError.errorHeight = 20
        let erring = withError.layout()
        var withProperties = withError
        withProperties.propertiesHeight = 120
        withProperties.propertiesGutter = 24
        let listed = withProperties.layout()
        #expect(listed.properties == CGRect(x: column.minX - 24, y: erring.error!.maxY + NotePageHeaderGeometry.propertiesGap, width: 744, height: 120), "properties follow the error, hanging into the gutter")
    }

    @Test func aPlainTextHeaderSkipsTheCoverAndIcon() {
        let base = geometry()
        var plain = base
        plain.isPlainText = true
        plain.coverHeight = 228
        plain.hasIcon = true
        let text = plain.layout()
        #expect(text.cover == nil && text.icon == nil && text.title.minY == NotePageHeaderGeometry.plainTextTop, "plain text pages skip the cover and icon")
    }

    @Test func aHeaderWithoutAColumnUsesTheFullWidth() {
        let base = geometry()
        var narrow = base
        narrow.column = .zero
        #expect(narrow.layout().title.width == 1000, "a missing column falls back to the full width")
    }
}
