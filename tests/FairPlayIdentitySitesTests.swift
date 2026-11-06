import Foundation

// Pure checks for Sources/ParcCore/FairPlayIdentity.swift; no browser.
@main
struct FairPlayIdentitySitesTests {
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        normalization()
        learning()
        userChoices()
        privateWindows()
        persistence()
        print("fairplay identity sites: \(checks) checks passed")
    }

    static func normalization() {
        check(FairPlayIdentitySites.normalized(" Netflix.COM ") == "netflix.com", "trimmed and lowercased")
        check(FairPlayIdentitySites.normalized("user.github.io") == "user.github.io", "private registry site")
        check(FairPlayIdentitySites.normalized("127.0.0.1") == "127.0.0.1", "IP address site")
        check(FairPlayIdentitySites.normalized("") == nil, "empty refused")
        check(FairPlayIdentitySites.normalized(".netflix.com") == nil, "leading dot refused")
        check(FairPlayIdentitySites.normalized("netflix.com.") == nil, "trailing dot refused")
        check(FairPlayIdentitySites.normalized("net flix.com") == nil, "space refused")
        check(FairPlayIdentitySites.normalized("netflix.com/watch") == nil, "path refused")
        check(FairPlayIdentitySites.normalized(String(repeating: "a", count: 254)) == nil, "too long refused")
        let sites = FairPlayIdentitySites(safari: ["B.com", "a.com", "a.com", "bad site"], chrome: ["b.com"])
        check(sites.safari == ["a.com"], "init sorts, dedupes, drops invalid and Chrome sites")
        check(sites.chrome == ["b.com"], "Chrome list kept")
    }

    static func learning() {
        var sites = FairPlayIdentitySites()
        check(sites.identity(of: "netflix.com") == .undecided, "unknown site undecided")
        check(sites.learn("netflix.com"), "learning adds a site")
        check(sites.identity(of: "NETFLIX.com") == .safari, "learned site presents Safari")
        check(!sites.learn("netflix.com"), "learning twice changes nothing")
        check(sites.learn("apple.com") && sites.safari == ["apple.com", "netflix.com"], "kept sorted")
        check(!sites.learn("not a site"), "invalid site not learned")
    }

    static func userChoices() {
        var sites = FairPlayIdentitySites(safari: ["netflix.com"])
        check(sites.useChrome("netflix.com"), "undo moves a site to Chrome")
        check(sites.identity(of: "netflix.com") == .chrome, "Chrome choice recorded")
        check(sites.safari.isEmpty, "removed from Safari")
        check(!sites.learn("netflix.com"), "learning never overrides the user's Chrome choice")
        check(sites.identity(of: "netflix.com") == .chrome, "still Chrome after a learning attempt")
        check(!sites.useChrome("netflix.com"), "choosing Chrome twice changes nothing")
        check(sites.useSafari("netflix.com"), "reverse item moves it back")
        check(sites.identity(of: "netflix.com") == .safari && sites.chrome.isEmpty, "back to Safari")
        check(!sites.useSafari("netflix.com"), "choosing Safari twice changes nothing")
        check(sites.useChrome("spotify.com") && sites.identity(of: "spotify.com") == .chrome,
              "Chrome can be chosen for a site never learned")
    }

    static func privateWindows() {
        let profile = FairPlayIdentitySites(safari: ["netflix.com", "apple.com"], chrome: ["spotify.com"])
        var own = FairPlayIdentitySites()
        var effective = FairPlayIdentitySites.effective(profile: profile, privateChoices: own)
        check(effective == profile, "a private window starts with the Profile's lists")
        own.useChrome("netflix.com")
        own.useSafari("spotify.com")
        own.learn("tv.example")
        effective = FairPlayIdentitySites.effective(profile: profile, privateChoices: own)
        check(effective.identity(of: "netflix.com") == .chrome, "private Chrome choice wins")
        check(effective.identity(of: "spotify.com") == .safari, "private Safari choice wins")
        check(effective.identity(of: "tv.example") == .safari, "privately learned site")
        check(effective.identity(of: "apple.com") == .safari, "Profile's site still applies")
        check(profile.identity(of: "tv.example") == .undecided, "private learning never reaches the Profile")
    }

    static func persistence() {
        let sites = FairPlayIdentitySites(safari: ["netflix.com"], chrome: ["spotify.com"])
        guard let data = try? sites.encoded() else { return check(false, "encodes") }
        check(FairPlayIdentitySites.decoded(data) == sites, "round trip")
        let text = String(decoding: data, as: UTF8.self)
        check(text.contains("\"version\" : 1"), "versioned file")
        check(FairPlayIdentitySites.decoded(Data("{".utf8)) == nil, "corrupt file is not read as empty")
        let newer = Data(#"{"version":2,"safari":[],"chrome":[]}"#.utf8)
        check(FairPlayIdentitySites.decoded(newer) == nil, "newer version refused")
        check(FairPlayIdentitySites.isNewerVersion(newer), "newer version recognised, so it is kept")
        check(!FairPlayIdentitySites.isNewerVersion(Data("{".utf8)), "damaged file is not a newer version")
        check(!FairPlayIdentitySites.isNewerVersion(data), "current file is not newer")
        let messy = Data(#"{"version":1,"safari":["X.com","x.com","y.com"],"chrome":["y.com"]}"#.utf8)
        check(FairPlayIdentitySites.decoded(messy) == FairPlayIdentitySites(safari: ["x.com"], chrome: ["y.com"]),
              "decoding normalizes")
    }
}
