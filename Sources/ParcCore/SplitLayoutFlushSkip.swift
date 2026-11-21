package enum SplitLayoutFlushSkip {
    package static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }

    package static func shouldApplyDividerMove(factorsChanged: Bool, alreadyMoved: Bool) -> Bool {
        factorsChanged || !alreadyMoved
    }
}
