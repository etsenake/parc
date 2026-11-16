import Foundation

@main
struct SitePermissionRowTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func row(_ title: String, allowed: Bool, systemSettings: Bool? = nil, pip: Bool = false,
                 index: Int = 0) -> [String: Any] {
            var row: [String: Any] = ["title": title, "key": "\(index) https://www.bestbuy.com",
                                      "index": NSNumber(value: index), "revision": NSNumber(value: UInt(4)),
                                      "allowed": NSNumber(value: allowed), "changeable": NSNumber(value: true),
                                      "autoPictureInPicture": NSNumber(value: pip)]
            if let systemSettings { row["systemSettings"] = NSNumber(value: systemSettings) }
            return row
        }

        let allowed = SitePermissionRow(row("Location", allowed: true, systemSettings: false))
        expect(allowed?.subtitle == "Allowed" && allowed?.systemSettings == false,
               "an allowed site with macOS location on or still undecided reads Allowed")
        expect(allowed?.id == "permission:0 https://www.bestbuy.com" && allowed?.index == 0
               && allowed?.revision == 4 && allowed?.changeable == true, "the engine's target survives parsing")

        let off = SitePermissionRow(row("Location", allowed: true, systemSettings: true))
        expect(off?.systemSettings == true && off?.subtitle == "Off in macOS",
               "an allowed site with location off for Parc in macOS says so instead of Allowed")
        expect(off?.accessibilityValue.contains("System Settings") == true,
               "VoiceOver hears that the site is allowed but macOS has location off")

        let blocked = SitePermissionRow(row("Location", allowed: false, systemSettings: true))
        expect(blocked?.systemSettings == false && blocked?.subtitle == "Blocked",
               "a blocked site stays Blocked with no System Settings button")

        let older = SitePermissionRow(row("Location", allowed: true))
        expect(older?.systemSettings == false && older?.subtitle == "Allowed",
               "an engine without the system state keeps the old wording")

        expect(SitePermissionRow(["title": "Location"]) == nil, "rows without an engine target are ignored")

        let ordered = SitePermissionRow.ordered([row("Location", allowed: true, index: 0),
                                                 row("Automatic picture-in-picture", allowed: true, pip: true, index: -2)])
        expect(ordered.map(\.title) == ["Automatic picture-in-picture", "Location"],
               "automatic picture-in-picture stays first")

        print("SitePermissionRow checks passed: \(checks)")
    }
}
