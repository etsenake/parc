import AppKit
import Combine
import ParcCore

package final class MenuAction: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func invoke() { block() }
    package static func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let holder = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(invoke), keyEquivalent: "")
        item.target = holder
        item.representedObject = holder
        return item
    }
}
