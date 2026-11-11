enum FindReconcileSkip {
    static func shouldSkip(isPresented: Bool) -> Bool {
        !isPresented
    }
}
