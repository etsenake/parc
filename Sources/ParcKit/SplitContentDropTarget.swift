import AppKit
import ParcCore

@MainActor
package protocol SplitContentDropTarget: NSView {
    func acceptsSplitContentDrop(_ info: NSDraggingInfo) -> Bool
}
