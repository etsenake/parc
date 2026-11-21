import Foundation
import Testing
@testable import Parc

struct SitePermissionRowTests {
    struct Permission: Sendable, CustomTestStringConvertible {
        let name: String
        let help: String
        var testDescription: String { name }
    }

    static let permissions = [
        Permission(name: "location", help: "Location is off"),
        Permission(name: "camera", help: "Camera is off"),
        Permission(name: "microphone", help: "Microphone is off"),
        Permission(name: "notifications", help: "Notifications are off"),
        Permission(name: "clipboard", help: "Pasting from other apps is off"),
    ]

    private static func row(_ title: String, allowed: Bool, systemSettings: Bool? = nil, systemPermission: String? = nil,
                            pip: Bool = false, index: Int = 0) -> [String: Any] {
        var row: [String: Any] = ["title": title, "key": "\(index) https://www.bestbuy.com",
                                  "index": NSNumber(value: index), "revision": NSNumber(value: UInt(4)),
                                  "allowed": NSNumber(value: allowed), "changeable": NSNumber(value: true),
                                  "autoPictureInPicture": NSNumber(value: pip)]
        if let systemSettings { row["systemSettings"] = NSNumber(value: systemSettings) }
        if let systemPermission { row["systemPermission"] = systemPermission }
        return row
    }

    @Test func anAllowedSiteWithMacOSLocationOnOrUndecidedReadsAllowed() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: true, systemSettings: false)))
        #expect(parsed.subtitle == "Allowed")
        #expect(!parsed.systemSettings)
    }

    @Test func theEnginesTargetSurvivesParsing() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: true, systemSettings: false)))
        #expect(parsed.id == "permission:0 https://www.bestbuy.com")
        #expect(parsed.index == 0)
        #expect(parsed.revision == 4)
        #expect(parsed.changeable)
    }

    @Test func anAllowedSiteWithLocationOffInMacOSSaysSo() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: true, systemSettings: true)))
        #expect(parsed.systemSettings)
        #expect(parsed.subtitle == "Off in macOS")
    }

    @Test func voiceOverHearsThatMacOSHasThePermissionOff() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: true, systemSettings: true)))
        #expect(parsed.accessibilityValue.contains("System Settings"))
    }

    @Test func anEngineNamingNoSystemPermissionIsDescribingLocation() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: true, systemSettings: true)))
        #expect(parsed.systemSettingsHelp.hasPrefix("Location is off for Parc in macOS"))
    }

    @Test(arguments: permissions)
    func anAllowedRowWithMacOSBlockingParcReadsOffInMacOS(permission: Permission) throws {
        let parsed = try #require(SitePermissionRow(Self.row(permission.name.capitalized, allowed: true,
                                                             systemSettings: true, systemPermission: permission.name)))
        #expect(parsed.subtitle == "Off in macOS")
        #expect(parsed.systemPermission == permission.name)
    }

    @Test(arguments: permissions)
    func theSettingsButtonExplainsWhichPermissionIsOff(permission: Permission) throws {
        let parsed = try #require(SitePermissionRow(Self.row(permission.name.capitalized, allowed: true,
                                                             systemSettings: true, systemPermission: permission.name)))
        #expect(parsed.systemSettingsHelp == permission.help + " for Parc in macOS. Open System Settings to turn it on.")
    }

    @Test(arguments: permissions)
    func anAllowedRowWithMacOSAllowingParcReadsAllowed(permission: Permission) throws {
        let parsed = try #require(SitePermissionRow(Self.row(permission.name.capitalized, allowed: true,
                                                             systemSettings: false, systemPermission: permission.name)))
        #expect(parsed.subtitle == "Allowed")
    }

    @Test(arguments: permissions)
    func aBlockedRowStaysBlockedWhileMacOSBlocksParc(permission: Permission) throws {
        let parsed = try #require(SitePermissionRow(Self.row(permission.name.capitalized, allowed: false,
                                                             systemSettings: true, systemPermission: permission.name)))
        #expect(!parsed.systemSettings)
        #expect(parsed.subtitle == "Blocked")
    }

    @Test func aBlockedSiteStaysBlockedWithNoSystemSettingsButton() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: false, systemSettings: true)))
        #expect(!parsed.systemSettings)
        #expect(parsed.subtitle == "Blocked")
    }

    @Test func anEngineWithoutTheSystemStateKeepsTheOldWording() throws {
        let parsed = try #require(SitePermissionRow(Self.row("Location", allowed: true)))
        #expect(!parsed.systemSettings)
        #expect(parsed.subtitle == "Allowed")
    }

    @Test func rowsWithoutAnEngineTargetAreIgnored() {
        #expect(SitePermissionRow(["title": "Location"]) == nil)
    }

    @Test func automaticPictureInPictureStaysFirst() {
        let ordered = SitePermissionRow.ordered([Self.row("Location", allowed: true, index: 0),
                                                 Self.row("Automatic picture-in-picture", allowed: true, pip: true, index: -2)])
        #expect(ordered.map(\.title) == ["Automatic picture-in-picture", "Location"])
    }
}
