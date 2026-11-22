import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc

extension CapturePortraitTestsSupport {
    struct CapturePortraitWallpaperTests {
        private static let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)

        private static func candidate(bundle: String, title: String, layer: Int) -> PortraitDesktopSnapshot.Candidate {
            PortraitDesktopSnapshot.Candidate(id: 1, processID: 1, bounds: display, bundle: bundle, title: title, layer: layer)
        }

        @MainActor @Test func theWindowManagerWallpaperWindowIsTheDesktop() {
            #expect(Self.candidate(bundle: "com.apple.WindowManager", title: "Wallpaper", layer: -2147483624).isWallpaper(for: Self.display))
        }

        @MainActor @Test func aWallpaperOnAnotherDisplayIsNotTheDesktop() {
            let wallpaper = Self.candidate(bundle: "com.apple.WindowManager", title: "Wallpaper", layer: -2147483624)
            #expect(!wallpaper.isWallpaper(for: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        }

        struct SystemWindow: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let bundle: String
            let title: String
            let layer: Int

            static let cases: [Self] = [
                .init(testDescription: "Mission Control", bundle: "com.apple.dock", title: "Mission Control", layer: -1),
                .init(testDescription: "Finder wallpaper title", bundle: "com.apple.finder", title: "Wallpaper", layer: -1),
                .init(testDescription: "Dock", bundle: "com.apple.dock", title: "Dock", layer: 20),
            ]
        }

        @MainActor @Test(arguments: SystemWindow.cases)
        func otherSystemWindowsAreNotTheDesktop(_ sample: SystemWindow) {
            #expect(!Self.candidate(bundle: sample.bundle, title: sample.title, layer: sample.layer).isWallpaper(for: Self.display))
        }
    }
}
