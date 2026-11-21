import AppKit
import Testing
@testable import Parc

@MainActor
struct CommandBarSurfaceTests {
    typealias Support = CommandBarTestSupport

    @MainActor struct Fixture {
        let window: NSWindow
        let surface: PopoverBackgroundView

        init(appearance: NSAppearance? = nil) {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
            surface = PopoverBackgroundView(blending: .withinWindow)
            window.contentView = surface
            window.appearance = appearance
            surface.layoutSubtreeIfNeeded()
            surface.updateLayer()
        }
    }

    @Test(arguments: [true, false])
    func theSurfaceUsesThePopoverMaterial(dark: Bool) {
        let fixture = Fixture(appearance: dark ? Support.dark : Support.light)
        let translucency = fixture.surface.translucency
        #expect(translucency.material == .popover)
        #expect(translucency.state == .followsWindowActiveState)
        #expect(translucency.blendingMode == .withinWindow)
        #expect(!translucency.isEmphasized)
    }

    @Test(arguments: [true, false])
    func theWashMatchesTheAppearance(dark: Bool) {
        let fixture = Fixture(appearance: dark ? Support.dark : Support.light)
        let wash = Support.rgba(fixture.surface.wash.layer?.backgroundColor)
        #expect(Support.near(wash, dark ? SIMD4(0.065, 0.065, 0.065, 0.7) : SIMD4(1, 1, 1, 0.7)))
    }

    @Test(arguments: [true, false])
    func theOuterRingMatchesTheAppearance(dark: Bool) {
        let fixture = Fixture(appearance: dark ? Support.dark : Support.light)
        #expect(Support.near(Support.rgba(fixture.surface.outerBorder.borderColor), SIMD4(0, 0, 0, dark ? 0.9 : 0.34)))
    }

    @Test func theInnerRingShowsInDark() {
        let fixture = Fixture(appearance: Support.dark)
        #expect(Support.near(Support.rgba(fixture.surface.innerBorder.borderColor), SIMD4(1, 1, 1, 0.23)))
    }

    @Test func theInnerRingIsClearInLight() {
        let fixture = Fixture(appearance: Support.light)
        #expect(Support.rgba(fixture.surface.innerBorder.borderColor).w == 0)
    }

    @Test func bothRingsAttachToTheSurfaceLayer() {
        let fixture = Fixture(appearance: Support.dark)
        #expect(fixture.surface.outerBorder.superlayer === fixture.surface.layer)
        #expect(fixture.surface.innerBorder.superlayer === fixture.surface.layer)
    }

    @Test func theWashIsItsOwnViewJustOverTheMaterial() {
        let surface = Fixture(appearance: Support.dark).surface
        #expect(surface.wash.superview === surface)
        #expect(surface.subviews.firstIndex(of: surface.wash) == 1)
        #expect(surface.subviews.first === surface.translucency)
    }

    @Test func ringWidthsFollowThePixel() {
        let fixture = Fixture(appearance: Support.dark)
        #expect(fixture.surface.outerBorder.borderWidth == 1 / fixture.window.backingScaleFactor)
        #expect(fixture.surface.innerBorder.borderWidth == 1)
    }

    @Test func theInnerRingSitsInsideTheOuterPixel() {
        let fixture = Fixture(appearance: Support.dark)
        let pixel = 1 / fixture.window.backingScaleFactor
        #expect(fixture.surface.innerBorder.frame == fixture.surface.bounds.insetBy(dx: pixel, dy: pixel))
        #expect(fixture.surface.innerBorder.cornerRadius == fixture.surface.cornerRadius - pixel)
    }

    @Test func theInlineSidebarBarHasAFillAndNoMaterialOrRing() {
        let fixture = Fixture(appearance: Support.dark)
        fixture.surface.flatFill = true
        fixture.surface.layoutSubtreeIfNeeded()
        fixture.surface.updateLayer()
        #expect(fixture.surface.translucency.isHidden)
        #expect(fixture.surface.wash.isHidden)
        #expect(fixture.surface.outerBorder.borderWidth == 0)
        #expect(fixture.surface.layer?.backgroundColor != nil)
    }

    @Test func theHairlineIsOneDevicePixel() {
        let fixture = Fixture(appearance: Support.dark)
        #expect(CommandBarHairline.height(in: fixture.window) == 1 / fixture.window.backingScaleFactor)
        #expect(CommandBarHairline.height(in: nil) == 1)
    }

    @Test func theHairlinePaintsWhiteTenthInDark() {
        let fixture = Fixture(appearance: Support.dark)
        let hairline = CommandBarHairline(frame: NSRect(x: 12, y: 64, width: 700, height: CommandBarHairline.height(in: fixture.window)))
        fixture.surface.addSubview(hairline)
        hairline.updateLayer()
        #expect(Support.near(Support.rgba(hairline.layer?.backgroundColor), SIMD4(1, 1, 1, 0.1)))
    }
}
