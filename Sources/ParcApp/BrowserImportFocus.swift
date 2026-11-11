import AppKit

@MainActor
enum BrowserImportFocus {
    static func mayReturn(requested: Bool, appIsActive: Bool, parent: NSWindow,
                          importer: NSWindow?, key: NSWindow?) -> Bool {
        guard requested, appIsActive, parent.isVisible, !parent.isMiniaturized,
              parent.attachedSheet == nil else { return false }
        return key == nil || key === parent || (importer != nil && key === importer)
    }

    static func keyViews(in roots: [NSView]) -> [NSView] {
        roots.flatMap { root in
            controls(in: root).map { ($0, $0.convert($0.bounds, to: nil)) }
                .sorted { a, b in
                    let top = (a.1.maxY.rounded(), b.1.maxY.rounded())
                    return top.0 != top.1 ? top.0 > top.1 : a.1.minX < b.1.minX
                }
                .map(\.0)
        }
    }

    private static func controls(in view: NSView) -> [NSView] {
        view.subviews.flatMap { child -> [NSView] in
            if let label = child as? NSTextField, !label.isEditable { return [] }
            if child is NSControl || String(describing: type(of: child)).hasPrefix("NSHostingView<") { return [child] }
            return (child.acceptsFirstResponder ? [child] : []) + controls(in: child)
        }
    }
}
