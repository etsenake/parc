/// Gate for render-time Find reconcile.
///
/// `BrowserWindowController.render` always defers into `reconcileFind`, which
/// filters `findStates`, may dismiss, then updates the host and lays out the
/// bar when visible. Closed Find with nothing to dismiss is a true no-op of
/// that path; keep the full reconcile when a bar is presented.
enum FindReconcileSkip {
    /// Skip only when Find is not presented. An open bar must still filter,
    /// dismiss when stale/library, update match UI, and layout. Find-result
    /// notifications reach reconcile only while a bar owns the page.
    static func shouldSkip(isPresented: Bool) -> Bool {
        !isPresented
    }
}
