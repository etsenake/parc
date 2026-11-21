import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPacingTests {
    typealias Stage = SidebarPacingStage

    struct Scenario: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let page: Bool
        let from: SidebarPresentation
        let to: SidebarPresentation
        let reversal: SidebarPresentation?
        var midSwipe = false
    }

    nonisolated static let scenarios = [
        Scenario(testDescription: "⌘S hide, empty content", page: false, from: .locked, to: .hidden, reversal: nil),
        Scenario(testDescription: "⌘S reveal, empty content", page: false, from: .hidden, to: .locked, reversal: nil),
        Scenario(testDescription: "⌘S hide, web page", page: true, from: .locked, to: .hidden, reversal: nil),
        Scenario(testDescription: "⌘S reveal, web page", page: true, from: .hidden, to: .locked, reversal: nil),
        Scenario(testDescription: "⌘S with a pending pane floats", page: false, from: .locked, to: .floating, reversal: nil),
        Scenario(testDescription: "⌘S with a pending pane floats, reversed by ⌘S", page: false, from: .locked, to: .floating, reversal: .locked),
        Scenario(testDescription: "hover reveal, or a pending pane opening", page: false, from: .hidden, to: .floating, reversal: nil),
        Scenario(testDescription: "floating dismissal", page: false, from: .floating, to: .hidden, reversal: nil),
        Scenario(testDescription: "⌘S locks a floating sidebar", page: false, from: .floating, to: .locked, reversal: nil),
        Scenario(testDescription: "⌘S hide reversed by ⌘S", page: true, from: .locked, to: .hidden, reversal: .locked),
        Scenario(testDescription: "⌘S reveal reversed by ⌘S", page: true, from: .hidden, to: .locked, reversal: .hidden),
        Scenario(testDescription: "hover reveal reversed by dismissal", page: false, from: .hidden, to: .floating, reversal: .hidden),
        Scenario(testDescription: "⌘S locks a floating sidebar mid-swipe", page: false, from: .floating, to: .locked, reversal: nil, midSwipe: true),
    ]

    static var forcedLight: SpaceTheme {
        var theme = SpaceTheme.singleColor(ThemeColor(red: 0.8, green: 0.88, blue: 0.97)!); theme.appearance = .light; return theme
    }
    static var forcedDark: SpaceTheme { var theme = SpaceTheme(); theme.appearance = .dark; return theme }

    private func stage(_ scenario: Scenario) -> Stage {
        let stage = Stage(showsPage: scenario.page)
        if scenario.midSwipe { swipe(stage, at: 0.95) }
        stage.set(scenario.from)
        return stage
    }

    private func swipe(_ stage: Stage, at progress: CGFloat) {
        stage.rootView.theme = Self.forcedDark; stage.sidebarContainer.theme = Self.forcedDark
        let transition = ThemePagingTransition(from: Self.forcedDark, theme: Self.forcedLight, progress: progress)
        stage.rootView.pagingTransition = transition; stage.sidebarContainer.pagingTransition = transition
    }

    private func exempts(_ from: SidebarPresentation, _ to: SidebarPresentation) -> Bool {
        SidebarTransition(from: from, to: to).keepsFloatingSurface && (to == .locked || from == .locked)
    }

    private func measure(_ stage: Stage, to next: SidebarPresentation) -> (layouts: (prep: Int, group: Int), labels: (prep: Int, group: Int), renderer: Int) {
        var prep = (0, 0)
        stage.tally.reset()
        stage.didPrepare = { prep = (stage.tally.mostLayouts, stage.tally.mostLabelSizes); stage.tally.reset() }
        stage.present(next); stage.commit()
        stage.didPrepare = nil
        return ((prep.0, stage.tally.mostLayouts), (prep.1, stage.tally.mostLabelSizes), stage.tally.rendererSizes)
    }

    @Test(arguments: scenarios)
    func thePreparationAndTheGroupLayEachViewAndLabelOutOnce(_ scenario: Scenario) {
        let s = stage(scenario)
        var work = measure(s, to: scenario.to)
        if let reversal = scenario.reversal { work = measure(s, to: reversal) }
        #expect(work.layouts.prep <= 1 && work.layouts.group <= 1)
        #expect(work.labels.prep <= 1 && work.labels.group <= 1)
        #expect(work.renderer <= 1)
    }

    private func ticks(_ s: Stage, from: SidebarPresentation, to next: SidebarPresentation) -> [String] {
        var before = s.snapshot()
        s.didPrepare = { before = s.snapshot() }
        s.present(next); s.commit()
        s.didPrepare = nil
        return s.ticked(since: before, exemptingMaterials: exempts(from, next))
    }

    @Test(arguments: scenarios)
    func everyGeometryChangeInTheGroupRidesCoreAnimationAndNothingAwaitsLayout(_ scenario: Scenario) {
        let s = stage(scenario)
        var ticked = ticks(s, from: scenario.from, to: scenario.to)
        if let reversal = scenario.reversal { ticked = ticks(s, from: scenario.to, to: reversal) }
        #expect(ticked.isEmpty)
        #expect(!s.needsLayout())
        #expect(s.staleFrames().isEmpty)
    }

    @Test(arguments: scenarios)
    func theSettledFramesAreTheChromeFramesAndNoGeometryAnimationOutlivesTheTransition(_ scenario: Scenario) {
        let s = stage(scenario)
        s.present(scenario.to); s.commit()
        if let reversal = scenario.reversal { s.present(reversal); s.commit() }
        s.finish()
        #expect(s.settledFramesMatch)
        #expect(!s.geometryAnimationsRemain)
    }

    @Test(arguments: scenarios)
    func eachRequestStartsFromWhereThePresentationIs(_ scenario: Scenario) {
        let s = stage(scenario)
        var before = s.snapshot()
        s.present(scenario.to)
        #expect(s.jumps(since: before, tolerance: 20).isEmpty)
        s.commit()
        if let reversal = scenario.reversal {
            before = s.snapshot()
            s.present(reversal)
            #expect(s.jumps(since: before, tolerance: 20).isEmpty)
        }
    }

    @Test func thePagesRendererHearsItsSizes() {
        let s = Stage(showsPage: true)
        s.tally.reset()
        s.set(.hidden)
        #expect(s.tally.rendererSizes > 0)
    }

    @Test(arguments: [false, true])
    func lockingAFloatingSidebarFadesItsShadowOnTheGroupsTiming(midSwipe: Bool) throws {
        let s = Stage()
        if midSwipe { swipe(s, at: 0.95) }
        s.set(.floating)
        s.present(.locked)
        let fade = try #require(s.shadow?.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(abs(fade.duration - 0.08) < 1e-6)
    }

    private func dockState(_ s: Stage) -> (alpha: CGFloat, hidden: Bool, radius: CGFloat) {
        (s.shadow?.alphaValue ?? -1, s.shadow?.isHidden ?? true, s.sidebarContainer.layer?.cornerRadius ?? -1)
    }

    private func materialState(_ s: Stage) -> (blur: CGFloat, dock: CGFloat, dockHidden: Bool) {
        let materials = s.materials
        return (materials.first?.alphaValue ?? -1, materials.count == 2 ? materials[1].alphaValue : -1, materials.count == 2 ? materials[1].isHidden : false)
    }

    private func dock(_ s: Stage) { s.set(.floating); s.present(.locked); s.commit() }

    @Test func theDockFadesItsShadowBlurAndTheWindowsMaterialOnceEach() {
        let s = Stage()
        dock(s)
        #expect(s.fades.count == 3 && s.fades.allSatisfy { $0.map { abs($0 - 0.08) < 1e-6 } == true })
    }

    @Test func aFullPassDuringTheDockKeepsItsShadowCornersAndCrossFade() {
        let s = Stage()
        dock(s)
        s.layoutChrome()
        let state = dockState(s), materials = materialState(s)
        #expect(state.alpha == 0 && !state.hidden && state.radius == FloatingSidebarSurface.cornerRadius)
        #expect(materials.blur == 0 && materials.dock == 1 && !materials.dockHidden)
    }

    @Test func theSettledDockHidesTheShadowAndRestoresTheMaterials() {
        let s = Stage()
        dock(s)
        s.finish()
        let state = dockState(s), materials = materialState(s)
        #expect(state.hidden && state.alpha == FloatingSidebarSurface.shadowAlpha && state.radius == 0)
        #expect(materials.blur == 1 && materials.dock == 0 && materials.dockHidden)
    }

    @Test func theNextFloatAfterADockKeepsItsShadowAndBlur() {
        let s = Stage()
        dock(s); s.finish()
        s.set(.floating)
        let state = dockState(s), materials = materialState(s)
        #expect(!state.hidden && state.alpha == FloatingSidebarSurface.shadowAlpha)
        #expect(materials.blur == 1 && materials.dockHidden)
    }

    @Test func aDockReversedIntoFloatingKeepsTheShadowAndLeavesNoFadeInFlight() {
        let s = Stage()
        dock(s)
        s.present(.floating); s.commit()
        let state = dockState(s), materials = materialState(s)
        #expect(!state.hidden && state.alpha == FloatingSidebarSurface.shadowAlpha && state.radius == FloatingSidebarSurface.cornerRadius)
        #expect(materials.blur == 1 && materials.dock == 0 && materials.dockHidden && s.fades.allSatisfy { $0 == nil })
    }

    private func blended(_ s: Stage) -> Bool {
        let materials = s.materials, blend = FloatingSidebarSurface.pagingBlend(progress: 0.95)
        return materials.count >= 2 && !materials[1].isHidden && abs(materials[0].alphaValue - blend.base) < 1e-6
            && abs(materials[1].alphaValue - blend.incoming) < 1e-6 && materials.dropFirst(2).allSatisfy { $0.isHidden }
    }

    private func swiping() -> Stage { let s = Stage(); swipe(s, at: 0.95); s.set(.floating); return s }

    @Test func floatingMidSwipeShowsTheBlurAndTheSwipesCrossFadeWithoutDockMaterials() {
        #expect(blended(swiping()))
    }

    @Test func theMidSwipeDockFadesFiveSurfacesOnTheGroupsTiming() {
        let s = swiping()
        s.present(.locked); s.commit()
        #expect(s.fades.count == 5 && s.fades.allSatisfy { $0.map { abs($0 - 0.08) < 1e-6 } == true })
    }

    @Test func aFullPassDuringTheMidSwipeDockKeepsItsFades() {
        let s = swiping()
        s.present(.locked); s.commit()
        s.layoutChrome()
        let alphas = s.materials.map(\.alphaValue)
        #expect(alphas.count == 4 && alphas[0] == 0 && alphas[1] == 0 && alphas[2] == 1 && abs(alphas[3] - 0.95) < 1e-6)
        #expect(s.fades.count == 5 && s.fades.allSatisfy { $0.map { abs($0 - 0.08) < 1e-6 } == true })
    }

    @Test func theSettledMidSwipeDockHidesEveryCrossFadeAndRestoresTheWindowsMaterial() {
        let s = swiping()
        s.present(.locked); s.commit(); s.finish()
        let materials = s.materials
        #expect(materials[1].isHidden && materials[0].alphaValue == 1 && materials[2].isHidden && materials[3].isHidden)
    }

    @Test func aMidSwipeDockReversedIntoFloatingKeepsTheBlendAndLeavesNoFade() {
        let s = swiping()
        s.present(.locked); s.commit()
        s.present(.floating); s.commit()
        #expect(blended(s) && s.fades.allSatisfy { $0 == nil })
    }

    struct Look: Equatable { var kind: Int, side: NSAppearance.Name?, alpha: CGFloat }
    private func looks(_ views: [NSVisualEffectView]) -> [Look] {
        views.filter { !$0.isHidden }.map { Look(kind: $0.material.rawValue, side: $0.appearance?.name, alpha: $0.alphaValue) }
    }

    @MainActor final class SettlingSwipe {
        let s = Stage()
        var handOff: (docked: [Look], window: [Look]) = ([], [])
        init(looks: @escaping ([NSVisualEffectView]) -> [Look]) {
            publish(0.6)
            s.set(.floating)
            s.willSettle = { [weak self] in
                guard let self else { return }
                handOff = (looks(Array(s.materials.suffix(2))), looks(s.rootView.subviews.compactMap { $0 as? NSVisualEffectView }))
            }
            s.present(.locked); s.commit()
        }
        func publish(_ progress: CGFloat) {
            let transition = ThemePagingTransition(from: SidebarPacingTests.forcedDark, theme: SidebarPacingTests.forcedLight, progress: progress)
            s.rootView.pagingTransition = transition; s.sidebarContainer.pagingTransition = transition
        }
        func settleSwipe(each: (() -> Void)? = nil) {
            for step in 1...8 { publish(min(1, 0.6 + 0.05 * CGFloat(step))); each?() }
        }
    }

    @Test func aSwipeSettlingDuringTheDockAddsNoLayoutOrGeometryWork() {
        let settling = SettlingSwipe(looks: looks)
        let s = settling.s
        var frames: [[NSRect]] = [], layouts: [Bool] = []
        settling.settleSwipe {
            layouts.append(s.needsLayout())
            frames.append(s.participants.map(\.frame))
        }
        #expect(layouts.count == 8 && !layouts.contains(true))
        #expect(Set(frames.map { $0.map { "\($0)" } }).count == 1)
    }

    @Test func theWindowsCrossFadeFollowsTheSettlingSwipe() {
        let settling = SettlingSwipe(looks: looks)
        settling.settleSwipe()
        let window = settling.s.rootView.subviews.compactMap { $0 as? NSVisualEffectView }
        #expect(window.count == 2 && window[1].alphaValue == 1)
    }

    @Test func theDockedSidebarsMaterialsMatchTheWindowsBlendItHandsOverTo() {
        let settling = SettlingSwipe(looks: looks)
        settling.settleSwipe()
        settling.s.finish()
        #expect(settling.handOff.window.count == 2 && settling.handOff.docked == settling.handOff.window)
        #expect(settling.s.materials.dropFirst().allSatisfy { $0.isHidden })
    }

    @Test func controlAnUnpinnedThemeCanvasIsLeftForAppKitToResizeEveryFrame() {
        let s = Stage(pinsSurface: false)
        s.set(.floating)
        s.present(.locked); s.commit()
        #expect(s.staleFrames().contains("ThemeMetalCanvas"))
    }

    @Test func controlAVisibleUnpinnedDrawingViewIsLeftForAppKitToRedrawEveryFrame() {
        let s = Stage(showsPage: true, visibleStrip: true)
        s.set(.locked)
        s.present(.hidden); s.commit()
        #expect(s.staleFrames().contains("developerToolbar"))
    }

    @Test func controlSettlingMidFlightIsDetectedAsAJump() {
        let s = Stage()
        s.set(.locked)
        s.present(.hidden); s.commit()
        let before = s.snapshot()
        s.settle(); s.commit()
        #expect(!s.jumps(since: before, tolerance: 40).isEmpty)
    }

    @Test func controlASecondGeometryPassLaysOutRelaysLabelsAndResizesTheRendererTwice() {
        let s = Stage(showsPage: true)
        s.passesTwice = true
        s.set(.locked)
        let work = measure(s, to: .hidden)
        #expect(work.layouts.group > 1 && work.labels.group > 1 && work.renderer > 1)
    }
}
