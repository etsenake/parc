import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcSidebar

enum ExtensionControlsSupport {
    @MainActor static func controlItem(_ id: String, pin: Int? = nil,
                                        execute: @escaping (NSView?) -> Void = { _ in },
                                        context: @escaping (NSView) -> Void = { _ in }) -> ExtensionControlItem {
        ExtensionControlItem(identifier: id, name: "Action " + id, tooltip: "Title " + id,
            accessibilityLabel: "Accessible " + id, image: nil, pinnedIndex: pin,
            canChangePin: true, execute: execute, showContextMenu: context, setPinned: { _ in })
    }
}
