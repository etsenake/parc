/// Gate for render-time command-bar reconcile input snapshots.
///
/// `commandBar?.reconcile(tabs:history:spaces:folders:)` still evaluates every
/// argument when the optional is nil. Closing that evaluation hole keeps idle
/// browsing ticks from walking tabs, history, spaces, and folders.
enum CommandBarReconcileInputs {
    /// Runs `build` only while a command bar is presented. Snapshot work must
    /// stay inside `build` so a closed bar performs no array construction.
    static func withPresentedBar<Bar>(
        _ commandBar: Bar?,
        build: (Bar) -> Void
    ) {
        guard let commandBar else { return }
        build(commandBar)
    }
}
