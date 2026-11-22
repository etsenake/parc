import AppKit
import ImageIO
import ParcTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ParcLibrary

extension CapturePortraitTestsSupport {
    struct CapturePortraitOptionsTests {
        @Test func freshDefaultsUseTheColorBackgroundWithAWatermark() {
            let defaults = TestDefaults("ParcPortraitOptions-")!
            let options = PortraitCaptureOptions(defaults: defaults)
            #expect(options.fraction == 0.95 && options.watermark && options.background == .color)
        }

        @Test func savedOptionsReloadFromTheSameDefaults() {
            let defaults = TestDefaults("ParcPortraitOptions-")!
            var options = PortraitCaptureOptions(defaults: defaults)
            options.fraction = 0.25
            options.background = .page
            options.watermark = false
            options.save(to: defaults)
            let saved = PortraitCaptureOptions(defaults: defaults)
            #expect(saved.fraction == 0.25 && saved.background == .page && !saved.watermark)
        }

        @Test func aNonFiniteSavedColorFallsBackToTheDefault() {
            let defaults = TestDefaults("ParcPortraitOptions-")!
            defaults.set(Double.infinity, forKey: "parc.capture.portrait.color")
            #expect(PortraitCaptureOptions(defaults: defaults).fraction == 0.95)
        }
    }
}
