import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTestsPresentation {
    private typealias Skip = PageLoadingPresentationSkip

    @MainActor @Test func theFirstFingerprintNeverSkips() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        #expect(Skip.shouldSkip(previous: nil, next: empty) == false)
    }

    @MainActor @Test func anIdenticalEmptyThirdSettledPresentationSkips() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        #expect(Skip.shouldSkip(previous: empty, next: empty))
    }

    @MainActor @Test func strokeGrowthMustPresent() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        let growing = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0.5), barOpacity: 0.92, hidden: false)
        #expect(Skip.shouldSkip(previous: empty, next: growing) == false)
    }

    @MainActor @Test func aLoadingPulseChangeMustPresent() {
        let a = PageLoadingIndicator.presentation(pulse: 0.40, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        let b = PageLoadingIndicator.presentation(pulse: 0.41, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        #expect(Skip.shouldSkip(previous: a, next: b) == false)
    }

    struct FillPhase: CustomTestStringConvertible {
        let label: String
        let pulse: Double
        let sweeping: Bool
        let barOpacity: Float
        let fillOpacity: CGFloat

        var testDescription: String { label }
    }

    @Test(arguments: [
        FillPhase(label: "Pulsing", pulse: 0.40, sweeping: false, barOpacity: 0, fillOpacity: 0.368),
        FillPhase(label: "Sweeping through the empty third", pulse: 1, sweeping: true, barOpacity: 0.92, fillOpacity: 0.276),
    ]) @MainActor
    func theFillOpacityMatchesItsPhase(_ sample: FillPhase) {
        let presentation = PageLoadingIndicator.presentation(pulse: sample.pulse, sweeping: sample.sweeping,
                                                             stroke: (0, 0), barOpacity: sample.barOpacity, hidden: false)
        #expect(NavigationLoadingTestsSupport.near(CGFloat(presentation.fillOpacity), sample.fillOpacity))
    }

    struct TrackPhase: CustomTestStringConvertible {
        let label: String
        let sweeping: Bool
        let width: CGFloat

        var testDescription: String { label }
    }

    @Test(arguments: [
        TrackPhase(label: "Pulsing", sweeping: false, width: 48),
        TrackPhase(label: "Sweeping", sweeping: true, width: 128),
    ]) @MainActor
    func theTrackSizeMatchesItsPhase(_ sample: TrackPhase) {
        #expect(PageLoadingIndicator.trackSize(sweeping: sample.sweeping) == CGSize(width: sample.width, height: 4))
    }
}
