import ParcCore

package final class ShortcutTooltipDiscovery {
    package init() {}
    private var lastApplied: String?

    package func apply(_ fingerprint: String, dismissToasts: () -> Void,
                        refreshCopyTooltip: () -> Void, refreshSiteControlShortcuts: () -> Void) {
        guard !ShortcutTooltipDiscoverySkip.shouldSkip(previous: lastApplied, next: fingerprint) else { return }
        dismissToasts()
        refreshCopyTooltip()
        refreshSiteControlShortcuts()
        lastApplied = fingerprint
    }
}
