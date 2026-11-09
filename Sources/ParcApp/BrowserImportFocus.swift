import AppKit

/// An import may return to its original browser only while the user still owns
/// that interaction. The caller separately verifies the browser's live owner.
@MainActor
enum BrowserImportFocus {
    static func mayReturn(requested: Bool, appIsActive: Bool, parent: NSWindow,
                          importer: NSWindow?, key: NSWindow?) -> Bool {
        guard requested, appIsActive, parent.isVisible, !parent.isMiniaturized,
              parent.attachedSheet == nil else { return false }
        return key == nil || key === parent || (importer != nil && key === importer)
    }

    /// Every control in the embedded import, each root in reading order, for
    /// setup's Tab loop. Hidden and disabled controls stay listed so a later
    /// stage of the same import needs no new loop; Tab skips them. A SwiftUI
    /// host is one entry and keeps its own order inside.
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
