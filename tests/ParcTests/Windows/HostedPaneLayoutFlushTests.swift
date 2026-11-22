import AppKit
import Testing
@testable import Parc

@MainActor
struct HostedPaneLayoutFlushTests {
    @MainActor private final class Document: NSView {
        var laidOutSizes: [NSSize] = []

        override func layout() {
            super.layout()
            laidOutSizes.append(bounds.size)
        }
    }

    @Test(arguments: [false, true])
    func aPaneFlushesOnlyDirtyHostedContentAtTheSameSize(dirty: Bool) {
        let pane = BrowserPane(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = Document()
        pane.showNativeContent(document)
        pane.layout()
        document.laidOutSizes.removeAll()
        document.needsLayout = dirty

        pane.layout()

        #expect(document.laidOutSizes == (dirty ? [pane.contentBounds.size] : []))
    }

    @Test func resizingThePaneLaysOutTheHostedDocumentAtItsNewSize() {
        let pane = BrowserPane(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = Document()
        pane.showNativeContent(document)
        pane.layout()
        document.laidOutSizes.removeAll()

        pane.setFrameSize(NSSize(width: 640, height: 480))
        pane.layout()

        #expect(document.bounds.size == pane.contentBounds.size)
        #expect(document.laidOutSizes.last == pane.contentBounds.size)
    }
}
