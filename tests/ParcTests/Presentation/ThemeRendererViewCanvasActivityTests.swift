import AppKit
import MetalKit
import Testing
import ParcCore
@testable import Parc

extension ThemeRendererViewTestsSupport {
    struct ThemeRendererViewCanvasActivityTests {
        @Test @MainActor func aZeroNoiseThemeSkipsActivityInvalidation() throws {
            let surface = Surface(tracksPendingRedraws: true)
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.window.reportsKey = true
            surface.post(NSWindow.didBecomeKeyNotification)
            #expect(surface.root.canvasActivityDisplayInvalidations == before)
        }

        @Test @MainActor func aNoisyThemeRedrawsWhenBecomingKeyFlipsActivity() throws {
            let surface = Surface(tracksPendingRedraws: true)
            surface.noisy()
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.window.reportsKey = true
            surface.post(NSWindow.didBecomeKeyNotification)
            #expect(surface.root.canvasActivityDisplayInvalidations == before + 1)
        }

        @Test @MainActor func becomingMainWhileKeyLeavesActivityAndSkipsTheRedraw() throws {
            let surface = Surface(tracksPendingRedraws: true)
            surface.noisy()
            surface.window.reportsKey = true
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.window.reportsMain = true
            surface.post(NSWindow.didBecomeMainNotification)
            #expect(surface.root.canvasActivityDisplayInvalidations == before)
        }

        @Test @MainActor func pairedKeyAndMainNotificationsRedrawOnce() throws {
            let surface = Surface(tracksPendingRedraws: true)
            surface.noisy()
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.window.reportsKey = true
            surface.window.reportsMain = true
            surface.post(NSWindow.didBecomeKeyNotification)
            surface.post(NSWindow.didBecomeMainNotification)
            #expect(surface.root.canvasActivityDisplayInvalidations == before + 1)
        }

        @Test @MainActor func resigningKeyWhileMainKeepsActivityAndSkipsTheRedraw() throws {
            let surface = Surface(tracksPendingRedraws: true)
            surface.noisy()
            surface.window.reportsKey = true
            surface.window.reportsMain = true
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.window.reportsKey = false
            surface.post(NSWindow.didResignKeyNotification)
            #expect(surface.root.canvasActivityDisplayInvalidations == before)
        }

        @Test @MainActor func resigningMainAfterKeyFlipsActivityAndRedraws() throws {
            let surface = Surface(tracksPendingRedraws: true)
            surface.noisy()
            surface.window.reportsMain = true
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.window.reportsMain = false
            surface.post(NSWindow.didResignMainNotification)
            #expect(surface.root.canvasActivityDisplayInvalidations == before + 1)
        }

        @Test @MainActor func aThemeRefreshRepublishesThePaletteWithoutTheActivityPath() throws {
            let surface = Surface(tracksPendingRedraws: true)
            surface.noisy()
            try surface.settleCanvas()
            let before = surface.root.canvasActivityDisplayInvalidations
            surface.root.theme = Surface.lightTheme
            #expect(surface.root.canvasActivityDisplayInvalidations == before)
            #expect(!surface.root.palette.isDark)
        }
    }
}
