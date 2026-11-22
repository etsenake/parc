import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore

struct WindowFrameViewTestsRendering {
    private typealias Support = WindowFrameViewTestsSupport

    private typealias CrankView = Support.CrankView
    private typealias LightsImage = Support.LightsImage
    private typealias CrankImage = Support.CrankImage

    @Test(arguments: [0, 7]) @MainActor
    func litPillsGlow(index: Int) throws {
        let image = try LightsImage()
        #expect(image.alpha(at: image.lights.pillCenter(index)) > 0.5)
    }

    @Test @MainActor
    func unlitPillsAreFainterThanLitPills() throws {
        let image = try LightsImage()
        let unlit = image.alpha(at: image.lights.pillCenter(10))
        #expect(unlit > 0)
        #expect(unlit < image.alpha(at: image.lights.pillCenter(7)))
    }

    @Test @MainActor
    func theLightsDoNotPaintABackdrop() throws {
        let image = try LightsImage()
        #expect(image.alpha(at: CGPoint(x: image.lights.bounds.midX + 50, y: image.lights.bounds.midY + 30)) == 0)
    }

    @Test @MainActor
    func theReadoutSitsUnderTheArc() throws {
        let image = try LightsImage()
        let center = CGPoint(x: image.lights.bounds.midX, y: image.lights.bounds.midY - WindowFrameCrankPlacement.lightsRadius)
        #expect(image.alpha(at: center) > 0.8)
    }

    @Test(arguments: [false, true]) @MainActor
    func theCrankRendersOpaqueAtTheHubAndKnob(knob: Bool) throws {
        let model = Support.makeModel()
        let image = try CrankImage(model: model)
        let offset = knob ? model.knobCenter : .zero
        #expect(image.alpha(x: offset.x, y: offset.y) > 0.9)
    }

    @Test(arguments: [false, true]) @MainActor
    func theCrankRendersWithTransparentCorners(positiveCorner: Bool) throws {
        let image = try CrankImage(model: Support.makeModel())
        let corner = (CrankView.side / 2 - 4) * (positiveCorner ? 1 : -1)
        #expect(image.alpha(x: corner, y: corner) == 0)
    }

    @Test @MainActor
    func theCrankShadowIsSoftAndDoesNotAccumulateWherePartsOverlap() throws {
        let image = try Support.shadowImage()
        let offset = WindowFrameCrankModel.shadowOffset
        let hub = image.alpha(x: offset.dx, y: offset.dy)
        let arm = image.alpha(x: offset.dx, y: offset.dy + 36)
        #expect(arm > 0.2 && arm < 0.7)
        #expect(abs(hub - arm) < 0.03)
    }

    @Test @MainActor
    func theCrankShadowEndsPastTheKnob() throws {
        let image = try Support.shadowImage()
        let offset = WindowFrameCrankModel.shadowOffset
        #expect(image.alpha(x: offset.dx, y: offset.dy + 110) < 0.02)
    }
}
