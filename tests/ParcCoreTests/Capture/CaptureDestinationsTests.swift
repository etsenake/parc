import Foundation
import Testing
@testable import ParcCore

struct CaptureDestinationsTests {
    @Test func lastActivityWinsOverDocumentEditsAndAnotherProfileNeverContributesRecency() {
        let profile = UUID(), otherProfile = UUID()
        let first = UUID(), second = UUID(), inactive = UUID()
        let summaries = [
            EaselSummary(id: first, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1),
            EaselSummary(id: second, title: "Travel", modifiedAt: Date(timeIntervalSince1970: 900), itemCount: 2),
            EaselSummary(id: inactive, title: "Research", modifiedAt: Date(timeIntervalSince1970: 999), itemCount: 0),
        ]
        let destinations = CaptureEaselDestination.catalog(documents: summaries, activity: [
            .init(id: first, profileID: profile, date: Date(timeIntervalSince1970: 800)),
            .init(id: first, profileID: profile, date: Date(timeIntervalSince1970: 100)),
            .init(id: second, profileID: profile, date: Date(timeIntervalSince1970: 400)),
            .init(id: inactive, profileID: otherProfile, date: Date(timeIntervalSince1970: 2000)),
        ], profileID: profile)
        #expect(CaptureEaselDestination.ranked(destinations).map(\.id) == [first, second, inactive])
    }
}
