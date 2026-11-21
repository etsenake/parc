import Testing
@testable import ParcCore

struct SoftwareUpdateDownloadCountTests {
    @Test func anUnknownSizeCannotReportAFraction() {
        let download = SoftwareUpdateDownloadProgress()
        #expect(download.display.fraction == nil)
    }

    @Test func receivingDataBeforeTheSizeNeitherShowsAFullBarNorInventsATotal() {
        var download = SoftwareUpdateDownloadProgress()
        download.receive(32_768)
        #expect(download.display.fraction == nil)
        #expect(!download.display.text.contains(" of "))
    }

    @Test func chunkLengthsAccumulateExactlyOnceAndTheReportedProgressIsEightyNinePercent() throws {
        var download = SoftwareUpdateDownloadProgress()
        download.receive(32_768)
        download.expect(227_500_000)
        download.receive(202_800_000 - 32_768)
        #expect(download.receivedLength == 202_800_000)
        let fraction = try #require(download.display.fraction)
        #expect(abs(fraction - 202.8 / 227.5) < 0.000001)
    }

    @Test func aRepeatedUnknownSizeCannotEraseTheKnownTotalOrJumpToComplete() throws {
        var download = SoftwareUpdateDownloadProgress()
        download.expect(227_500_000)
        download.receive(202_800_000)
        download.expect(0)
        #expect(download.expectedLength == 227_500_000)
        #expect(try #require(download.display.fraction) < 1)
    }

    @Test func repeatedSizeCallbacksDoNotResetReceivedBytes() {
        var download = SoftwareUpdateDownloadProgress()
        download.expect(227_500_000)
        download.receive(202_800_000)
        download.expect(227_500_000)
        #expect(download.receivedLength == 202_800_000)
    }

    @Test(arguments: [UInt64(227_500_000), 228_500_000])
    func receivingAtLeastTheExpectedBytesFillsTheBar(received: UInt64) {
        var download = SoftwareUpdateDownloadProgress()
        download.expect(227_500_000)
        download.receive(received)
        #expect(download.display.fraction == 1)
    }

    @Test func anAuthoritativeSizeCorrectionKeepsTheCountAndFractionConsistent() {
        var download = SoftwareUpdateDownloadProgress()
        download.expect(227_500_000)
        download.receive(228_500_000)
        download.expect(250_000_000)
        #expect(download.display.fraction == Double(download.receivedLength) / 250_000_000)
    }

    @Test func aNewTransferStartsFresh() {
        let download = SoftwareUpdateDownloadProgress()
        #expect(download.receivedLength == 0)
        #expect(download.display.fraction == nil)
    }

    @Test func invalidCountersCannotWrapBackToZeroOrTrap() {
        var download = SoftwareUpdateDownloadProgress()
        download.receive(.max)
        download.receive(1)
        #expect(download.receivedLength == .max)
    }
}
