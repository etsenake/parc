import Testing
@testable import ParcCore

struct ShortcutTooltipDiscoverySkipTests {
    typealias Skip = ShortcutTooltipDiscoverySkip

    func fingerprint(copyTooltip: String = "Copy URL ⌘C", copyShortcut: String = "⌘C", capture: String = "⌘⇧C",
                     visible: String = "", full: String = "") -> String {
        Skip.fingerprint(copyURLTooltip: copyTooltip, copyURLShortcut: copyShortcut, captureShortcut: capture,
                         captureVisiblePageShortcut: visible, captureFullPageShortcut: full)
    }

    @Test func theFirstDiscoveryFingerprintNeverSkips() {
        #expect(!Skip.shouldSkip(previous: nil, next: "a"))
    }

    @Test func anIdenticalDiscoveryFingerprintIsATrueNoOpSkip() {
        #expect(Skip.shouldSkip(previous: "a", next: "a"))
    }

    @Test func aChangedDiscoveryFingerprintDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: "a", next: "b"))
    }

    @Test func stableDiscoveryInputsProduceAStableFingerprint() {
        #expect(fingerprint() == fingerprint())
    }

    @Test func unchangedCopyTooltipAndSiteControlShortcutsRemainANoOp() {
        #expect(Skip.shouldSkip(previous: fingerprint(), next: fingerprint()))
    }

    @Test func aCopyURLTooltipOrShortcutChangeStillUpdates() {
        let changed = fingerprint(copyTooltip: "Copy URL ⌃C", copyShortcut: "⌃C")
        #expect(!Skip.shouldSkip(previous: fingerprint(), next: changed))
    }

    @Test func aCaptureShortcutChangeStillUpdates() {
        #expect(!Skip.shouldSkip(previous: fingerprint(), next: fingerprint(capture: "⌃⇧C")))
    }

    @Test func aCaptureVisibleShortcutChangeStillUpdates() {
        #expect(!Skip.shouldSkip(previous: fingerprint(), next: fingerprint(visible: "⌃V")))
    }

    @Test func aCaptureFullPageShortcutChangeStillUpdates() {
        #expect(!Skip.shouldSkip(previous: fingerprint(), next: fingerprint(full: "⌃F")))
    }

    @Test func theFirstApplyInAWindowAfterOpenDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: nil, next: fingerprint()))
    }
}
