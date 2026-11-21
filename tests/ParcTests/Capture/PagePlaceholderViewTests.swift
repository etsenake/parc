import AppKit
import Testing
@testable import Parc

struct PagePlaceholderViewTests {
    @MainActor private func placeholder() -> PagePlaceholderView {
        PagePlaceholderView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
    }

    private func image(width: Int = 120, height: Int = 80) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    @MainActor @Test func anEmptyPlaceholderDrawsNothingOfItsOwn() {
        let view = placeholder()
        #expect(view.subviews.isEmpty && (view.layer?.sublayers ?? []).isEmpty)
    }

    @MainActor @Test func thePlaceholderShowsOnlyTheStillSnapshot() throws {
        let view = placeholder()
        let snapshot = try image()
        view.show(snapshot)
        let layers = try #require(view.layer?.sublayers)
        let layer = try #require(layers.first)
        #expect(layers.count == 1 && view.subviews.isEmpty)
        #expect(layer.contentsGravity == .resizeAspectFill && layer.animationKeys() == nil)
        #expect((layer.contents as AnyObject?) === snapshot)
    }

    @MainActor @Test func clearingTheSnapshotLeavesThePlaceholderEmpty() throws {
        let view = placeholder()
        view.show(try image())
        view.show(nil)
        let layers = view.layer?.sublayers ?? []
        #expect(layers.isEmpty)
    }

    @MainActor @Test func voiceOverExplainsWhereThePageIsAndHowToMoveIt() {
        #expect(placeholder().accessibilityHelp() == "Shown in another window. Press to move it here.")
    }

    @MainActor @Test func thePlaceholderCanTakeFirstResponder() {
        #expect(placeholder().acceptsFirstResponder)
    }

    @MainActor @Test func accessibilityPressMovesThePageBack() {
        let view = placeholder()
        var presses = 0
        view.onClick = { presses += 1 }
        #expect(view.accessibilityPerformPress())
        #expect(presses == 1)
    }

    @MainActor @Test func aSnapshotDownsamplesJustEnoughToFillItsPane() throws {
        let decoded = PagePlaceholderView.downsampled(try image(width: 240, height: 160), toFill: CGSize(width: 60, height: 30))
        #expect(decoded.width == 60 && decoded.height == 40)
    }

    @MainActor @Test func aSmallSnapshotIsNeverEnlarged() throws {
        let original = try image()
        #expect(PagePlaceholderView.downsampled(original, toFill: CGSize(width: 240, height: 160)) === original)
    }

    @Test(arguments: [
        (CGSize(width: 2880, height: 1800), CGSize(width: 1200, height: 800), 1280),
        (CGSize(width: 2880, height: 1800), CGSize(width: 6000, height: 4000), 2880),
        (CGSize.zero, CGSize(width: 1200, height: 800), 0),
    ])
    func decodingKeepsOnlyThePixelsNeededToFillThePane(_ source: CGSize, _ pane: CGSize, _ longestSide: Int) {
        #expect(PagePlaceholderSnapshot.maxPixelSize(source: source, filling: pane) == longestSide)
    }

    @MainActor @Test func aPNGThumbDecodesToThePaneSizeAndArrivesOnMain() async throws {
        let source = try image(width: 288, height: 180)
        let png = try #require(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
        let result = await withCheckedContinuation { continuation in
            PagePlaceholderSnapshot.thumbnail(fromPNG: png, maxPixelSize: 128) { thumbnail in
                continuation.resume(returning: (thumbnail, Thread.isMainThread))
            }
        }
        let thumbnail = try #require(result.0)
        #expect(thumbnail.width == 128 && thumbnail.height == 80)
        #expect(result.1)
    }

    @MainActor @Test(arguments: [(true, Float(0.6)), (false, Float(1))])
    func aStillPlaceholderImmediatelyShowsItsNewOpacity(_ dimmed: Bool, _ opacity: Float) {
        let layer = CALayer()
        layer.opacity = dimmed ? 1 : 0.6
        PagePlaceholderDim.apply(dimmed, to: layer, animated: false)
        #expect(layer.opacity == opacity)
        #expect(layer.animation(forKey: "placeholderDim") == nil)
    }

    @MainActor @Test(arguments: [(true, 0.225, 0.895), (false, 0.245, 0.865)])
    func changingTheDimUsesTheMatchingSpring(_ dimmed: Bool, _ response: Double, _ damping: Double) throws {
        let layer = CALayer()
        layer.opacity = dimmed ? 1 : 0.6
        PagePlaceholderDim.apply(dimmed, to: layer, animated: true, reduceMotion: false)
        let spring = try #require(layer.animation(forKey: "placeholderDim") as? CASpringAnimation)
        #expect(abs(spring.stiffness - pow(2 * .pi / response, 2)) < 0.001)
        #expect(abs(spring.damping - 4 * .pi * damping / response) < 0.001)
    }
}
