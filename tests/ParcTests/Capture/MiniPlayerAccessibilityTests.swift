import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

extension MiniPlayerTestsSupport {
    struct MiniPlayerAccessibilityTests {
        @MainActor private func checkName(_ button: ActionButton, name: String, help: String) {
            #expect(button.accessibilityLabel() == name)
            #expect(button.cell?.accessibilityLabel() == name)
            #expect(button.image?.accessibilityDescription == name)
            #expect(button.parcTooltip?.label == help)
            #expect(button.toolTip == nil && button.accessibilityHelp() == help)
        }

        struct MediaLabel: Sendable {
            let active: Bool
            let name: String
            let help: String

            static let samples: [Self] = [
                .init(active: false, name: "Pause", help: "Pause"),
                .init(active: false, name: "Turn Camera On", help: "Toggle Camera"),
                .init(active: false, name: "Unmute Microphone", help: "Toggle Microphone"),
                .init(active: false, name: "Mute Tab", help: "Mute Tab"),
                .init(active: true, name: "Play", help: "Play"),
                .init(active: true, name: "Turn Camera Off", help: "Toggle Camera"),
                .init(active: true, name: "Mute Microphone", help: "Toggle Microphone"),
                .init(active: true, name: "Unmute Tab", help: "Unmute Tab"),
            ]
        }

        @MainActor @Test(arguments: [false, true])
        func theDeckControlExposesItsExpansionState(_ expanded: Bool) throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            if expanded { try fixture.toggleExpansion() }
            let title = expanded ? "Collapse Mini Players" : "Show All Mini Players (2)"
            let button = try fixture.button(title)
            checkName(button, name: title, help: title)
            #expect(button.isAccessibilityExpanded() == expanded)
            #expect(button.cell?.isAccessibilityExpanded() == expanded)
        }

        @MainActor @Test(arguments: MediaLabel.samples)
        func theTransportNamesTheActionAvailableNow(_ sample: MediaLabel) throws {
            let fixture = try MiniPlayerFixture(["episode"])
            let engine = fixture.engine("episode")
            engine.canToggleCamera = true
            engine.canToggleMicrophone = true
            engine.playing = !sample.active
            engine.cameraOn = sample.active
            engine.microphoneOn = sample.active
            engine.muted = sample.active
            try fixture.update(["episode"])
            fixture.deck.updateHover(true)
            fixture.layout()
            checkName(try fixture.button(sample.name), name: sample.name, help: sample.help)
        }

        @MainActor @Test(arguments: [0, 1, 2])
        func theVolumeButtonAndCellReportTheirExpansion(_ toggles: Int) throws {
            let fixture = try MiniPlayerFixture(["episode"])
            fixture.deck.updateHover(true)
            for _ in 0..<toggles { try fixture.toggleVolume(in: "episode") }
            let button = try fixture.button("Adjust Tab Volume")
            #expect(button.isAccessibilityExpanded() == (toggles == 1))
            #expect(button.cell?.isAccessibilityExpanded() == (toggles == 1))
        }

        struct RetiredEpisode: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let multiple: Bool
            let expanded: Bool

            static let cases: [Self] = [
                .init(testDescription: "One collapsed episode", multiple: false, expanded: false),
                .init(testDescription: "One expanded episode", multiple: false, expanded: true),
                .init(testDescription: "Two expanded episodes", multiple: true, expanded: true),
            ]
        }

        @MainActor @Test(arguments: RetiredEpisode.cases)
        func aRetiredEpisodeExposesAnUnavailableMessage(_ sample: RetiredEpisode) throws {
            let fixture = try MiniPlayerFixture(sample.multiple ? ["episode", "other"] : ["episode"])
            if sample.expanded { fixture.deck.updateHover(true); fixture.layout() }
            let pause = try fixture.button("Pause", in: fixture.row("episode"))
            fixture.engine("episode").available = false
            pause.actionBlock?()
            fixture.layout()
            let error = fixture.descendants(fixture.deck).compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "This media is no longer available." }
            #expect(error?.isHiddenOrHasHiddenAncestor == false)
        }

        @MainActor @Test func anUnavailableActionExpandsTheCollapsedDeck() throws {
            let fixture = try MiniPlayerFixture(["episode", "other"])
            fixture.engine("episode").available = false
            try fixture.button("Pause", in: fixture.row("episode")).actionBlock?()
            fixture.layout()
            #expect(try fixture.button("Collapse Mini Players").isAccessibilityExpanded())
        }
    }
}
