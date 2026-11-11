import CoreGraphics
import Foundation

/// The frozen frame of a tab, shared by every window that shows its
/// placeholder, and the order a window copies its arrived panes in.
@main @MainActor
struct PagePlaceholderImagesTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }

    nonisolated static func frame(_ width: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        return context.makeImage()!
    }

    /// The engine copies only the page its window has selected, or the one the
    /// window has lent the selection to for that copy.
    struct Engine {
        var selected: UUID
        func copies(_ step: PagePlaceholderCaptureOrder.Step) -> CGImage? {
            step.lendsSelection || step.tab == selected ? frame(10) : nil
        }
    }

    static func main() throws {
        let first = UUID(), second = UUID(), third = UUID()
        let one = UUID(), two = UUID(), three = UUID()

        // A split of two tabs moves to another window: both panes get a frame.
        let images = PagePlaceholderImages()
        images.setShown([first, second], in: one)
        var pending = [first, second]
        let engine = Engine(selected: first)
        for step in PagePlaceholderCaptureOrder.steps(pending, selected: engine.selected) {
            if let copy = engine.copies(step) { images.store(copy, for: step.tab); pending.removeAll { $0 == step.tab } }
        }
        expect(pending.isEmpty && images.image(for: first, in: one) != nil && images.image(for: second, in: one) != nil,
               "a split moved to another window gets a frozen image for both panes")
        let order = PagePlaceholderCaptureOrder.steps([second, first, third], selected: first)
        expect(order.map(\.tab) == [first, second, third] && order.map(\.lendsSelection) == [false, true, true],
               "the selected pane is copied first with nothing lent; each other pane borrows the selection")
        expect(PagePlaceholderCaptureOrder.steps([second], selected: first) == [.init(tab: second, lendsSelection: true)]
               && PagePlaceholderCaptureOrder.steps([], selected: first).isEmpty,
               "a lone arrival that is not selected still borrows it")

        // A third window showing the same placeholder reuses the one image.
        let shared = frame(20)
        images.store(shared, for: first)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        expect(images.image(for: first, in: one) === shared && images.image(for: first, in: two) === shared
               && images.image(for: first, in: three) === shared,
               "every window showing a tab's placeholder reads the tab's one image")
        expect(images.image(for: second, in: two) == nil, "a window reads only the frames of its own placeholders")
        var refreshed: [UUID] = []
        images.observe(in: one) { refreshed.append(one) }
        images.observe(in: two) { refreshed.append(two) }
        images.observe(in: three) { refreshed.append(three) }
        let next = frame(30)
        images.store(next, for: first)
        expect(images.image(for: first, in: three) === next && Set(refreshed) == [one, two, three],
               "a new frame reaches every window showing the tab, not just the one the page left")
        refreshed.removeAll()
        images.store(frame(40), for: second)
        expect(refreshed == [one], "only windows showing a tab are told about its frame")

        // Frames are kept only while some window shows the placeholder.
        images.setShown([second], in: one)
        expect(images.image(for: first, in: three) === next,
               "a window no longer showing a tab leaves the frame to the windows that do")
        images.removeWindow(two)
        images.removeWindow(three)
        expect(images.image(for: first, in: one) == nil && !images.isShown(first) && !images.isShown(third),
               "the frame goes when the last window showing the placeholder does")
        images.store(frame(50), for: third)
        expect(!images.isShown(third) && images.image(for: third, in: three) == nil, "no frame is kept for a tab no window shows")

        // Private windows have their own store, so their frames stay with them.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-placeholder-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let regular = try BrowserStore(directory: root)
        let privateOne = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        let privateTwo = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        regular.placeholderImages.setShown([first], in: one)
        regular.placeholderImages.store(frame(60), for: first)
        privateOne.placeholderImages.setShown([first], in: two)
        expect(regular.placeholderImages.image(for: first, in: one) != nil && privateOne.placeholderImages.image(for: first, in: two) == nil
               && privateOne.placeholderImages !== regular.placeholderImages && privateTwo.placeholderImages !== privateOne.placeholderImages,
               "a private window's frames never reach a regular window, nor the reverse")
        print("PagePlaceholderImagesTests: \(count) assertions passed")
    }
}
