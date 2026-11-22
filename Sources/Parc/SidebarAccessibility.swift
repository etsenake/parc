import AppKit

@MainActor
enum SidebarAccessibility {
    static let hideSidebar = "Hide sidebar", lockSidebar = "Lock sidebar"
    static let goBack = "Go back", goForward = "Go forward", reload = "Reload this page"

    static func configureSpace(_ button: NSButton, name: String) {
        let title = name.isEmpty ? "Untitled Space" : name
        let identifier = "SidebarDockItem-" + title
        button.refusesFirstResponder = true; button.focusRingType = .none
        button.setAccessibilityRoleDescription("Space")
        button.setAccessibilityTitle(title); button.setAccessibilityIdentifier(identifier)
        button.cell?.setAccessibilityRoleDescription("Space")
        button.cell?.setAccessibilityTitle(title); button.cell?.setAccessibilityIdentifier(identifier)
    }

    static func label(_ button: NSButton, _ text: String) {
        button.setAccessibilityLabel(text)
        button.cell?.setAccessibilityLabel(text)
        guard let image = button.image, image.size.width > 1 || image.size.height > 1,
              image.accessibilityDescription != text, let own = image.copy() as? NSImage else { return }
        own.accessibilityDescription = text
        button.image = own
    }

    static func laidOut(_ views: [NSView]) -> [NSView] {
        views.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func headerFirst(_ children: [Any], header: [NSView]) -> [Any] {
        let ranked = children.enumerated().map { index, element -> (rank: Int?, index: Int, element: Any) in
            let view = (element as? NSView) ?? (element as? NSCell)?.controlView
            return (view.flatMap { view in header.firstIndex { view.isDescendant(of: $0) } }, index, element)
        }
        let leading = ranked.compactMap { item in item.rank.map { ($0, item.index, item.element) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
        return leading + ranked.filter { $0.rank == nil }.map(\.element)
    }

    static func keyViewChain(leading: [NSView], favorites: NSView, list: NSView, regions: [NSView],
                             trailing: [NSView], space: NSView, beforeList: [NSView] = [],
                             laidOut: (NSView) -> Bool = { _ in false }) -> [NSView] {
        for region in [favorites] + beforeList + regions where !laidOut(region) { region.layoutSubtreeIfNeeded() }
        return leading + keyViews(in: [favorites] + beforeList, space: space) + [list] + keyViews(in: regions, space: space) + trailing
    }

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

    static func takesFocus(_ view: NSView) -> Bool {
        if view.acceptsFirstResponder { return true }
        guard let control = view as? NSControl, !control.isEnabled, !control.refusesFirstResponder else { return false }
        return (control as? NSTextField).map { $0.isEditable || $0.isSelectable } ?? true
    }

    static func link(_ chain: [NSView], within owner: NSView, exit: NSView?, bypassed: Bool = false,
                     skipping skipped: (NSView) -> Bool = { _ in false }) {
        guard let first = chain.first, let last = chain.last else { return }
        func outside(_ view: NSView) -> Bool { view.window != nil && view.window === owner.window && !view.isDescendant(of: owner) }
        let wayBack = first.previousKeyView.flatMap { $0.nextKeyView === first && outside($0) ? $0 : nil }
        for member in [owner] + chain where member !== first {
            if let entering = member.previousKeyView, entering.nextKeyView === member, outside(entering) { entering.nextKeyView = first }
        }
        if let wayBack { link(wayBack, to: first) }
        func linkOut(below view: NSView) -> NSView? {
            for child in view.subviews where !skipped(child) {
                if let next = child.nextKeyView, outside(next) { return next }
                if let next = linkOut(below: child) { return next }
            }
            return nil
        }
        let next = exit ?? ([last] + chain).lazy.compactMap(\.nextKeyView).first(where: outside) ?? linkOut(below: owner)
        if bypassed { link(first, to: next); return }
        for (view, following) in zip(chain, chain.dropFirst()) { link(view, to: following) }
        link(last, to: next)
    }

    static func link(_ view: NSView, to following: NSView?) {
        if view.nextKeyView !== following || following.map({ $0.previousKeyView !== view }) == true { view.nextKeyView = following }
    }
}
