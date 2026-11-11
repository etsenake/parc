enum SplitLayoutFlushSkip {
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }

    static func shouldApplyDividerMove(factorsChanged: Bool, alreadyMoved: Bool) -> Bool {
        factorsChanged || !alreadyMoved
    }
}
