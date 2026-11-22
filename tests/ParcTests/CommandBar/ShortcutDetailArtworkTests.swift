import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcCommandBar

extension ShortcutDetailTestsSupport {
    struct ShortcutDetailArtworkTests {
        private static func artwork() throws -> ShortcutSmileyArtwork {
            let url = try #require(Bundle.module.url(forResource: "smiley", withExtension: "json", subdirectory: "CommandBarFixtures"))
            return try #require(ShortcutSmileyArtwork(data: Data(contentsOf: url)))
        }

        private static func pixels(_ artwork: ShortcutSmileyArtwork, _ seconds: Double) throws -> Data {
            let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            artwork.draw(in: NSRect(x: 0, y: 0, width: 100, height: 100), seconds: seconds, context: context)
            return Data(bytes: try #require(context.data), count: 40000)
        }

        @Test func theBundledWinkTimelineIsThirtyFramesForFiveSeconds() throws {
            let artwork = try Self.artwork()
            #expect(artwork.frameRate == 30 && artwork.duration == 5)
        }

        @Test func faceEyesAndMouthChangeTheRenderedVectors() throws {
            let artwork = try Self.artwork()
            let initial = try Self.pixels(artwork, 0), middle = try Self.pixels(artwork, 1), final = try Self.pixels(artwork, 5)
            #expect(initial != middle && middle != final)
        }

        @Test func playingPastTheEndClampsToTheFinalFrame() throws {
            let artwork = try Self.artwork()
            #expect(try Self.pixels(artwork, 5) == Self.pixels(artwork, 50))
        }

        @Test func playingBeforeTheStartClampsToTheInitialFrame() throws {
            let artwork = try Self.artwork()
            #expect(try Self.pixels(artwork, 0) == Self.pixels(artwork, -1))
        }

        @Test func theFaceRendersThreeStrokesWithEyesInPlaceAndNoSolidRectangle() throws {
            let initial = try Self.pixels(Self.artwork(), 0)
            let covered = stride(from: 3, to: initial.count, by: 4).filter { initial[$0] != 0 }
            #expect(covered.count > 500 && covered.count < 1800)
            #expect(initial[(60 * 100 + 39) * 4 + 3] > 0 && initial[(60 * 100 + 60) * 4 + 3] > 0)
        }

        @Test @MainActor func theAnimatedDecorationIsPassiveAndHiddenFromAccessibility() {
            _ = NSApplication.shared
            let smiley = ShortcutSmileyView(frame: .zero)
            #expect(!smiley.acceptsFirstResponder && smiley.hitTest(.zero) == nil && !smiley.isAccessibilityElement())
        }
    }
}
