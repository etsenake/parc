import Foundation
import Testing
@testable import ParcCore

struct PeekPresentationSkipTests {
    typealias Skip = PeekPresentationSkip

    func fingerprint(
        title: String = "Example",
        url: String = "https://example.test/",
        loading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        closePending: Bool = false,
        canExpand: Bool = true,
        canSplit: Bool = false,
        splitToolTip: String? = nil,
        capture: String = Skip.captureToken(
            active: false, camera: false, microphone: false, tab: false,
            window: false, display: false, mirrored: false, shared: false),
        crash: String = Skip.crashToken(identity: nil, terminationStatus: 0, errorCode: 0),
        favicon: String = Skip.faviconToken(nil)
    ) -> String {
        Skip.fingerprint(
            title: title, url: url, loading: loading, canGoBack: canGoBack,
            canGoForward: canGoForward, closePending: closePending,
            canExpand: canExpand, canSplit: canSplit, splitToolTip: splitToolTip, capture: capture,
            crash: crash, favicon: favicon)
    }

    func capture(microphone: Bool) -> String {
        Skip.captureToken(active: true, camera: true, microphone: microphone, tab: false,
                          window: false, display: false, mirrored: false, shared: false)
    }

    @Test func theFirstFingerprintNeverSkips() {
        #expect(Skip.shouldSkip(previous: nil, next: "a") == false)
    }

    @Test func anIdenticalFingerprintSkips() {
        #expect(Skip.shouldSkip(previous: "a", next: "a"))
    }

    @Test func aChangedFingerprintDoesNotSkip() {
        #expect(Skip.shouldSkip(previous: "a", next: "b") == false)
    }

    @Test func aNonEmptyBrowserTitleWins() {
        #expect(Skip.displayTitle(browserTitle: "Hello", urlHost: "example.test") == "Hello")
    }

    @Test func anEmptyTitleFallsBackToTheHost() {
        #expect(Skip.displayTitle(browserTitle: "", urlHost: "example.test") == "example.test")
    }

    @Test func aMissingHostFallsBackToPeek() {
        #expect(Skip.displayTitle(browserTitle: "", urlHost: nil) == "Peek")
    }

    @Test func anIdenticalPresentationRemainsATrueNoOp() {
        #expect(Skip.shouldSkip(previous: fingerprint(), next: fingerprint()))
    }

    @Test func titleURLLoadingAndHistoryChangesDoNotSkip() {
        let idle = fingerprint()
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(title: "Changed")) == false)
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(url: "https://other.test/")) == false)
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(loading: true)) == false)
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(canGoBack: true)) == false)
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(canGoForward: true)) == false)
    }

    @Test func closePendingExpandAndSplitChangesDoNotSkip() {
        let idle = fingerprint()
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(closePending: true)) == false)
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(canExpand: false)) == false)
        #expect(Skip.shouldSkip(previous: idle, next: fingerprint(canSplit: true)) == false)
    }

    @Test func aSplitReasonAppearingOrChangingDoesNotSkipAndAnUnchangedOneDoes() {
        let full = "Split View already shows four pages"
        #expect(Skip.shouldSkip(previous: fingerprint(), next: fingerprint(splitToolTip: full)) == false)
        #expect(Skip.shouldSkip(previous: fingerprint(splitToolTip: full),
                                next: fingerprint(splitToolTip: "Split View isn't available right now")) == false)
        #expect(Skip.shouldSkip(previous: fingerprint(splitToolTip: full), next: fingerprint(splitToolTip: full)))
    }

    @Test func anIdenticalCaptureTokenSkips() {
        let capturing = capture(microphone: false)
        #expect(Skip.shouldSkip(previous: fingerprint(capture: capturing), next: fingerprint(capture: capturing)))
    }

    @Test func aCaptureBitFlipDoesNotSkip() {
        #expect(Skip.shouldSkip(previous: fingerprint(capture: capture(microphone: false)),
                                next: fingerprint(capture: capture(microphone: true))) == false)
    }

    @Test func aCaptureStartDoesNotSkip() {
        #expect(Skip.shouldSkip(previous: fingerprint(), next: fingerprint(capture: capture(microphone: false))) == false)
    }

    @Test func distinctCrashIdentitiesAlterTheToken() {
        let owners = (NSObject(), NSObject())
        let (first, second) = withExtendedLifetime(owners) {
            (Skip.crashToken(identity: ObjectIdentifier(owners.0), terminationStatus: 1, errorCode: 2),
             Skip.crashToken(identity: ObjectIdentifier(owners.1), terminationStatus: 1, errorCode: 2))
        }
        #expect(first != second)
        #expect(Skip.shouldSkip(previous: fingerprint(), next: fingerprint(crash: first)) == false)
        #expect(Skip.shouldSkip(previous: fingerprint(crash: first), next: fingerprint(crash: first)))
        #expect(Skip.shouldSkip(previous: fingerprint(crash: first), next: fingerprint(crash: second)) == false)
    }

    @Test func stableFaviconBytesMatchAndChangedBytesAlterTheToken() {
        let first = Skip.faviconToken(Data([0x01, 0x02, 0x03]))
        let same = Skip.faviconToken(Data([0x01, 0x02, 0x03]))
        let different = Skip.faviconToken(Data([0x09, 0x08]))
        #expect(first == same)
        #expect(first != different)
    }

    @Test func aFaviconArrivalOrChangeDoesNotSkipButAnIdenticalOneDoes() {
        let first = Skip.faviconToken(Data([0x01, 0x02, 0x03]))
        let same = Skip.faviconToken(Data([0x01, 0x02, 0x03]))
        let different = Skip.faviconToken(Data([0x09, 0x08]))
        #expect(Skip.shouldSkip(previous: fingerprint(), next: fingerprint(favicon: first)) == false)
        #expect(Skip.shouldSkip(previous: fingerprint(favicon: first), next: fingerprint(favicon: same)))
        #expect(Skip.shouldSkip(previous: fingerprint(favicon: first), next: fingerprint(favicon: different)) == false)
    }
}
