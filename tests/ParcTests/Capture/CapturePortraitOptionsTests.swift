import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc

extension CapturePortraitTestsSupport {
    struct CapturePortraitOptionsTests {
        private func suite() -> (UserDefaults, String) {
            let name = "ParcPortraitOptions-" + UUID().uuidString
            return (UserDefaults(suiteName: name)!, name)
        }

        @Test func freshDefaultsUseTheColorBackgroundWithAWatermark() {
            let (defaults, name) = suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let options = PortraitCaptureOptions(defaults: defaults)
            #expect(options.fraction == 0.95 && options.watermark && options.background == .color)
        }

        @Test func savedOptionsReloadFromTheSameDefaults() {
            let (defaults, name) = suite()
            defer { defaults.removePersistentDomain(forName: name) }
            var options = PortraitCaptureOptions(defaults: defaults)
            options.fraction = 0.25
            options.background = .page
            options.watermark = false
            options.save(to: defaults)
            let saved = PortraitCaptureOptions(defaults: defaults)
            #expect(saved.fraction == 0.25 && saved.background == .page && !saved.watermark)
        }

        @Test func aNonFiniteSavedColorFallsBackToTheDefault() {
            let (defaults, name) = suite()
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(Double.infinity, forKey: "parc.capture.portrait.color")
            #expect(PortraitCaptureOptions(defaults: defaults).fraction == 0.95)
        }
    }
}
