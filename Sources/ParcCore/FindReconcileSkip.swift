package enum FindReconcileSkip {
    package static func shouldSkip(isPresented: Bool) -> Bool {
        !isPresented
    }
}
