import Foundation

@main
struct PeekPresentationSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func fingerprint(
        title: String = "Example",
        url: String = "https://example.test/",
        loading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        closePending: Bool = false,
        canExpand: Bool = true,
        canSplit: Bool = false,
        capture: String = PeekPresentationSkip.captureToken(
            active: false, camera: false, microphone: false, tab: false,
            window: false, display: false, mirrored: false, shared: false),
        crash: String = PeekPresentationSkip.crashToken(identity: nil, terminationStatus: 0, errorCode: 0),
        favicon: String = PeekPresentationSkip.faviconToken(nil)
    ) -> String {
        PeekPresentationSkip.fingerprint(
            title: title, url: url, loading: loading, canGoBack: canGoBack,
            canGoForward: canGoForward, closePending: closePending,
            canExpand: canExpand, canSplit: canSplit, capture: capture,
            crash: crash, favicon: favicon)
    }

    static func main() {
        typealias Skip = PeekPresentationSkip

        expect(Skip.shouldSkip(previous: nil, next: "a") == false, "First fingerprint never skips")
        expect(Skip.shouldSkip(previous: "a", next: "a"), "Identical fingerprint skips")
        expect(Skip.shouldSkip(previous: "a", next: "b") == false, "Changed fingerprint does not skip")

        expect(Skip.displayTitle(browserTitle: "Hello", urlHost: "example.test") == "Hello",
               "Non-empty browser title wins")
        expect(Skip.displayTitle(browserTitle: "", urlHost: "example.test") == "example.test",
               "Empty title falls back to host")
        expect(Skip.displayTitle(browserTitle: "", urlHost: nil) == "Peek",
               "Missing host falls back to Peek")

        let idle = fingerprint()
        expect(Skip.shouldSkip(previous: idle, next: fingerprint()),
               "Identical Peek presentation remains a true no-op")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(title: "Changed")) == false,
               "Title change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(url: "https://other.test/")) == false,
               "URL change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(loading: true)) == false,
               "Loading change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(canGoBack: true)) == false,
               "Back-history change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(canGoForward: true)) == false,
               "Forward-history change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(closePending: true)) == false,
               "Close-pending change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(canExpand: false)) == false,
               "Expand availability change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(canSplit: true)) == false,
               "Split availability change must not skip")

        let capturing = Skip.captureToken(
            active: true, camera: true, microphone: false, tab: false,
            window: false, display: false, mirrored: false, shared: false)
        let captureFlip = Skip.captureToken(
            active: true, camera: true, microphone: true, tab: false,
            window: false, display: false, mirrored: false, shared: false)
        expect(Skip.shouldSkip(previous: fingerprint(capture: capturing),
                               next: fingerprint(capture: capturing)),
               "Identical capture token skips")
        expect(Skip.shouldSkip(previous: fingerprint(capture: capturing),
                               next: fingerprint(capture: captureFlip)) == false,
               "Capture bit flip must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(capture: capturing)) == false,
               "Capture start must not skip")

        let crashOwners = (NSObject(), NSObject())
        let (crashA, crashB) = withExtendedLifetime(crashOwners) {
            (Skip.crashToken(identity: ObjectIdentifier(crashOwners.0), terminationStatus: 1, errorCode: 2),
             Skip.crashToken(identity: ObjectIdentifier(crashOwners.1), terminationStatus: 1, errorCode: 2))
        }
        expect(crashA != crashB, "Distinct crash identities alter the token")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(crash: crashA)) == false,
               "Renderer crash presentation must not skip")
        expect(Skip.shouldSkip(previous: fingerprint(crash: crashA), next: fingerprint(crash: crashA)),
               "Identical crash token skips")
        expect(Skip.shouldSkip(previous: fingerprint(crash: crashA), next: fingerprint(crash: crashB)) == false,
               "Crash identity change must not skip")

        let favA = Skip.faviconToken(Data([0x01, 0x02, 0x03]))
        let favB = Skip.faviconToken(Data([0x01, 0x02, 0x03]))
        let favC = Skip.faviconToken(Data([0x09, 0x08]))
        expect(favA == favB, "Stable favicon bytes match")
        expect(favA != favC, "Favicon byte change alters token")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(favicon: favA)) == false,
               "Favicon arrival must not skip")
        expect(Skip.shouldSkip(previous: fingerprint(favicon: favA), next: fingerprint(favicon: favB)),
               "Identical favicon remains a true no-op")
        expect(Skip.shouldSkip(previous: fingerprint(favicon: favA), next: fingerprint(favicon: favC)) == false,
               "Favicon change must not skip")

        fputs("PeekPresentationSkipTests: \(assertions) assertions\n", stderr)
    }
}
