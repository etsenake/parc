/// True no-op skip for LiveShortcutToolTip.didChange fan-out: identical
/// discovered copy-tooltip / site-control shortcut fingerprints skip; a first
/// apply or any string change must still update every window that needs them.
@main
struct ShortcutTooltipDiscoverySkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() {
        typealias Skip = ShortcutTooltipDiscoverySkip

        expect(Skip.shouldSkip(previous: nil, next: "a") == false,
               "First discovery fingerprint never skips")
        expect(Skip.shouldSkip(previous: "a", next: "a"),
               "Identical discovery fingerprint is a true no-op skip")
        expect(Skip.shouldSkip(previous: "a", next: "b") == false,
               "Changed discovery fingerprint must not skip")

        let idle = Skip.fingerprint(
            copyURLTooltip: "Copy URL ⌘C",
            copyURLShortcut: "⌘C",
            captureShortcut: "⌘⇧C",
            captureVisiblePageShortcut: "",
            captureFullPageShortcut: ""
        )
        let same = Skip.fingerprint(
            copyURLTooltip: "Copy URL ⌘C",
            copyURLShortcut: "⌘C",
            captureShortcut: "⌘⇧C",
            captureVisiblePageShortcut: "",
            captureFullPageShortcut: ""
        )
        let copyChanged = Skip.fingerprint(
            copyURLTooltip: "Copy URL ⌃C",
            copyURLShortcut: "⌃C",
            captureShortcut: "⌘⇧C",
            captureVisiblePageShortcut: "",
            captureFullPageShortcut: ""
        )
        let captureChanged = Skip.fingerprint(
            copyURLTooltip: "Copy URL ⌘C",
            copyURLShortcut: "⌘C",
            captureShortcut: "⌃⇧C",
            captureVisiblePageShortcut: "",
            captureFullPageShortcut: ""
        )
        let visibleChanged = Skip.fingerprint(
            copyURLTooltip: "Copy URL ⌘C",
            copyURLShortcut: "⌘C",
            captureShortcut: "⌘⇧C",
            captureVisiblePageShortcut: "⌃V",
            captureFullPageShortcut: ""
        )
        let fullChanged = Skip.fingerprint(
            copyURLTooltip: "Copy URL ⌘C",
            copyURLShortcut: "⌘C",
            captureShortcut: "⌘⇧C",
            captureVisiblePageShortcut: "",
            captureFullPageShortcut: "⌃F"
        )

        expect(idle == same, "Stable discovery inputs produce a stable fingerprint")
        expect(Skip.shouldSkip(previous: idle, next: same),
               "Unchanged copy tooltip and site-control shortcuts remain a true no-op")
        expect(Skip.shouldSkip(previous: idle, next: copyChanged) == false,
               "Copy-URL tooltip/shortcut change must still update")
        expect(Skip.shouldSkip(previous: idle, next: captureChanged) == false,
               "Capture shortcut change must still update")
        expect(Skip.shouldSkip(previous: idle, next: visibleChanged) == false,
               "Capture-visible shortcut change must still update")
        expect(Skip.shouldSkip(previous: idle, next: fullChanged) == false,
               "Capture-full-page shortcut change must still update")
        expect(Skip.shouldSkip(previous: nil, next: idle) == false,
               "Per-window first apply after open must not skip")

        print("\(assertions) shortcut tooltip discovery skip assertions passed")
    }
}
