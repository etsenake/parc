enum SidebarOutlineLayoutFlushSkip {
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }
}
