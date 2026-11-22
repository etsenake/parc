import AppKit
import ParcCore
import ParcEngine

extension EaselCaptureLayout {
    @MainActor var nativeScrollContainers: [PCNativeCaptureScrollContainer] {
        (scrollContainers ?? []).compactMap {
            PCNativeCaptureScrollContainer(anchorID: $0.anchorID, path: $0.path, scrollOffset: NSPoint(x: $0.scroll.x, y: $0.scroll.y),
                                           frame: NSRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height))
        }
    }
}
