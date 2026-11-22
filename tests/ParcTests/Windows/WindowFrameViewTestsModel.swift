import AppKit
import Metal
import SceneKit
import Testing
@testable import ParcCore
@testable import ParcSettings

struct WindowFrameViewTestsModel {
    private typealias Support = WindowFrameViewTestsSupport

    struct ArmAngle: CustomTestStringConvertible {
        let label: String
        let angle: Double
        let xFraction: Double
        let yFraction: Double

        var testDescription: String { label }
    }

    @Test(arguments: [
        ArmAngle(label: "Upright", angle: 90, xFraction: 0, yFraction: 1),
        ArmAngle(label: "Thirty degrees below horizontal", angle: -30, xFraction: cos(Double.pi / 6), yFraction: -0.5),
    ]) @MainActor
    func theKnobFollowsTheArmAngle(_ sample: ArmAngle) {
        let model = Support.makeModel()
        let reach = WindowFrameCrankModel.armLength * WindowFrameCrankModel.scale
        model.setArm(degrees: sample.angle)
        #expect(Support.near(model.knobCenter, CGPoint(x: reach * sample.xFraction, y: reach * sample.yFraction), 0.05))
    }

    @Test @MainActor
    func theShadowRotorsFollowTheCrankAngle() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        model.setArm(degrees: -30)
        #expect(model.ghostRotors.count == WindowFrameCrankModel.shadowSpread.count)
        #expect(model.ghostRotors.allSatisfy { Support.near($0.eulerAngles.z, model.rotor.eulerAngles.z, 0.0001) })
    }

    @Test @MainActor
    func theCrankFitsThePlacementRadiusAndLength() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        let (low, high) = model.rotor.boundingBox
        let scale = WindowFrameCrankModel.scale
        #expect(abs(high.x * scale - WindowFrameCrankPlacement.swingRadius) < 2)
        #expect((high.x - low.x) * scale > 100 && (high.x - low.x) * scale < 112)
    }

    @Test @MainActor
    func theCrankViewContainsTheWholeCircleOfLights() {
        #expect(WindowFrameCrankView.side >= 2 * WindowFrameCrankPlacement.extent)
    }

    @Test @MainActor
    func aPaletteReusesItsLightingEnvironment() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        #expect(model.scene.lightingEnvironment.contents != nil)
        let environment = WindowFrameCrankModel.cachedEnvironment(deep: Support.light.deep, dark: false)
        #expect(environment != nil && (model.scene.lightingEnvironment.contents as AnyObject) === environment)
    }

    @Test @MainActor
    func aDarkPaletteRelightsTheMetal() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        model.apply(Support.dark)
        #expect(Support.near(model.scene.lightingEnvironment.intensity, 1.6, 0.001))
    }

    @Test @MainActor
    func switchingBackToLightReusesItsLightingEnvironment() throws {
        let model = Support.makeModel()
        let inLight = try #require(model.scene.lightingEnvironment.contents as AnyObject?)
        model.apply(Support.dark)
        model.apply(Support.light)
        #expect((model.scene.lightingEnvironment.contents as AnyObject?) === inLight)
    }

    @Test @MainActor
    func switchingBackToDarkReusesItsLightingEnvironment() throws {
        let model = Support.makeModel()
        model.apply(Support.dark)
        let inDark = try #require(model.scene.lightingEnvironment.contents as AnyObject?)
        model.apply(Support.light)
        model.apply(Support.dark)
        #expect((model.scene.lightingEnvironment.contents as AnyObject?) === inDark)
    }

    @Test @MainActor
    func eachCrankGetsItsOwnNodesFromSharedGeometry() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        let twin = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.dark)
        #expect(twin.arm?.geometry != nil && twin.arm?.geometry === model.arm?.geometry)
        #expect(twin.knob !== model.knob && twin.rotor.childNodes.count == model.rotor.childNodes.count)
    }

    @Test @MainActor
    func thePaddleRisesTowardTheKnob() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        let arm = WindowFrameCrankModel.positions(model.arm?.geometry ?? SCNGeometry())
        let knobEnd = arm.filter { $0.x > 45 }.map(\.z), hubEnd = arm.filter { $0.x < 5 }.map(\.z)
        let rise = (knobEnd.max() ?? 0) - (hubEnd.max() ?? 0)
        #expect(!knobEnd.isEmpty && !hubEnd.isEmpty && abs(rise - WindowFrameCrankModel.paddleLift) < 0.5)
    }

    @Test @MainActor
    func thePaddleGeometryIsSharedAtTheSameDepth() {
        #expect(WindowFrameCrankModel.paddleGeometry(depth: WindowFrameCrankModel.paddleDepth) === WindowFrameCrankModel.paddleGeometry(depth: WindowFrameCrankModel.paddleDepth))
    }

    @Test @MainActor
    func theCrankLabelDoesNotCastAShadow() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        let planes = model.scene.rootNode.childNodes { node, _ in node.geometry is SCNPlane }
        #expect(planes.count == 1)
    }

    @Test @MainActor
    func tinyCrankPartsDoNotCastShadows() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: Support.light)
        #expect(model.shadowParts > 0 && model.shadowParts < model.root.childNodes { node, _ in node.geometry != nil }.count)
    }
}
