enum CommandBarReconcileInputs {
    static func withPresentedBar<Bar>(
        _ commandBar: Bar?,
        build: (Bar) -> Void
    ) {
        guard let commandBar else { return }
        build(commandBar)
    }
}
