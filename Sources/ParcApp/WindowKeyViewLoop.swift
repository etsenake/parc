import AppKit

@MainActor
protocol SidebarKeyViewEnds: AnyObject {
    var keyViewEntry: NSView { get }
    var keyViewExit: NSView? { get set }
    func setNeedsKeyViewLinking()
}

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

    init(root: NSView, sidebar: any SidebarKeyViewEnds, excluded: @escaping (NSView) -> Bool,
         isPage: @escaping (NSView) -> Bool, passesThrough: @escaping (NSView) -> Bool = { _ in false }) {
        self.root = root; self.sidebar = sidebar; self.excluded = excluded; self.isPage = isPage
        self.passesThrough = passesThrough
    }

    static func windowExcludes(_ view: NSView, sidebarContainer: NSView, parkedPages: NSView, pageHost: NSView,
                               activePeek: () -> NSView?) -> Bool {
        if view === sidebarContainer || view === parkedPages || view is SidebarPreviewSurface { return true }
        guard view.superview === pageHost, let peek = activePeek() else { return false }
        return view !== peek
    }

    deinit { if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) } }

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

    private static func loop(from view: NSView) -> [NSView]? {
        var members = [view], next = view.nextKeyView
        for _ in 0..<64 {
            guard let current = next else { return nil }
            if current === view { return members }
            members.append(current); next = current.nextKeyView
        }
        return nil
    }

    static func link(_ chain: [NSView], to entry: NSView) {
        for (view, following) in zip(chain, chain.dropFirst() + [entry]) { SidebarAccessibility.link(view, to: following) }
    }
}
