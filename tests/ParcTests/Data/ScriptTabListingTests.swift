import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct ScriptTabListingTests {
    private struct Model {
        let alpha = BrowserProfile(id: UUID(), name: "Alpha")
        let leaving = BrowserProfile(id: UUID(), name: "Leaving")
        let beta = BrowserProfile(id: UUID(), name: "Beta")
        let home: BrowserSpace
        let office: BrowserSpace
        let away: BrowserSpace
        let lab: BrowserSpace
        let gone = UUID()
        let distinct: BrowserState
        let twinned: BrowserState
        let blocked: Set<UUID>

        init() {
            home = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "ABCDEF", profileID: alpha.id)
            office = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "ABCDEF", profileID: alpha.id)
            away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: leaving.id)
            lab = BrowserSpace(id: UUID(), name: "Lab", symbol: "circle", color: "ABCDEF", profileID: beta.id)
            var state = BrowserState(profiles: [alpha, leaving, beta], spaces: [home, office, away, lab], activeSpaceID: home.id)
            state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: leaving.id, profileName: "Leaving",
                                                          fallbackProfileID: alpha.id)]
            let spaceIDs = [home.id, office.id, away.id, gone, lab.id]
            let (alphaID, leavingID, betaID) = (alpha.id, leaving.id, beta.id)
            state.tabs = (0..<60).map { index in
                let profile = index % 5 == 4 ? betaID : index % 7 == 0 || index % 5 == 2 ? leavingID : alphaID
                var tab = BrowserTab(id: UUID(), spaceID: spaceIDs[index % 5], profileID: profile,
                                     url: "https://model.test/\(index)", title: "Model \(index)",
                                     kind: TabKind.allCases[index % 3], folderID: nil,
                                     createdAt: Date(timeIntervalSince1970: Double(index)),
                                     lastAccessed: Date(timeIntervalSince1970: Double(index)),
                                     savedURL: "https://model.test/\(index)", savedTitle: "Model \(index)")
                if index % 6 == 5 { tab.archivedAt = Date(timeIntervalSince1970: 1_000) }
                return tab
            }
            distinct = state
            var archivedTwin = state.tabs[1]
            archivedTwin.spaceID = home.id
            archivedTwin.kind = .today
            archivedTwin.archivedAt = Date(timeIntervalSince1970: 2_000)
            var openTwin = state.tabs[16]
            openTwin.spaceID = home.id
            openTwin.kind = .today
            var profileTwin = state.tabs[31]
            profileTwin.spaceID = lab.id
            profileTwin.profileID = beta.id
            var twins = state
            twins.tabs.insert(archivedTwin, at: 0)
            twins.tabs.insert(profileTwin, at: 1)
            twins.tabs.append(openTwin)
            twinned = twins
            blocked = [state.tabs[6].id, state.tabs[26].id]
        }

        var shared: BrowserTab { distinct.tabs[1] }
        var doubled: BrowserTab { distinct.tabs[16] }
        var crossed: BrowserTab { distinct.tabs[31] }
        var spaces: [UUID] { [home.id, office.id, away.id, lab.id, gone] }
        var profiles: [UUID] { [alpha.id, leaving.id, beta.id] }

        func usable(_ tab: BrowserTab) -> Bool { !blocked.contains(tab.id) }

        func state(twins: Bool, indexed: Bool) -> BrowserState {
            let state = twins ? twinned : distinct
            return indexed ? state.attachingTabLookup(after: nil) : state
        }

        func filteredList(_ state: BrowserState) -> [BrowserTab] {
            state.tabs.filter { tab in
                tab.archivedAt == nil && !state.profileRemovals.contains { $0.profileID == tab.profileID } && usable(tab)
                    && state.spaces.contains { $0.id == tab.spaceID && $0.profileID == tab.profileID }
            }
        }

        func probeIDs(_ state: BrowserState) -> [UUID] { state.tabs.map(\.id) + [UUID(), UUID()] }
    }

    static let shapes = [(false, false), (false, true), (true, false), (true, true)]

    @Test func theModelReachesTheIndexsFoundAbsentAndRepeatedIdentityPaths() {
        let model = Model()
        let distinct = model.distinct.attachingTabLookup(after: nil)
        let twinned = model.twinned.attachingTabLookup(after: nil)

        #expect(distinct.tabLookup.lookup?.match(model.crossed.id, in: distinct.tabs) == .found(31))
        #expect(distinct.tabLookup.lookup?.match(UUID(), in: distinct.tabs) == .absent)
        #expect(twinned.tabLookup.lookup?.match(model.crossed.id, in: twinned.tabs) == .ambiguous)
    }

    @Test(arguments: shapes)
    func theWindowTabListKeepsTheFilterAndOrder(_ twins: Bool, _ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: twins, indexed: indexed)
        let listed = model.filteredList(state)

        #expect(Set(listed.map(\.profileID)) == [model.alpha.id, model.beta.id])
        #expect([model.shared.id, model.doubled.id, model.crossed.id].allSatisfy { id in listed.contains { $0.id == id } })
        #expect(state.scriptListedTabs(where: model.usable) == listed)
    }

    @Test(arguments: shapes)
    func aSingleTabLookupFindsTheListsFirstMatch(_ twins: Bool, _ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: twins, indexed: indexed)
        let listed = model.filteredList(state)

        for id in model.probeIDs(state) {
            for profile in [nil] + model.profiles.map(Optional.some) {
                #expect(state.scriptListedTab(id, profile: profile, where: model.usable)
                    == listed.first { $0.id == id && (profile == nil || $0.profileID == profile) })
            }
        }
    }

    @Test(arguments: shapes)
    func aSpaceTabListKeepsTheMembershipRuleAndOrder(_ twins: Bool, _ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: twins, indexed: indexed)
        let listed = model.filteredList(state)

        for space in model.spaces {
            for profile in model.profiles {
                let members = Set(state.tabs.filter { $0.profileID == profile && ($0.spaceID == space || $0.kind == .favorite) }.map(\.id))
                #expect(state.scriptListedTabs(inSpace: space, profile: profile, where: model.usable)
                    == listed.filter { members.contains($0.id) })
            }
        }
    }

    @Test(arguments: shapes)
    func aTabNamedInsideASpaceIsTheSpaceListsFirstMatch(_ twins: Bool, _ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: twins, indexed: indexed)

        for id in model.probeIDs(state) {
            for space in model.spaces {
                for profile in model.profiles {
                    #expect(state.scriptListedTab(id, inSpace: space, profile: profile, where: model.usable)
                        == state.scriptListedTabs(inSpace: space, profile: profile, where: model.usable).first { $0.id == id })
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func aSpaceKeepsListingTabsThatShareAnIdentityWithOneOfItsOwn(_ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: true, indexed: indexed)

        let homeTabs = state.scriptListedTabs(inSpace: model.home.id, profile: model.alpha.id, where: model.usable)

        #expect(homeTabs.contains { $0.id == model.shared.id && $0.spaceID == model.office.id })
        #expect(homeTabs.filter { $0.id == model.doubled.id }.count == 2)
    }

    @Test(arguments: [false, true])
    func aProfileBoundLookupSkipsAnEarlierTabFromAnotherProfile(_ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: true, indexed: indexed)

        #expect(state.scriptListedTab(model.crossed.id, profile: nil, where: model.usable)?.profileID == model.beta.id)
        #expect(state.scriptListedTab(model.crossed.id, profile: model.alpha.id, where: model.usable) == model.crossed)
    }

    @Test(arguments: [false, true])
    func aTabNamedInsideASpaceKeepsTheListsIdentityRuleAndAbsences(_ indexed: Bool) {
        let model = Model()
        let state = model.state(twins: true, indexed: indexed)
        let other = model.distinct.tabs[46]

        #expect(state.scriptListedTab(model.shared.id, inSpace: model.home.id, profile: model.alpha.id,
                                      where: model.usable)?.spaceID == model.office.id)
        #expect(state.scriptListedTab(model.crossed.id, inSpace: model.office.id, profile: model.alpha.id,
                                      where: model.usable)?.profileID == model.beta.id)
        #expect(state.scriptListedTab(other.id, inSpace: model.office.id, profile: model.alpha.id, where: model.usable) == other)
        #expect(state.scriptListedTab(other.id, inSpace: model.home.id, profile: model.alpha.id, where: model.usable) == nil)
    }
}
