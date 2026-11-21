import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct DownloadArrivalFlightTests {
    private func flight(bin: Bool, source: CGPoint = CGPoint(x: 615, y: 485),
                        window: CGSize = CGSize(width: 1200, height: 800)) -> DownloadArrivalFlight {
        DownloadArrivalFlight(source: source, destination: DownloadArrivalFlight.destinationArgument, windowSize: window, showsBin: bin)
    }

    @Test(arguments: [false, true])
    func anOrdinaryFlightStartsAtTheOriginalPointer(_ bin: Bool) {
        let flight = flight(bin: bin)
        #expect(flight.isRenderable)
        #expect(flight.positions.first == CGPoint(x: 615, y: 485))
        #expect(flight.scales.first == CGPoint(x: 0.8, y: 1.2))
    }

    @Test func aBinnedFlightBouncesAndComesToRestAtTheBin() throws {
        let flight = flight(bin: true)
        let last = try #require(flight.positions.last)
        #expect(flight.destination == CGPoint(x: 62, y: 70))
        #expect(last == CGPoint(x: 70, y: 70))
        #expect(flight.positions.contains { $0.y < last.y })
    }

    @Test func anUnbinnedFlightContinuesPastTheExitAndShrinks() throws {
        let flight = flight(bin: false)
        let last = try #require(flight.positions.last)
        let scale = try #require(flight.scales.last)
        #expect(flight.destination == CGPoint(x: 32, y: 40))
        #expect(last.x < flight.destination.x && last.y < flight.destination.y)
        #expect(scale.x < 0.1 && scale.y < 0.1)
    }

    @Test(arguments: [
        (CGPoint(x: 100, y: 100), true, 1.1244606467093237, 2.2666666666666635),
        (CGPoint(x: 100, y: 100), false, 1.143920560767664, 1.2833333333333337),
        (CGPoint(x: 1100, y: 700), true, 0.9711866097121664, 2.116666666666664),
        (CGPoint(x: 70, y: 70), false, 1.1550740817055343, 1.3000000000000003),
    ])
    func theSourceAndBinDetermineTheFlightDuration(_ source: CGPoint, _ bin: Bool, _ projectile: Double, _ total: Double) {
        let flight = flight(bin: bin, source: source)
        #expect(abs(flight.projectileDuration - projectile) < 1e-9)
        #expect(abs(flight.duration - total) < 1e-9)
    }

    @Test(arguments: [false, true])
    func anImpossibleTrajectoryDoesNotProduceRenderableFrames(_ bin: Bool) {
        let flight = flight(bin: bin, source: CGPoint(x: 600, y: 29.09), window: CGSize(width: 1200, height: 20))
        #expect(!flight.isRenderable)
        #expect(flight.projectileDuration == 0)
    }
}

struct DownloadArrivalSpringTests {
    @Test func configuringTheBinSpringUsesItsResponseAndDamping() {
        var spring = DownloadArrivalSpring()
        spring.configure(response: 0.9, dampingRatio: 0.82)
        #expect(abs(spring.stiffness - 48.738787165873376) < 1e-9)
        #expect(abs(spring.damping - 11.4493598930828) < 1e-9)
    }

    @Test func anUnderdampedBinSpringSettlesExactlyOnItsDestination() throws {
        var spring = DownloadArrivalSpring(initialValue: SIMD2(-80, 0))
        spring.configure(response: 0.9, dampingRatio: 0.82)
        spring.toValue = SIMD2(53, 0)
        let frames = spring.keyframeValues()
        let first = try #require(frames.first)
        #expect(abs(first.x - (-79.15526349351643)) < 1e-9)
        #expect(frames.last == SIMD2(53, 0))
    }

    @Test func aCriticallyDampedSpringUsesItsCriticalSolution() {
        var spring = DownloadArrivalSpring(initialValue: SIMD2(10, 0))
        spring.configure(response: 1.2, dampingRatio: 1)
        spring.toValue = .zero
        let omega = 2 * Double.pi / 1.2, dt = 1.0 / 60
        spring.tick(dt)
        #expect(abs(spring.value.x - 10 * exp(-omega * dt) * (1 + omega * dt)) < 1e-9)
    }

    @Test(arguments: [(4.005, true), (4.02, false)])
    func theSpringSettlesOnlyWithinItsPositionTolerance(_ target: Double, _ resolved: Bool) {
        var spring = DownloadArrivalSpring(initialValue: SIMD2(4, 0))
        spring.toValue = SIMD2(target, 0)
        #expect(spring.hasResolved == resolved)
    }

