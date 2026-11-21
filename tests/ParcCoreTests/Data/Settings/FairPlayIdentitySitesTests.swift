import Foundation
import Testing
@testable import ParcCore

struct FairPlayIdentitySitesTests {
    @Test(arguments: [
        (" Netflix.COM ", "netflix.com"),
        ("user.github.io", "user.github.io"),
        ("127.0.0.1", "127.0.0.1"),
        ("a~b!c$d&e+f,g;h=i.example", "a~b!c$d&e+f,g;h=i.example"),
        ("[::1]", "[::1]"),
        ("A%2A.example", "a%2a.example"),
    ])
    func validHostsAreNormalized(host: String, expected: String) {
        #expect(FairPlayIdentitySites.normalized(host) == expected)
    }

    @Test(arguments: ["", ".netflix.com", "netflix.com.", "net flix.com", "netflix.com/watch", "café.example",
                      String(repeating: "a", count: 254)])
    func invalidHostsAreRefused(host: String) {
        #expect(FairPlayIdentitySites.normalized(host) == nil)
    }

    @Test func initSortsDedupesAndDropsInvalidAndChromeSites() {
        let sites = FairPlayIdentitySites(safari: ["B.com", "a.com", "a.com", "bad site"], chrome: ["b.com"])
        #expect(sites.safari == ["a.com"])
        #expect(sites.chrome == ["b.com"])
    }

    @Test func anUnknownSiteIsUndecided() {
        #expect(FairPlayIdentitySites().identity(of: "netflix.com") == .undecided)
    }

    @Test func learningAddsASiteThatThenPresentsSafari() {
        var sites = FairPlayIdentitySites()
        let changed1 = sites.learn("netflix.com")
        #expect(changed1)
        #expect(sites.identity(of: "NETFLIX.com") == .safari)
        let changed2 = sites.learn("netflix.com")
        #expect(!changed2)
    }

    @Test func learnedSitesAreKeptSortedAndInvalidOnesAreNotLearned() {
        var sites = FairPlayIdentitySites()
        _ = sites.learn("netflix.com")
        let changed3 = sites.learn("apple.com")
        #expect(changed3 && sites.safari == ["apple.com", "netflix.com"])
        let changed4 = sites.learn("not a site")
        #expect(!changed4)
    }

    @Test func choosingChromeMovesASiteAndLearningNeverOverridesIt() {
        var sites = FairPlayIdentitySites(safari: ["netflix.com"])
        let changed5 = sites.useChrome("netflix.com")
        #expect(changed5)
        #expect(sites.identity(of: "netflix.com") == .chrome)
        #expect(sites.safari.isEmpty)
        let changed6 = sites.learn("netflix.com")
        #expect(!changed6)
        #expect(sites.identity(of: "netflix.com") == .chrome)
        let changed7 = sites.useChrome("netflix.com")
        #expect(!changed7)
    }

    @Test func choosingSafariMovesASiteBack() {
        var sites = FairPlayIdentitySites(chrome: ["netflix.com"])
        let changed8 = sites.useSafari("netflix.com")
        #expect(changed8)
        #expect(sites.identity(of: "netflix.com") == .safari && sites.chrome.isEmpty)
        let changed9 = sites.useSafari("netflix.com")
        #expect(!changed9)
    }

    @Test func chromeCanBeChosenForASiteNeverLearned() {
        var sites = FairPlayIdentitySites()
        let changed10 = sites.useChrome("spotify.com")
        #expect(changed10 && sites.identity(of: "spotify.com") == .chrome)
    }

    @Test func aPrivateWindowStartsWithTheProfilesLists() {
        let profile = FairPlayIdentitySites(safari: ["netflix.com", "apple.com"], chrome: ["spotify.com"])
        #expect(FairPlayIdentitySites.effective(profile: profile, privateChoices: FairPlayIdentitySites()) == profile)
    }

    @Test func privateChoicesWinAndPrivateLearningNeverReachesTheProfile() {
        let profile = FairPlayIdentitySites(safari: ["netflix.com", "apple.com"], chrome: ["spotify.com"])
        var own = FairPlayIdentitySites()
        own.useChrome("netflix.com")
        own.useSafari("spotify.com")
        own.learn("tv.example")
        let effective = FairPlayIdentitySites.effective(profile: profile, privateChoices: own)
        #expect(effective.identity(of: "netflix.com") == .chrome)
        #expect(effective.identity(of: "spotify.com") == .safari)
        #expect(effective.identity(of: "tv.example") == .safari)
        #expect(effective.identity(of: "apple.com") == .safari)
        #expect(profile.identity(of: "tv.example") == .undecided)
    }

    @Test func theFileRoundTripsAndIsVersioned() throws {
        let sites = FairPlayIdentitySites(safari: ["netflix.com"], chrome: ["spotify.com"])
        let data = try sites.encoded()
        #expect(FairPlayIdentitySites.decoded(data) == sites)
        #expect(String(decoding: data, as: UTF8.self).contains("\"version\" : 1"))
    }

    @Test func aCorruptFileIsNotReadAsEmpty() {
        #expect(FairPlayIdentitySites.decoded(Data("{".utf8)) == nil)
        #expect(!FairPlayIdentitySites.isNewerVersion(Data("{".utf8)))
    }

    @Test func aNewerVersionIsRefusedButRecognisedSoItIsKept() {
        let newer = Data(#"{"version":2,"safari":[],"chrome":[]}"#.utf8)
        #expect(FairPlayIdentitySites.decoded(newer) == nil)
        #expect(FairPlayIdentitySites.isNewerVersion(newer))
    }

    @Test func theCurrentFileIsNotNewer() throws {
        #expect(try !FairPlayIdentitySites.isNewerVersion(FairPlayIdentitySites(safari: ["netflix.com"]).encoded()))
    }

    @Test func decodingNormalizes() {
        let messy = Data(#"{"version":1,"safari":["X.com","x.com","y.com"],"chrome":["y.com"]}"#.utf8)
        #expect(FairPlayIdentitySites.decoded(messy) == FairPlayIdentitySites(safari: ["x.com"], chrome: ["y.com"]))
    }
}
