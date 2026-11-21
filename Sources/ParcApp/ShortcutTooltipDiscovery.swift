import ParcCore

final class ShortcutTooltipDiscovery {
    private var lastApplied: String?

    func apply(_ fingerprint: String, dismissToasts: () -> Void,
                        refreshCopyTooltip: () -> Void, refreshSiteControlShortcuts: () -> Void) {
        guard !ShortcutTooltipDiscoverySkip.shouldSkip(previous: lastApplied, next: fingerprint) else { return }
        dismissToasts()
        refreshCopyTooltip()
        refreshSiteControlShortcuts()
        lastApplied = fingerprint
    }
}
