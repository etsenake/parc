import AppKit

/// The Notes load-error view's accessibility owner, outside this check.
@MainActor
enum NoteAccessibility {
    static func configureLoadError(_ view: NSView, heading: NSTextField, detail: NSTextField) {}
}
