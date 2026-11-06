/// Gates for forced split layout work during drop reserve / apply and
/// divider drag. Skip only true no-ops of the current contract.
enum SplitLayoutFlushSkip {
    /// True no-op: identical geometry with a clean subtree skips layoutSubtree.
    /// A moved frame, a dirty view, or a dirty child still flushes.
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }

    /// First pan update materializes the resize factors (they may differ from
    /// savedFactors when resizing from displayed lengths). Later moves with
    /// unchanged factors are a true no-op of geometry; snap haptics stay
    /// outside this gate.
    static func shouldApplyDividerMove(factorsChanged: Bool, alreadyMoved: Bool) -> Bool {
        factorsChanged || !alreadyMoved
    }
}