    @Test func nonFiniteSpringInputCannotProduceKeyframes() {
        var spring = DownloadArrivalSpring()
        spring.toValue = SIMD2(.nan, 0)
        #expect(spring.keyframeValues().isEmpty)
    }
}

struct DownloadArrivalAdmissionTests {
    struct Admission: Sendable {
        var valid = true
        var page = true
        var popup = false
        var privateWindow = false
        var context: String?
        var live = false
        var profile = true

        static let refused = [
            Admission(valid: false), Admission(page: false), Admission(popup: true), Admission(profile: false),
            Admission(context: "private"), Admission(privateWindow: true), Admission(privateWindow: true, context: "private"),
            Admission(popup: true, privateWindow: true, context: "private", live: true),
        ]
    }

    @MainActor private func admits(_ input: Admission) -> Bool {
        DownloadArrivalOwner.admits(valid: input.valid, hasPage: input.page, popupWindow: input.popup,
            privateWindow: input.privateWindow, privateContext: input.context, privateContextLive: input.live, profileKnown: input.profile)
    }

    @MainActor @Test(arguments: Admission.refused)
    func theArrivalRejectsAnInvalidPageWindowOrProfile(_ input: Admission) {
        #expect(!admits(input))
    }

    @MainActor @Test(arguments: [false, true])
    func aLiveDownloadCanArriveInItsMatchingWindow(_ privateWindow: Bool) {
        #expect(admits(.init(privateWindow: privateWindow, context: privateWindow ? "private" : nil, live: privateWindow)))
    }
}

struct DownloadArrivalControllerTests {
    @MainActor private final class Schedule: DownloadArrivalSchedule {
        override var drivesFrames: Bool { false }
        override var reduceMotion: Bool { still }
        var still = false
        var now: TimeInterval = 0
        private var timers: [(due: TimeInterval, job: @MainActor () -> Void)] = []
        private var ready: [@MainActor () -> Void] = []

        override func present(_ arrival: NSWindow, above parent: NSWindow, frame: NSRect) {
            arrival.setFrame(frame, display: false)
            arrival.level = .floating
        }

        override func after(_ delay: TimeInterval, _ job: @escaping @MainActor () -> Void) {
            timers.append((now + delay, job))
        }

        override func async(_ job: @escaping @MainActor () -> Void) { ready.append(job) }

        func advance(to end: TimeInterval, controller: DownloadArrivalController) {
            while now < end {
                let delta = min(1.0 / 60, end - now)
                now += delta
                while let earliest = timers.indices.min(by: { timers[$0].due < timers[$1].due }),
                      timers[earliest].due <= now {
                    timers.remove(at: earliest).job()
                }
                let jobs = ready
                ready.removeAll()
                jobs.forEach { $0() }
                controller.advance(delta)
            }
        }
    }

    @MainActor private struct Fixture {
        let parent: NSWindow
        let schedule = Schedule()
        let library = CGPoint(x: 24, y: 25)
        let owner: DownloadArrivalOwner

        init(still: Bool = false) {
            _ = NSApplication.shared
            parent = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: .borderless, backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            schedule.still = still
            owner = DownloadArrivalOwner(schedule: schedule)
        }

        func point(_ x: CGFloat = 600, _ y: CGFloat = 500) -> CGPoint {
            parent.convertPoint(toScreen: CGPoint(x: x, y: y))
        }

        func arrive(bin: @autoclosure () -> Bool = true, at point: CGPoint? = nil) throws -> DownloadArrivalController {
            owner.arrive(at: point ?? self.point(), in: parent, showsBin: bin(), library: library,
                         palette: ThemeChromePalette(theme: SpaceTheme(), isDark: false))
            return try #require(owner.controller)
        }
    }

    @MainActor @Test func theScreenPointConvertsIntoTheParentsFlightCoordinates() {
        let fixture = Fixture()
        #expect(DownloadArrivalController.source(screenPoint: fixture.point(), in: fixture.parent) == CGPoint(x: 615, y: 485))
    }

    @MainActor @Test func nonFinitePointerGeometryUsesTheFallbackSource() {
        let fixture = Fixture()
        #expect(DownloadArrivalController.source(screenPoint: CGPoint(x: CGFloat.nan, y: 5), in: fixture.parent) == CGPoint(x: 70, y: 70))
    }

