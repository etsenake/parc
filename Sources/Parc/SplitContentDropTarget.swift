import AppKit
import ParcCore

@MainActor
protocol SplitContentDropTarget: NSView {
    func acceptsSplitContentDrop(_ info: NSDraggingInfo) -> Bool
}
