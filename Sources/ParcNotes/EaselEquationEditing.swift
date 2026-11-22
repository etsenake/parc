import AppKit
import ParcCore

@MainActor
package protocol EaselEquationEditing: AnyObject {
    var textView: NSTextView { get }
    var onChange: ((String) -> Void)? { get set }
    var onCommit: (() -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }
    var onDismiss: (() -> Void)? { get set }
    var onClickAway: (() -> Void)? { get set }
    func present(anchor: NSRect, error: String?, range: NSRange?)
    func reposition(anchor: NSRect)
    func setError(_ text: String?, range: NSRange?)
    func close(animated: Bool)
    func contains(_ view: NSView) -> Bool
}