    @MainActor @Test func theOverlayUsesTheParentFrameSpace() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        #expect(controller.window.frame == fixture.parent.frame.insetBy(dx: 1, dy: 1))
        #expect(controller.root.frame == CGRect(x: -1, y: -1, width: 1200, height: 800))
        #expect(!controller.window.isOpaque && !controller.window.hasShadow && !controller.window.canBecomeKey)
    }

    @MainActor @Test func theFlightKeyframesCarryTheWholePath() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        let first = try #require(controller.downloads.first)
        let position = try #require(first.view.content.layer?.animation(forKey: "parc.arrival.position") as? CAKeyframeAnimation)
        let transform = try #require(first.view.content.layer?.animation(forKey: "parc.arrival.transform") as? CAKeyframeAnimation)
        #expect(position.values?.count == first.flight.positions.count)
        #expect(transform.values?.count == first.flight.scales.count)
        #expect(position.duration == first.flight.duration && position.fillMode == .forwards)
        #expect(!position.isRemovedOnCompletion && position.calculationMode == .linear && position.keyTimes == nil)
    }

    @MainActor @Test func anotherArrivalReusesTheOriginalBinDecision() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        var reevaluated = false
        func chooseBin() -> Bool { reevaluated = true; return false }
        let reused = try fixture.arrive(bin: chooseBin(), at: fixture.point(900, 300))
        #expect(reused === controller)
        #expect(reused.downloads.count == 2 && !reevaluated)
    }

    @MainActor @Test func theBinFlightBeginsItsExitOnlyAfterLanding() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        let download = try #require(controller.downloads.first)
        let exit = download.flight.projectileDuration + 1
        fixture.schedule.advance(to: exit - 0.05, controller: controller)
        #expect(download.iconOffsetX == 0)
        fixture.schedule.advance(to: exit + 0.3, controller: controller)
        #expect(download.iconOffsetX < -10)
    }

    @MainActor @Test func anUnbinnedFlightRetiresTheOverlayWhenItsGroupFinishes() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive(bin: false)
        let download = try #require(controller.downloads.first)
        fixture.schedule.advance(to: download.flight.projectileDuration + 1.05, controller: controller)
        #expect(controller.retired && fixture.owner.controller == nil)
    }

    @MainActor @Test func theLastBinnedFlightRetiresOnlyAfterTheBinSlidesAway() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        let download = try #require(controller.downloads.first)
        let exit = download.flight.projectileDuration + 1
        fixture.schedule.advance(to: exit + 0.05, controller: controller)
        #expect(!controller.retired)
        fixture.schedule.advance(to: exit + 4, controller: controller)
        #expect(controller.retired && fixture.owner.controller == nil)
        #expect(controller.binPositionX == -80)
    }

    @MainActor @Test func aNonForcedDismissalLeavesAnActiveFlightAlone() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        fixture.owner.dismiss(force: false)
        #expect(fixture.owner.controller === controller && !controller.retired)
    }

    @MainActor @Test func forcedDismissalInvalidatesPendingFramesAndCallbacks() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        fixture.owner.dismiss(force: true)
        fixture.schedule.advance(to: 4, controller: controller)
        #expect(controller.retired && fixture.owner.controller == nil)
        #expect(!controller.advance(1.0 / 60))
    }

    @MainActor @Test(arguments: [false, true])
    func onlyTheOriginalParentsSecurityNotificationDismissesTheFlight(_ original: Bool) throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        let other = Fixture()
        NotificationCenter.default.post(name: Notification.Name("PCNativeWindowSecurityStateChanged"),
            object: original ? fixture.parent : other.parent)
        #expect(controller.retired == original)
    }

    @MainActor @Test(arguments: [false, true])
    func reducedMotionStartsWithoutMovingOrRotatingTheIcon(_ bin: Bool) throws {
        let fixture = Fixture(still: true)
        let controller = try fixture.arrive(bin: bin)
        let download = try #require(controller.downloads.first)
        #expect(download.view.still)
        #expect(download.view.content.layer?.animation(forKey: "parc.arrival.position") == nil)
        #expect(download.view.face.animation(forKey: "parc.arrival.rotation") == nil)
        #expect(download.view.content.layer?.position == controller.stillPosition)
    }

    @MainActor @Test func enablingReducedMotionSettlesTheFlightAtTheOwnedDestination() throws {
        let fixture = Fixture()
        let controller = try fixture.arrive()
        fixture.schedule.still = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let download = try #require(controller.downloads.first)
        #expect(controller.still && download.view.still)
        #expect(download.view.content.layer?.animation(forKey: "parc.arrival.position") == nil)
        #expect(download.view.content.layer?.position == controller.stillPosition)
    }
}
