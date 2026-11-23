import AppKit
import Testing
@testable import ParcEasels

struct EaselScreenChromeTests {
    private let boardFrame = NSRect(x: 10, y: 20, width: 100, height: 40)

    @MainActor
    @Test(arguments: [CGFloat(0.5), 1, 3])
    func placesFrameAndScaledBounds(scale: CGFloat) {
        let view = NSView()
        EaselScreenChrome.place(view, boardFrame: boardFrame, scale: scale)
        #expect(view.frame == boardFrame)
        #expect(view.bounds == NSRect(x: 0, y: 0, width: 100 * scale, height: 40 * scale))
    }

    @MainActor
    @Test
    func placingTwiceWithSameValuesKeepsTheSameGeometry() {
        let view = NSView()
        EaselScreenChrome.place(view, boardFrame: boardFrame, scale: 2)
        let frame = view.frame, bounds = view.bounds
        EaselScreenChrome.place(view, boardFrame: boardFrame, scale: 2)
        #expect(view.frame == frame && view.bounds == bounds)
    }

    @MainActor
    @Test(arguments: [CGFloat(0), .infinity])
    func invalidScaleIsTreatedAsOne(scale: CGFloat) {
        let view = NSView()
        EaselScreenChrome.place(view, boardFrame: boardFrame, scale: scale)
        #expect(view.bounds.size == boardFrame.size)
    }
}
