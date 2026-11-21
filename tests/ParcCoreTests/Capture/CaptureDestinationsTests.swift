import Foundation
import Testing
@testable import ParcCore

struct CaptureDestinationsTests {
    @Test func recencyUsesTheMostRecentSidebarActivityRatherThanTheEditDate() {
        let profile = UUID(), recent = UUID(), older = UUID()
        let docs = [
            EaselSummary(id: recent, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1),
            EaselSummary(id: older, title: "Travel", modifiedAt: Date(timeIntervalSince1970: 900), itemCount: 2),
        ]
        let newestActivity = Date(timeIntervalSince1970: 800)
        let destinations = CaptureEaselDestination.catalog(documents: docs, activity: [
            .init(id: recent, profileID: profile, date: newestActivity),
            .init(id: recent, profileID: profile, date: Date(timeIntervalSince1970: 100)),
            .init(id: older, profileID: profile, date: Date(timeIntervalSince1970: 400)),
        ], profileID: profile)
        #expect(CaptureEaselDestination.ranked(destinations).map(\.id) == [recent, older])
        #expect(destinations.first { $0.id == recent }?.lastActive == newestActivity)
    }

    @Test func anotherProfilesActivityDoesNotPromoteTheLocalDestination() throws {
        let profile = UUID(), otherProfile = UUID(), easel = UUID()
        let doc = EaselSummary(id: easel, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1)
        let destinations = CaptureEaselDestination.catalog(documents: [doc], activity: [
            .init(id: easel, profileID: otherProfile, date: Date(timeIntervalSince1970: 900)),
        ], profileID: profile)
        let destination = try #require(destinations.first)
        #expect(destination.id == easel && destination.lastActive == nil)
    }
}
