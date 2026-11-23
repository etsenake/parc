import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ParcLibrary

extension CapturePortraitTestsSupport {
    struct CapturePortraitRendererTests {
        struct OutputSize: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let source: CGSize
            let expected: CGSize

            static let cases: [Self] = [
                .init(testDescription: "Large source kept at full size", source: .init(width: 4000, height: 2000), expected: .init(width: 4320, height: 2320)),
                .init(testDescription: "Small source kept at size", source: .init(width: 320, height: 160), expected: .init(width: 400, height: 240)),
            ]
        }

        @MainActor @Test(arguments: OutputSize.cases)
        func outputSizeFitsTheSourceInsideTheFrame(_ sample: OutputSize) {
            #expect(PortraitCaptureRenderer.geometry(pixels: sample.source, backingScale: 1)?.canvas == sample.expected)
        }

        @MainActor @Test func theBundledPaletteHasNineColors() {
            #expect(PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor").count == 9)
        }

        @MainActor @Test func aNonNumberBlendsToNoColor() {
            let palette = PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor")
            #expect(PortraitCaptureRenderer.blendedColor(.nan, palette: palette) == nil)
        }

        @MainActor @Test(arguments: [0, 1, 2])
        func theFirstEndpointBlendsToTheFirstPaletteColor(_ channel: Int) throws {
            let palette = PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor")
            let endpoint = try #require(PortraitCaptureRenderer.blendedColor(0, palette: palette)?.usingColorSpace(.sRGB))
            let first = try #require(palette[0].usingColorSpace(.sRGB))
            let components = [(endpoint.redComponent, first.redComponent), (endpoint.greenComponent, first.greenComponent),
                              (endpoint.blueComponent, first.blueComponent)]
            #expect(abs(components[channel].0 - components[channel].1) < 0.00001)
        }

        @MainActor @Test func aPageBackgroundFramesTheSourceAtTheOutputSize() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let page = try fixture.render()
            #expect(page.width == 400 && page.height == 240)
        }

        @MainActor @Test func theLeftHalfOfTheSourceStaysRed() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let left = PortraitFixture.sample(try fixture.render(), x: 120, y: 120)
            #expect(left[0] > 245 && left[2] < 10)
        }

        @MainActor @Test func theRightHalfOfTheSourceStaysBlue() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let right = PortraitFixture.sample(try fixture.render(), x: 280, y: 120)
            #expect(right[2] > 245 && right[0] < 10)
        }

        @MainActor @Test func aColorBackgroundKeepsTheSamePixelsInsideTheFrame() throws {
            let fixture = try PortraitFixture()
            var page = fixture.options
            page.background = .page
            var color = fixture.options
            color.background = .color
            #expect(PortraitFixture.sample(try fixture.render(color), x: 120, y: 120) == PortraitFixture.sample(try fixture.render(page), x: 120, y: 120))
        }

        @MainActor @Test func aColorBackgroundPaintsTheMarginDifferentlyFromTheWebsiteColor() throws {
            let fixture = try PortraitFixture()
            var page = fixture.options
            page.background = .page
            var color = fixture.options
            color.background = .color
            #expect(PortraitFixture.sample(try fixture.render(color), x: 8, y: 8) != PortraitFixture.sample(try fixture.render(page), x: 8, y: 8))
        }

        @MainActor @Test func aDesktopBackgroundDrawsTheWallpaper() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            let desktop = try fixture.render(desktop: fixture.wallpaper)
            #expect(PortraitFixture.sample(desktop, x: 8, y: 8)[0] < 10)
        }

        @MainActor @Test func aMissingDesktopNeverSilentlyBecomesAColorBackground() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            #expect(throws: PortraitCaptureError.desktopUnavailable) { try fixture.render(desktop: nil) }
        }

        @MainActor @Test func theWatermarkChangesTheRenderedPixels() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            fixture.options.watermark = false
            let plain = try fixture.render(desktop: fixture.wallpaper)
            fixture.options.watermark = true
            let marked = try fixture.render(desktop: fixture.wallpaper)
            #expect((marked.dataProvider!.data! as Data) != (plain.dataProvider!.data! as Data))
        }

        @MainActor @Test func desktopContrastSamplesTheBottomWatermarkFootprint() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            let split = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
                NSColor.black.setFill()
                rect.fill()
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 100, height: 50).fill()
                return true
            }
            fixture.options.watermark = true
            let marked = try fixture.render(desktop: split)
            fixture.options.watermark = false
            let plain = try fixture.render(desktop: split)
            var darker = 0
            for y in 8..<32 {
                for x in 140..<260 where PortraitFixture.sample(marked, x: x, y: y)[0] < PortraitFixture.sample(plain, x: x, y: y)[0] {
                    darker += 1
                }
            }
            #expect(darker > 0)
        }

        @MainActor @Test func aPreviewRendersWithinThePreviewSide() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            let preview = try PortraitCaptureRenderer.render(source: fixture.source, options: fixture.options, palette: fixture.palette,
                                                             pageColor: .green, desktop: fixture.wallpaper,
                                                             fitting: CGSize(width: 220, height: 220))
            #expect(preview.width == 220 && preview.height == 132)
        }

        @MainActor @Test func aRetinaRenderDoublesTheOutputPixels() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            let retina = try fixture.render(desktop: fixture.wallpaper, backingScale: 2)
            #expect(retina.width == 480 && retina.height == 320)
        }

        @MainActor @Test func aRetinaRenderKeepsTheSourcePixels() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            let retina = try fixture.render(desktop: fixture.wallpaper, backingScale: 2)
            #expect(PortraitFixture.sample(retina, x: 120, y: 120)[0] > 245)
        }

        @MainActor @Test func aWideGamutSourceKeepsItsColorSpaceAndColors() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .desktop
            let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
            let context = PortraitFixture.context(width: 320, height: 160, space: p3)
            context.setFillColor(CGColor(colorSpace: p3, components: [0.8, 0.2, 0.4, 1])!)
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
            let wide = context.makeImage()!
            let result = try fixture.render(desktop: fixture.wallpaper, source: wide)
            #expect(result.colorSpace?.name == CGColorSpace.displayP3)
            let expected = PortraitFixture.sample(wide, x: 100, y: 100)
            let actual = PortraitFixture.sample(result, x: 120, y: 120)
            #expect(zip(expected, actual).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        }

        struct WatermarkInk: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let gray: CGFloat
            let red: CGFloat
            let alpha: CGFloat

            static let cases: [Self] = [
                .init(testDescription: "Light backdrop", gray: 0.75, red: 0, alpha: 0.45),
                .init(testDescription: "Dark backdrop", gray: 0.74, red: 1, alpha: 0.75),
            ]
        }

        @MainActor @Test(arguments: WatermarkInk.cases)
        func watermarkInkContrastsWithTheBackdrop(_ sample: WatermarkInk) {
            let ink = PortraitCaptureRenderer.watermarkInk(on: NSColor(srgbRed: sample.gray, green: sample.gray, blue: sample.gray, alpha: 1))
            #expect(ink.usingColorSpace(.sRGB)!.redComponent == sample.red && ink.alphaComponent == sample.alpha)
        }
    }
}
