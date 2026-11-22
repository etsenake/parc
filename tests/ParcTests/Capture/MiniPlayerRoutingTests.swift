import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

extension MiniPlayerTestsSupport {
    struct MiniPlayerRoutingTests {
        @MainActor @Test(arguments: ["cast", "airplay"])
        func theRouteButtonUsesItsOwnChooser(_ route: String) throws {
            let fixture = try MiniPlayerFixture(["a"])
            let engine = fixture.engine("a")
            if route == "cast" { engine.castState = Int(PCNativeCastState.available.rawValue) }
            else { engine.airPlayState = Int(PCNativeAirPlayState.available.rawValue) }
            try fixture.update(["a"])
            let button = try fixture.button(route == "cast" ? "Cast" : "AirPlay", visible: true)
            button.actionBlock?()
            #expect(engine.chooserRequests == [route])
            #expect(button.showsSelectedFill)
        }

        @MainActor @Test func dismissingTheChooserReleasesTheSelectedRouteButton() throws {
            let fixture = try MiniPlayerFixture(["a"])
            let engine = fixture.engine("a")
            engine.castState = Int(PCNativeCastState.available.rawValue)
            try fixture.update(["a"])
            let button = try fixture.button("Cast")
            button.actionBlock?()
            engine.dismissChooser()
            #expect(!button.showsSelectedFill)
        }

        struct CastStatus: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let connected: Bool
            let label: String

            static let cases: [Self] = [
                .init(testDescription: "Connecting", connected: false, label: "Connecting to Living Room TV"),
                .init(testDescription: "Connected", connected: true, label: "Casting to Living Room TV"),
            ]
        }

        @MainActor @Test(arguments: CastStatus.cases)
        func anActiveCastNamesItsReceiver(_ sample: CastStatus) throws {
            let fixture = try MiniPlayerFixture(["a"])
            let engine = fixture.engine("a")
            engine.castState = Int((sample.connected ? PCNativeCastState.connected : .connecting).rawValue)
            engine.castDeviceName = "Living Room TV"
            try fixture.update(["a"])
            let button = try fixture.button(sample.label, visible: true)
            if sample.connected { #expect(button.accessibilityValue() as? String == "Connected") }
        }

        @MainActor @Test func aRefusedActionDoesNotShowAnUnavailableMessageForActiveMedia() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.engine("a").refusesActions = true
            try fixture.button("Pause").actionBlock?()
            #expect(!fixture.descendants(fixture.deck).contains { view in
                (view as? NSTextField)?.stringValue == "This media is no longer available." && !view.isHidden
            })
        }

        @MainActor @Test func theUnavailableMessageClearsWhenTheEpisodeReturns() throws {
            let fixture = try MiniPlayerFixture(["a"])
            let engine = fixture.engine("a"), pause = try fixture.button("Pause")
            engine.available = false
            pause.actionBlock?()
            engine.available = true
            try fixture.update(["a"])
            #expect(!fixture.descendants(fixture.deck).contains { view in
                (view as? NSTextField)?.stringValue == "This media is no longer available." && !view.isHidden
            })
        }
    }
}
