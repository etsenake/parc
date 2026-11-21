import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct PagePlaceholderCaptureOrderTests {
    let first = UUID()
    let second = UUID()

    @Test func aSplitMovedToAnotherWindowGetsAFrozenImageForBothPanes() {
        let window = UUID()
        let images = PagePlaceholderImages()
        images.setShown([first, second], in: window)
        var pending: Set<UUID> = [first, second]
        var copied: [UUID] = []
        for _ in 0..<4 {
            for tab in [second, first] where pending.contains(tab)
                && PagePlaceholderCaptureOrder.mayCapture(tab, pending: pending, focused: first) {
                images.store(PagePlaceholderFixtures.frame(10), for: tab)
                pending.remove(tab)
                copied.append(tab)
            }
        }
        #expect(pending.isEmpty)
        #expect(images.image(for: first, in: window) != nil)
        #expect(images.image(for: second, in: window) != nil)
        #expect(copied == [first, second])
    }

    @Test func aPaneWaitsOnlyWhileTheFocusedPanesCopyIsStillToCome() {
        #expect(PagePlaceholderCaptureOrder.mayCapture(second, pending: [second], focused: first))
        #expect(PagePlaceholderCaptureOrder.mayCapture(second, pending: [first, second], focused: nil))
        #expect(PagePlaceholderCaptureOrder.mayCapture(first, pending: [first, second], focused: first))
        #expect(!PagePlaceholderCaptureOrder.mayCapture(second, pending: [first, second], focused: first))
    }

    @Test func aPaneWaitsForTheFocusedPanesCopyForThreeTriesAtMostThenCopiesAnyway() {
        #expect(PagePlaceholderCaptureOrder.waits(second, attempt: 0, pending: [first, second], focused: first))
        #expect(PagePlaceholderCaptureOrder.waits(second, attempt: 2, pending: [first, second], focused: first))
        #expect(!PagePlaceholderCaptureOrder.waits(second, attempt: 3, pending: [first, second], focused: first))
        #expect(!PagePlaceholderCaptureOrder.waits(first, attempt: 0, pending: [first, second], focused: first))
    }

    @Test func aCopyTheEngineKeepsRefusingIsTriedSixTimesOverAboutTwoAndAHalfSecondsThenLeftBlank() {
        var attempt = 0
        var tries = 1
        var waited = PagePlaceholderCaptureOrder.delay(before: 0)
        while PagePlaceholderCaptureOrder.retries(after: attempt) {
            attempt += 1
            tries += 1
            waited += PagePlaceholderCaptureOrder.delay(before: attempt)
        }
        #expect(tries == 6)
        #expect(abs(waited - 2.55) < 0.001)
    }
}

@MainActor
struct PagePlaceholderImagesTests {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let one = UUID()
    let two = UUID()
    let three = UUID()

    @Test func everyWindowShowingATabsPlaceholderReadsTheTabsOneImage() {
        let images = PagePlaceholderImages()
        images.setShown([first, second], in: one)
        let shared = PagePlaceholderFixtures.frame(20)
        images.store(shared, for: first)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        #expect(images.image(for: first, in: one) === shared)
        #expect(images.image(for: first, in: two) === shared)
        #expect(images.image(for: first, in: three) === shared)
    }

    @Test func aWindowReadsOnlyTheFramesOfItsOwnPlaceholders() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first], in: two)
        images.store(PagePlaceholderFixtures.frame(20), for: first)
        #expect(images.image(for: second, in: two) == nil)
    }

    @Test func aNewFrameReachesEveryWindowShowingTheTab() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        var refreshed: [UUID] = []
        images.observe(in: one) { refreshed.append(one) }
        images.observe(in: two) { refreshed.append(two) }
        images.observe(in: three) { refreshed.append(three) }
        let next = PagePlaceholderFixtures.frame(30)
        images.store(next, for: first)
        #expect(images.image(for: first, in: three) === next)
        #expect(Set(refreshed) == [one, two, three])
    }

    @Test func onlyWindowsShowingATabAreToldAboutItsFrame() {
        let images = PagePlaceholderImages()
        images.setShown([first, second], in: one)
        images.setShown([first], in: two)
        var refreshed: [UUID] = []
        images.observe(in: one) { refreshed.append(one) }
        images.observe(in: two) { refreshed.append(two) }
        images.store(PagePlaceholderFixtures.frame(40), for: second)
        #expect(refreshed == [one])
    }

    @Test func aWindowNoLongerShowingATabLeavesTheFrameToTheWindowsThatDo() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first, third], in: three)
        let frame = PagePlaceholderFixtures.frame(30)
        images.store(frame, for: first)
        images.setShown([second], in: one)
        #expect(images.image(for: first, in: three) === frame)
    }

    @Test func theFrameGoesWhenTheLastWindowShowingThePlaceholderDoes() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        images.store(PagePlaceholderFixtures.frame(30), for: first)
        images.setShown([second], in: one)
        images.removeWindow(two)
        images.removeWindow(three)
        #expect(images.image(for: first, in: one) == nil)
        #expect(!images.isShown(first))
        #expect(!images.isShown(third))
    }

    @Test func noFrameIsKeptForATabNoWindowShows() {
        let images = PagePlaceholderImages()
        images.store(PagePlaceholderFixtures.frame(50), for: third)
        #expect(!images.isShown(third))
        #expect(images.image(for: third, in: three) == nil)
    }

    @Test func aPrivateWindowsFramesNeverReachARegularWindowNorTheReverse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-placeholder-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let regular = try BrowserStore(directory: root)
        let privateOne = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        let privateTwo = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        regular.placeholderImages.setShown([first], in: one)
        regular.placeholderImages.store(PagePlaceholderFixtures.frame(60), for: first)
        privateOne.placeholderImages.setShown([first], in: two)
        #expect(regular.placeholderImages.image(for: first, in: one) != nil)
        #expect(privateOne.placeholderImages.image(for: first, in: two) == nil)
        #expect(privateOne.placeholderImages !== regular.placeholderImages)
        #expect(privateTwo.placeholderImages !== privateOne.placeholderImages)
    }
}

enum PagePlaceholderFixtures {
    static func frame(_ width: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        return context.makeImage()!
    }
}
