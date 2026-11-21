import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct PagePlaceholderCaptureOrderTests {
    typealias Order = PagePlaceholderCaptureOrder

    let first = UUID()
    let second = UUID()

    private func copyOrder(pending start: Set<UUID>, focused: UUID?, visiting: [UUID]) -> [UUID] {
        var pending = start
        var copied: [UUID] = []
        for _ in 0..<visiting.count {
            for tab in visiting where pending.contains(tab) && Order.mayCapture(tab, pending: pending, focused: focused) {
                pending.remove(tab)
                copied.append(tab)
            }
        }
        return copied
    }

    @Test func aSplitCopiesTheFocusedPaneBeforeTheOther() {
        #expect(copyOrder(pending: [first, second], focused: first, visiting: [second, first]) == [first, second])
    }

    @Test func aSplitMovedToAnotherWindowFreezesBothPanes() {
        #expect(Set(copyOrder(pending: [first, second], focused: first, visiting: [second, first])) == [first, second])
    }

    @Test func aPaneNeverWaitsWhenItIsTheOnlyOneToCopy() {
        #expect(Order.mayCapture(second, pending: [second], focused: first))
    }

    @Test func aPaneNeverWaitsWhenNothingIsFocused() {
        #expect(Order.mayCapture(second, pending: [first, second], focused: nil))
    }

    @Test func theFocusedPaneNeverWaits() {
        #expect(Order.mayCapture(first, pending: [first, second], focused: first))
    }

    @Test func aPaneWaitsWhileTheFocusedPanesCopyIsStillToCome() {
        #expect(!Order.mayCapture(second, pending: [first, second], focused: first))
    }

    @Test(arguments: [0, 1, 2])
    func aPaneWaitsForTheFocusedPanesCopyForTheFirstThreeTries(_ attempt: Int) {
        #expect(Order.waits(second, attempt: attempt, pending: [first, second], focused: first))
    }

    @Test(arguments: [3, 4, 5])
    func aPaneCopiesAnywayAfterThreeTries(_ attempt: Int) {
        #expect(!Order.waits(second, attempt: attempt, pending: [first, second], focused: first))
    }

    @Test func theFocusedPaneNeverWaitsOnItself() {
        #expect(!Order.waits(first, attempt: 0, pending: [first, second], focused: first))
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func aRefusedCopyIsTriedAgain(_ attempt: Int) {
        #expect(Order.retries(after: attempt))
    }

    @Test func aCopyTheEngineKeepsRefusingIsLeftBlankAfterTheSixthTry() {
        #expect(!Order.retries(after: 5))
    }

    @Test func retriesBackOffWithEachAttempt() {
        let delays = (0...5).map { Order.delay(before: $0) }
        #expect(delays == delays.sorted() && Set(delays).count == delays.count)
    }
}

struct PagePlaceholderImagesTests {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let one = UUID()
    let two = UUID()
    let three = UUID()

    @MainActor @Test func everyWindowShowingATabsPlaceholderReadsTheTabsOneImage() {
        let images = PagePlaceholderImages()
        images.setShown([first, second], in: one)
        let shared = PagePlaceholderFrame.make(20)
        images.store(shared, for: first)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        #expect(images.image(for: first, in: one) === shared)
        #expect(images.image(for: first, in: two) === shared)
        #expect(images.image(for: first, in: three) === shared)
    }

    @MainActor @Test func aWindowReadsOnlyTheFramesOfItsOwnPlaceholders() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first], in: two)
        images.store(PagePlaceholderFrame.make(20), for: first)
        #expect(images.image(for: second, in: two) == nil)
    }

    @MainActor @Test func aNewFrameReachesEveryWindowShowingTheTab() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        var refreshed: [UUID] = []
        images.observe(in: one) { refreshed.append(one) }
        images.observe(in: two) { refreshed.append(two) }
        images.observe(in: three) { refreshed.append(three) }
        let next = PagePlaceholderFrame.make(30)
        images.store(next, for: first)
        #expect(images.image(for: first, in: three) === next)
        #expect(Set(refreshed) == [one, two, three])
    }

    @MainActor @Test func onlyWindowsShowingATabAreToldAboutItsFrame() {
        let images = PagePlaceholderImages()
        images.setShown([first, second], in: one)
        images.setShown([first], in: two)
        var refreshed: [UUID] = []
        images.observe(in: one) { refreshed.append(one) }
        images.observe(in: two) { refreshed.append(two) }
        images.store(PagePlaceholderFrame.make(40), for: second)
        #expect(refreshed == [one])
    }

    @MainActor @Test func aWindowNoLongerShowingATabLeavesTheFrameToTheWindowsThatDo() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first, third], in: three)
        let frame = PagePlaceholderFrame.make(30)
        images.store(frame, for: first)
        images.setShown([second], in: one)
        #expect(images.image(for: first, in: three) === frame)
    }

    @MainActor @Test func theFrameGoesWhenTheLastWindowShowingThePlaceholderDoes() {
        let images = PagePlaceholderImages()
        images.setShown([first], in: one)
        images.setShown([first], in: two)
        images.setShown([first, third], in: three)
        images.store(PagePlaceholderFrame.make(30), for: first)
        images.setShown([second], in: one)
        images.removeWindow(two)
        images.removeWindow(three)
        #expect(images.image(for: first, in: one) == nil)
        #expect(!images.isShown(first))
        #expect(!images.isShown(third))
    }

    @MainActor @Test func noFrameIsKeptForATabNoWindowShows() {
        let images = PagePlaceholderImages()
        images.store(PagePlaceholderFrame.make(50), for: third)
        #expect(!images.isShown(third))
        #expect(images.image(for: third, in: three) == nil)
    }

    @MainActor @Test func aPrivateWindowsFramesNeverReachARegularWindowNorTheReverse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-placeholder-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let regular = try BrowserStore(directory: root)
        let privateOne = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        let privateTwo = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        regular.placeholderImages.setShown([first], in: one)
        regular.placeholderImages.store(PagePlaceholderFrame.make(60), for: first)
        privateOne.placeholderImages.setShown([first], in: two)
        #expect(regular.placeholderImages.image(for: first, in: one) != nil)
        #expect(privateOne.placeholderImages.image(for: first, in: two) == nil)
    }

    @MainActor @Test func everyPrivateWindowKeepsItsOwnImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-placeholder-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let regular = try BrowserStore(directory: root)
        let privateOne = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        let privateTwo = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                      directory: root, settings: regular.state.settings)
        #expect(privateOne.placeholderImages !== regular.placeholderImages)
        #expect(privateTwo.placeholderImages !== privateOne.placeholderImages)
    }
}

private enum PagePlaceholderFrame {
    static func make(_ width: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        return context.makeImage()!
    }
}
