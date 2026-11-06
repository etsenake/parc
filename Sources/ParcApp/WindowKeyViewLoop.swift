import AppKit

/// The sidebar's ends in the window loop: `keyViewEntry`, a gate that never
/// takes focus, and `keyViewExit`, the first key view after it; and a relink of
/// its own chain (SidebarView).
@MainActor
protocol SidebarKeyViewEnds: AnyObject {
    var keyViewEntry: NSView { get }
    var keyViewExit: NSView? { get set }
    func setNeedsKeyViewLinking()
}

///
/// main executable (1.122 and 1.170) sends no `setNextKeyView:` or
/// `recalculateKeyViewLoop` (neither selector is in its tables) [D], so AppKit
/// computes its browser window's loop when the window is first shown and a view
///
/// page view to the view it adds, its one `recalculateKeyViewLoop` is a page
/// dialog's [D]. Both engines ask the page view's window for the next key view
/// when Tab leaves a page (Parc's `rotateFocusForward`), so without links Tab
/// past a later page's last element stays in the page [C]. Parc links the page
///
/// docs/sidebar-accessibility.md): every key view outside the sidebar in
/// AppKit's geometric order, the last to the sidebar's gate, and the first is
/// the sidebar's way out. Showing a window the first time replaces links set
/// before with AppKit's computed loop [C], so both sides link again once the
/// window becomes key. It never recalculates the window's loop: a view holding
/// a closed loop of its own (page capture's overlay, its portrait card) keeps
/// it, with its subtree. Inside a page (`isPage`) a view that takes focus but
/// holds another that does is the engine's page host, which forwards focus to
/// its renderer later (page_host.mm), so the renderer is the stop: Tab leaves
/// the page from it, and entering it directly keeps the selection direction
/// Chromium uses to focus the first or last element. A view that
/// `passesThrough` takes first responder only for its own keys (the Peek's
/// host, for Escape) and is no stop; its subviews are.
@MainActor
final class WindowKeyViewLoop {
    private weak var root: NSView?
    private weak var sidebar: (any SidebarKeyViewEnds)?
    private let excluded: (NSView) -> Bool
    private let isPage: (NSView) -> Bool
    private let passesThrough: (NSView) -> Bool
    private let linked = NSHashTable<NSView>.weakObjects()
    private var observation: NSKeyValueObservation?
    private var keyObserver: NSObjectProtocol?

    /// `root` is the window's content view; `excluded` subtrees (`windowExcludes`)
    /// are not on the page side.
    init(root: NSView, sidebar: any SidebarKeyViewEnds, excluded: @escaping (NSView) -> Bool,
         isPage: @escaping (NSView) -> Bool, passesThrough: @escaping (NSView) -> Bool = { _ in false }) {
        self.root = root; self.sidebar = sidebar; self.excluded = excluded; self.isPage = isPage
        self.passesThrough = passesThrough
    }

    /// The browser window's exclusions: the sidebar's container and the parked
    /// panes; a sidebar preview card, live or animating out after its dismissal
    /// (the card is a root subview: a keyboard-owned one keeps Tab among its own
    /// controls, and a leaving one would take a Tab and drop it to the window
    /// when it is removed); and while a Peek is up, the page host's other
    /// subviews, the panes it dims and any other Peek.
    static func windowExcludes(_ view: NSView, sidebarContainer: NSView, parkedPages: NSView, pageHost: NSView,
                               activePeek: () -> NSView?) -> Bool {
        if view === sidebarContainer || view === parkedPages || view is SidebarPreviewSurface { return true }
        guard view.superview === pageHost, let peek = activePeek() else { return false }
        return view !== peek
    }

