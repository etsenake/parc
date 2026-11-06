import AppKit

///
/// evidence basis is in docs/sidebar-accessibility.md. The item list's outline
/// is SidebarOutline.swift; the items' own semantics stay with their owners.
@MainActor
enum SidebarAccessibility {
    //
    //
    static let hideSidebar = "Hide sidebar", lockSidebar = "Lock sidebar"
    static let goBack = "Go back", goForward = "Go forward", reload = "Reload this page"

    ///
    ///
    ///
    ///
    ///
    /// non-optional String, so an empty name takes it instead.
    /// Keyboard: SidebarDockItemView is a cell-less NSControl with no focus-ring
    /// or responder override (method list, disassembly), so AppKit draws no
    /// ring for it. Parc's NSButton therefore takes no keyboard focus rather
    /// than leave an unmarked stop; Next/Previous Space and VoiceOver's press
    /// still reach every Space.
    static func configureSpace(_ button: NSButton, name: String) {
        let title = name.isEmpty ? "Untitled Space" : name
        let identifier = "SidebarDockItem-" + title
        button.refusesFirstResponder = true; button.focusRingType = .none
        button.setAccessibilityRoleDescription("Space")
        button.setAccessibilityTitle(title); button.setAccessibilityIdentifier(identifier)
        // AppKit ignores the NSButton and exposes its cell to VoiceOver.
        button.cell?.setAccessibilityRoleDescription("Space")
        button.cell?.setAccessibilityTitle(title); button.cell?.setAccessibilityIdentifier(identifier)
    }

    /// The exposed NSButtonCell describes itself from its image, so a label set
    /// only on the button never reaches VoiceOver.
    static func label(_ button: NSButton, _ text: String) {
        button.setAccessibilityLabel(text)
        button.cell?.setAccessibilityLabel(text)
        button.image?.accessibilityDescription = text
    }

    /// The visible members of one row of `views`, leading first by frame.
    static func laidOut(_ views: [NSView]) -> [NSView] {
        views.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Moves the elements that belong to a `header` view (the view itself, a
    /// descendant, or a cell AppKit exposes for one) ahead of the rest, in
    /// `header` order; everything else keeps AppKit's subview order.
    static func headerFirst(_ children: [Any], header: [NSView]) -> [Any] {
        let ranked = children.enumerated().map { index, element -> (rank: Int?, index: Int, element: Any) in
            let view = (element as? NSView) ?? (element as? NSCell)?.controlView
            return (view.flatMap { view in header.firstIndex { view.isDescendant(of: $0) } }, index, element)
        }
        let leading = ranked.compactMap { item in item.rank.map { ($0, item.index, item.element) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
        return leading + ranked.filter { $0.rank == nil }.map(\.element)
    }

    /// The sidebar's Tab chain: `leading` (header and address controls), the
    /// Favorites' and `beforeList` header controls, `list` (the list's own
    /// keyboard stop, an adaptation:
    ///
    /// (the dock). Regions lay out first, so children they place in their own
    /// layout sort by their real frames.
    static func keyViewChain(leading: [NSView], favorites: NSView, list: NSView, regions: [NSView],
                             trailing: [NSView], space: NSView, beforeList: [NSView] = []) -> [NSView] {
        ([favorites] + beforeList + regions).forEach { $0.layoutSubtreeIfNeeded() }
        return leading + keyViews(in: [favorites] + beforeList, space: space) + [list] + keyViews(in: regions, space: space) + trailing
    }

    /// Descendants of `roots` that take keyboard focus, depth first, each level
    /// top to bottom (4-point rows) and then leading first in the flipped
    /// `space`: AppKit's geometric key-view order, scoped to one region. An
    /// editing field's field editor stays with its field. The window owner's
    /// page side leaves out `excluded` subtrees and the views that `forwards`
    /// (WindowKeyViewLoop).
    static func keyViews(in roots: [NSView], space: NSView, excluded: (NSView) -> Bool = { _ in false },
                         forwards: (NSView) -> Bool = { _ in false }) -> [NSView] {
        var views: [NSView] = []
        func visit(_ view: NSView) {
            if (view as? NSTextView)?.isFieldEditor == true || excluded(view) { return }
            if takesFocus(view), !forwards(view) { views.append(view) }
            let keyed = view.subviews.enumerated().map { index, child in
                let frame = child.convert(child.bounds, to: space)
                return (row: (frame.minY / 4).rounded(.down), x: frame.minX, index: index, child: child)
            }
            for entry in keyed.sorted(by: { ($0.row, $0.x, $0.index) < ($1.row, $1.x, $1.index) }) { visit(entry.child) }
        }
        roots.forEach(visit)
        return views
    }

    /// A disabled control answers acceptsFirstResponder false only until it is
    /// enabled, so it keeps its place unless it refuses focus or is a label.
    static func takesFocus(_ view: NSView) -> Bool {
        if view.acceptsFirstResponder { return true }
        guard let control = view as? NSControl, !control.isEnabled, !control.refusesFirstResponder else { return false }
        return (control as? NSTextField).map { $0.isEditable || $0.isSelectable } ?? true
    }

    /// Links `chain` in order and continues from its last element to `exit`.
    /// Without one it keeps the first link out of `owner` that the chain already
    /// holds and that stays in `owner`'s window (the window loop's way on), else
    /// one another view inside `owner` holds: AppKit's computed loop leaves from
    /// `owner`'s last descendant, on this OS a control's own hosting subview. A
    /// removed former member is never an exit. AppKit's computed loop enters a
    /// container before its children, so its link into `owner` itself moves to
    /// the chain's start; otherwise it would enter at `owner`'s own stop and skip
    /// the elements before it. A link from outside into any other member (a
    /// former first, such as the toggle before a narrow row moved it after Back
    /// and Forward) moves to the start too. Views that cannot become key now (hidden,
    /// disabled, no Full Keyboard Access) stay linked and are skipped by
    /// `nextValidKeyView`. A `bypassed` chain (a hidden sidebar, unhidden
    /// off-screen) leads from its first view, which must never become key (the
    /// sidebar's gate), straight to the way out, so Tab and Shift-Tab pass it;
    /// linking it again unbypassed restores the chain behind that way in. A
    /// moved link never takes the start's way back from an outside link already
    /// there (the window owner's, from the page side's end).
    static func link(_ chain: [NSView], within owner: NSView, exit: NSView?, bypassed: Bool = false) {
        guard let first = chain.first, let last = chain.last else { return }
        func outside(_ view: NSView) -> Bool { view.window != nil && view.window === owner.window && !view.isDescendant(of: owner) }
        let wayBack = first.previousKeyView.flatMap { $0.nextKeyView === first && outside($0) ? $0 : nil }
        for member in [owner] + chain where member !== first {
            if let entering = member.previousKeyView, entering.nextKeyView === member, outside(entering) { entering.nextKeyView = first }
        }
        if let wayBack { link(wayBack, to: first) }
        func descendants(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants(of: $0) } }
        let next = exit ?? ([last] + chain).lazy.compactMap(\.nextKeyView).first(where: outside)
            ?? descendants(of: owner).lazy.compactMap(\.nextKeyView).first(where: outside)
        if bypassed { link(first, to: next); return }
        for (view, following) in zip(chain, chain.dropFirst()) { link(view, to: following) }
        link(last, to: next)
    }

    /// A link is set again when its target's way back is another view's: a key
    /// view's back pointer keeps only the last view linked to it [C].
    static func link(_ view: NSView, to following: NSView?) {
        if view.nextKeyView !== following || following.map({ $0.previousKeyView !== view }) == true { view.nextKeyView = following }
    }
}
