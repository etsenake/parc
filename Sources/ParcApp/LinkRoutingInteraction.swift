import AppKit
import QuartzCore

/// Native interaction support for the Air Traffic Control editor.
@MainActor
enum LinkRoutingInteraction {
    struct FieldID: Equatable {
        let ruleID: UUID
        let conditionID: UUID
    }

    struct FieldFocus {
        let id: FieldID
        let selection: NSRange
    }

    /// Capture only the actual first-responder field editor, keyed by the
    /// rule and condition identity rather than the transient view instance.
    static func captureFocus(in window: NSWindow?, fields: [(FieldID, NSTextField)]) -> FieldFocus? {
        guard let window, window.isKeyWindow, window.attachedSheet == nil else { return nil }
        for (id, field) in fields {
            guard field.window === window, let editor = field.currentEditor(),
                  window.firstResponder === editor else { continue }
            return FieldFocus(id: id, selection: editor.selectedRange)
        }
        return nil
    }

    /// Restore only an identity still present after rebuilding the editor.
    /// A deleted condition must never transfer its selection to another one.
    static func restoreFocus(_ snapshot: FieldFocus?, in window: NSWindow?,
                             fields: [(FieldID, NSTextField)]) {
        guard let snapshot, let field = fields.first(where: { $0.0 == snapshot.id })?.1 else { return }
        focus(field, in: window)
        guard let window, window.isKeyWindow, window.attachedSheet == nil,
              let editor = field.currentEditor(), window.firstResponder === editor else { return }
        let length = (field.stringValue as NSString).length
        let location = min(snapshot.selection.location, length)
        let count = min(snapshot.selection.length, length - location)
        editor.selectedRange = NSRange(location: location, length: count)
    }

    ///
    ///
    /// view and Reduce Motion branch are Parc adaptations.
    static func revealAddedRule(_ row: NSView, in scroll: NSScrollView) {
        guard let document = scroll.documentView, row.isDescendant(of: document),
              row.window != nil else { return }
        let clip = scroll.contentView
        let rect = row.convert(row.bounds, to: document)
        let visible = clip.bounds.size
        let top = document.isFlipped ? rect.minY : rect.maxY - visible.height
        let maxY = max(document.bounds.minY, document.bounds.maxY - visible.height)
        let origin = NSPoint(x: clip.bounds.origin.x,
                             y: min(max(top, document.bounds.minY), maxY))
        guard origin != clip.bounds.origin else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            clip.scroll(to: origin)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
            }
        }
        scroll.reflectScrolledClipView(clip)
    }

    /// Focus follows the live control and its owning sheet, never a discarded
    /// editor subtree. Caller chooses the rule/component identity.
    @discardableResult
    static func focus(_ control: NSView?, in window: NSWindow?) -> Bool {
        guard let control, let window, control.window === window,
              window.isKeyWindow, window.attachedSheet == nil,
              !control.isHiddenOrHasHiddenAncestor,
              (control as? NSControl)?.isEnabled != false else { return false }
        return window.makeFirstResponder(control)
    }

    /// The caller supplies all visible sheet controls in visual order,
    /// including header and footer; AppKit skips controls that cannot focus.
    static func linkKeyViews(_ views: [NSView], in window: NSWindow?) {
        guard let window else { return }
        let controls = views.filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }
        guard !controls.isEmpty else { return }
        for index in controls.indices {
            controls[index].nextKeyView = controls[(index + 1) % controls.count]
        }
    }

    /// Report persistence/validation failures without replacing the draft.
    static func announceError(_ message: String?, in window: NSWindow?) {
        guard let message, !message.isEmpty, let window, window.isVisible else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