    deinit { if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) } }

    /// Relinks when focus reaches a page-side view the last link did not
    /// include, such as a renderer the engine swapped in without a shell
    /// layout (field editors stay with their field), and, with the sidebar's
    /// chain, when the window becomes key.
    func attach(to window: NSWindow) {
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                             queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.relink(); self?.sidebar?.setNeedsKeyViewLinking() }
        }
        observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, let root = self.root, let view = window.firstResponder as? NSView,
                      (view as? NSTextView)?.isFieldEditor != true, !self.linked.contains(view),
                      view.isDescendant(of: root), !sequence(first: view, next: \.superview).contains(where: self.excluded)
                else { return }
                self.relink()
            }
        }
    }

    /// The page side's key views, last to the sidebar's gate, first as its way
    /// out. Run after every full chrome layout. Skips rewriting when the
    /// discovered chain and gate links already match the Tab-order contract.
    /// - Returns: `true` when links or the sidebar exit were rewritten.
    @discardableResult
    func relink() -> Bool {
        guard let root, let sidebar else { return false }
        let chain = Self.pageSide(in: root, excluded: excluded, isPage: isPage, passesThrough: passesThrough)
        let entry = sidebar.keyViewEntry
        if Self.isInstalled(chain, entry: entry, exit: sidebar.keyViewExit) {
            syncLinked(chain)
            return false
        }
        Self.link(chain, to: entry)
        sidebar.keyViewExit = chain.first
        syncLinked(chain)
        return true
    }

    /// True when `chain` is already the page-side Tab order into `entry` and
    /// `exit` is the chain's first (nil when empty)—what `relink` would install.
    static func isInstalled(_ chain: [NSView], entry: NSView, exit: NSView?) -> Bool {
        guard exit === chain.first else { return false }
        for (view, following) in zip(chain, chain.dropFirst() + [entry]) {
            if view.nextKeyView !== following || following.previousKeyView !== view { return false }
        }
        return true
    }

    private func syncLinked(_ chain: [NSView]) {
        if linked.count == chain.count, chain.allSatisfy(linked.contains) { return }
        linked.removeAllObjects(); chain.forEach(linked.add)
    }

    static func pageSide(in root: NSView, excluded: @escaping (NSView) -> Bool, isPage: @escaping (NSView) -> Bool,
                         passesThrough: @escaping (NSView) -> Bool = { _ in false }) -> [NSView] {
        func takesFocus(_ view: NSView) -> Bool { SidebarAccessibility.takesFocus(view) }
        func holdsFocusable(_ view: NSView) -> Bool { view.subviews.contains { takesFocus($0) || holdsFocusable($0) } }
        let owners = loopOwners(in: root, excluded: excluded)
        return SidebarAccessibility.keyViews(in: [root], space: root, excluded: { view in
            excluded(view) || owners.contains(ObjectIdentifier(view))
        }, forwards: { view in
            passesThrough(view) || sequence(first: view, next: \.superview).dropFirst().contains(where: isPage) && holdsFocusable(view)
        })
    }

    /// The views below `root` that hold a closed key-view loop of their own: for
    /// each key view whose links lead back to it, the lowest view holding the
    /// whole loop. AppKit's computed loop passes through `root` itself and the
    /// window owner's through the sidebar's gate, so neither is one.
    static func loopOwners(in root: NSView, excluded: (NSView) -> Bool) -> Set<ObjectIdentifier> {
        var owners = Set<ObjectIdentifier>(), seen = Set<ObjectIdentifier>()
        func visit(_ view: NSView) {
            guard !excluded(view) else { return }
            if !seen.contains(ObjectIdentifier(view)), SidebarAccessibility.takesFocus(view), let loop = loop(from: view) {
                loop.forEach { seen.insert(ObjectIdentifier($0)) }
                let holder = loop.dropFirst().reduce(view) { holder, member in
                    sequence(first: holder, next: \.superview).first { member.isDescendant(of: $0) } ?? root
                }
                if holder !== root, holder.isDescendant(of: root) { owners.insert(ObjectIdentifier(holder)) }
            }
            view.subviews.forEach(visit)
        }
        root.subviews.forEach(visit)
        return owners
    }

    /// The views `view`'s links lead through back to it, if they do.
    private static func loop(from view: NSView) -> [NSView]? {
        var members = [view], next = view.nextKeyView
        for _ in 0..<64 {
            guard let current = next else { return nil }
            if current === view { return members }
            members.append(current); next = current.nextKeyView
        }
        return nil
    }

    /// Links `chain` in order and its last view to `entry`. A link from the
    /// page side into the sidebar goes only to its gate.
    static func link(_ chain: [NSView], to entry: NSView) {
        for (view, following) in zip(chain, chain.dropFirst() + [entry]) { SidebarAccessibility.link(view, to: following) }
    }
}
