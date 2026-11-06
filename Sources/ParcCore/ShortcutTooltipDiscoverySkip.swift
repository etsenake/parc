/// Gate for process-wide `LiveShortcutToolTip.didChange` fan-out into each
/// `BrowserWindowController`.
///
/// Discovery posts once; every open window previously dismissed copy feedback
/// and reapplied the popup copy tooltip plus site-control shortcut strings
/// even when that window's presented strings were unchanged. Skip only when
/// the discovered content already matches what the window last applied; a
/// first apply or any string change still updates.
enum ShortcutTooltipDiscoverySkip {
    /// True no-op: identical discovered copy-tooltip and site-control shortcut
    /// fingerprint. Nil previous never skips; any content change applies.
    static func shouldSkip(previous: String?, next: String) -> Bool {
        previous == next
    }

    /// Fingerprint of the copy-URL tooltip text plus the site-control shortcut
    /// displays the sink would write for this discovery.
    static func fingerprint(
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
