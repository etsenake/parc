package enum ShortcutTooltipDiscoverySkip {
    package static func shouldSkip(previous: String?, next: String) -> Bool {
        previous == next
    }

    package static func fingerprint(
        copyURLTooltip: String,
        copyURLShortcut: String,
        captureShortcut: String,
        captureVisiblePageShortcut: String,
        captureFullPageShortcut: String
    ) -> String {
        [
            copyURLTooltip,
            copyURLShortcut,
            captureShortcut,
            captureVisiblePageShortcut,
            captureFullPageShortcut,
        ].joined(separator: "\u{1f}")
    }
}
