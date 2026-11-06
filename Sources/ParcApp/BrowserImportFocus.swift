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
}
