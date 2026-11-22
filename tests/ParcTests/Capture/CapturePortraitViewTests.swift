import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc

extension CapturePortraitTestsSupport {
    struct CapturePortraitViewTests {
        @MainActor
        private struct PortraitViewFixture {
            let fixture: PortraitFixture
            let view: PortraitCaptureView

            init(background: PortraitCaptureOptions.Background = .color, fraction: Double = 0.5, desktop: Bool = true) throws {
                _ = NSApplication.shared
                fixture = try PortraitFixture()
                fixture.options.background = background
                fixture.options.fraction = fraction
                view = PortraitCaptureView(source: fixture.source, pageColor: .green,
                                           composition: fixture.composition(hasDesktop: desktop), defaults: fixture.defaults)
                view.setFrameSize(view.fittingSize)
                view.layoutSubtreeIfNeeded()
            }

            func button(_ label: String) -> NSButton? {
                view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label }
            }
        }

        @MainActor @Test func theFramePageFillsThePaletteCardWidth() throws {
            let page = try PortraitViewFixture()
            #expect(page.view.bounds.size == NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height))
        }

        @MainActor @Test func reopeningAnAppliedFrameLeavesApplyQuiet() throws {
            let page = try PortraitViewFixture()
            #expect(page.view.applyState == .unchanged && !page.view.captureButton.isEnabled)
        }

        @MainActor @Test func theLivePreviewRendersAtTheFullPageSizedImage() throws {
            let page = try PortraitViewFixture()
            let preview = try #require(page.view.previewImage)
            #expect(preview.width == 704 && preview.height == 544)
        }

        struct BackgroundTile: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let label: String
            let background: PortraitCaptureOptions.Background

            static let cases: [Self] = [
                .init(testDescription: "Website color", label: "Use Website Color", background: .page),
                .init(testDescription: "Desktop wallpaper", label: "Use Desktop Wallpaper", background: .desktop),
                .init(testDescription: "Custom color", label: "Use a Color", background: .color),
            ]
        }

        @MainActor @Test(arguments: BackgroundTile.cases)
        func eachTileChoosesItsBackground(_ sample: BackgroundTile) throws {
            let page = try PortraitViewFixture(background: sample.label == "Use a Color" ? .page : .color)
            try #require(page.button(sample.label)).sendClick()
            #expect(page.view.composition.options.background == sample.background)
        }

        @MainActor @Test func movingTheColorSliderChoosesTheColorBackgroundAtThatPosition() throws {
            let page = try PortraitViewFixture(background: .page)
            let slider = try #require(page.view.subviews.compactMap { $0 as? NSSlider }.first)
            slider.doubleValue = 0.7
            slider.sendAction(slider.action!, to: slider.target)
            #expect(page.view.composition.options.background == .color && page.view.composition.options.fraction == 0.7)
        }

        @MainActor @Test func aChangedFrameMakesApplyThePrimaryButton() throws {
            let page = try PortraitViewFixture()
            let slider = try #require(page.view.subviews.compactMap { $0 as? NSSlider }.first)
            slider.doubleValue = 0.7
            slider.sendAction(slider.action!, to: slider.target)
            #expect(page.view.applyState == .pending && page.view.captureButton.isEnabled)
        }

        @MainActor @Test func applyingReportsTheChosenFrame() throws {
            let page = try PortraitViewFixture()
            let slider = try #require(page.view.subviews.compactMap { $0 as? NSSlider }.first)
            slider.doubleValue = 0.7
            slider.sendAction(slider.action!, to: slider.target)
            var applied = false
            page.view.onCapture = { applied = true }
            page.view.captureButton.sendClick()
            #expect(applied && page.view.composition.options.fraction == 0.7)
        }

        @MainActor @Test func escapeLeavesThePage() throws {
            let page = try PortraitViewFixture()
            var canceled = false
            page.view.onCancel = { canceled = true }
            page.view.cancelOperation(nil)
            #expect(canceled)
        }

        @MainActor @Test func aLongErrorKeepsEverySubviewInsideTheCard() throws {
            let page = try PortraitViewFixture()
            page.view.showError(String(repeating: "A desktop error. ", count: 16))
            page.view.setFrameSize(page.view.fittingSize)
            page.view.layoutSubtreeIfNeeded()
            #expect(page.view.subviews.allSatisfy { page.view.bounds.contains($0.frame) })
        }

        @MainActor @Test func aSavedDesktopBackgroundWithoutAWallpaperKeepsApplyDisabled() throws {
            let page = try PortraitViewFixture(background: .desktop, desktop: false)
            #expect(!page.view.captureButton.isEnabled)
        }

        @MainActor @Test func aDeniedWallpaperExplainsScreenRecordingAndKeepsApplyDisabled() async throws {
            let page = try PortraitViewFixture(background: .desktop, desktop: false)
            let load = try #require(page.view.loadDesktop(screen: nil, provider: { _ in throw PortraitDesktopSnapshot.Failure.permission }))
            await load.value
            let messages = page.view.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
            #expect(!page.view.captureButton.isEnabled && messages.contains { $0.contains("Screen Recording") })
        }

        @MainActor @Test func theWatermarkToggleAndBackingChangesDoNotEnableApplyWithoutAWallpaper() throws {
            let page = try PortraitViewFixture(background: .desktop, desktop: false)
            try #require(page.button("Parc watermark")).sendClick()
            page.view.viewDidChangeBackingProperties()
            #expect(!page.view.captureButton.isEnabled)
        }

        @MainActor @Test func choosingTheWebsiteColorReplacesAnUnavailableWallpaper() throws {
            let page = try PortraitViewFixture(background: .desktop, desktop: false)
            try #require(page.button("Use Website Color")).sendClick()
            #expect(page.view.captureButton.isEnabled && page.view.composition.options.background == .page)
        }
    }
}
