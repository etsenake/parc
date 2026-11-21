import Foundation
import Testing
@testable import ParcCore

struct EaselCrashHardeningTests {
    @Test func ordinaryBoardsExportAtFullDensity() {
        #expect(EaselExportScale.capped(2, width: 1200, height: 900) == 2)
    }

    @Test func aGiantBoardKeepsEverySideWithinTheExportLimit() {
        let tall = EaselExportScale.capped(2, width: 1500, height: 2_000_000)
        #expect(tall > 0 && 2_000_000 * tall <= EaselExportScale.maximumSide + 0.5)
    }

    @Test func aHugeBoardStaysWithinThePixelBudgetAtAPositiveScale() {
        let wide = EaselExportScale.capped(2, width: 20_000, height: 20_000)
        #expect(20_000 * wide * 20_000 * wide <= EaselExportScale.maximumPixels * 1.000_001)
        #expect(wide > 0)
    }

    @Test(arguments: [(0.0, 900.0), (1200.0, 0.0)])
    func anEmptySideLeavesTheScaleForTheCallersOwnGuard(_ width: Double, _ height: Double) {
        #expect(EaselExportScale.capped(2, width: width, height: height) == 2)
    }

    @Test func invalidScalesPassThroughForTheCallersOwnGuard() {
        #expect(EaselExportScale.capped(.nan, width: 100, height: 100).isNaN)
    }

    @Test func pastedTableCellsDropLeadingAndTrailingBreaks() {
        #expect(EaselTableData.normalizedCellText("\u{2028}\u{2028} Hello   there \u{2028}") == "Hello there")
    }

    @Test func aCellOfOnlyBreaksPastesEmpty() {
        #expect(EaselTableData.normalizedCellText("\u{2028} \u{2028}").isEmpty)
    }

    @Test func aCellPaddedWithAFloodOfBreaksStillPastesItsWords() {
        let flood = String(repeating: "\u{2028}", count: 200_000) + "Kept" + String(repeating: "\u{2028}", count: 200_000)
        #expect(EaselTableData.normalizedCellText(flood) == "Kept")
    }
}
