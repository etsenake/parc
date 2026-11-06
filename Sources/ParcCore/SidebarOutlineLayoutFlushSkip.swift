/// Gate for forced outline/list `layoutSubtreeIfNeeded` during sidebar layout.
///
/// `SidebarView.layout` previously always walked the outline after assigning its
/// frame, even when membership/geometry already matched and the subtree was
/// clean (amplifying row layout after the `797f2a55` paint skip). Skip only
/// when no frame moved and the tree is already clean; keep the flush when
/// membership rebuilds, size/disclosure changes, or a child still needs layout.
enum SidebarOutlineLayoutFlushSkip {
    /// True no-op: identical outline geometry with a clean subtree skips
    /// layoutSubtree. A moved frame, a dirty list, or a dirty child still flushes.
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }
}
