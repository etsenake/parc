import Foundation
import Testing
@testable import ParcCore

struct ICloudPasswordsHelperTests {
    typealias Signer = ICloudPasswordsSupport.Signer

    static let passkeys = "com.apple.developer.web-browser.public-key-credential"

    static func release(_ major: Int, _ minor: Int, _ patch: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    static func der(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        [tag] + (body.count < 0x80 ? [UInt8(body.count)] : [0x82, UInt8(body.count >> 8), UInt8(body.count & 0xff)]) + body
    }

    static func text(_ value: String) -> [UInt8] { der(0x0c, Array(value.utf8)) }
    static func pair(_ key: String, _ value: [UInt8]) -> [UInt8] { der(0x30, text(key) + value) }
    static func dictionary(_ pairs: [UInt8]...) -> [UInt8] { der(0xb0, pairs.flatMap { $0 }) }
    static func array(_ items: [UInt8]...) -> [UInt8] { der(0x30, items.flatMap { $0 }) }
    static let one = der(0x02, [1])
    static let five = der(0x02, [5])
    static let yes = der(0x01, [0xff])

    static func constraint(_ requirements: [UInt8]) -> Data {
        Data(der(0x70, one + dictionary(pair("ccat", der(0x02, [0])), pair("comp", one),
                                        pair("reqs", requirements), pair("vers", one))))
    }

    static let allowList = constraint(dictionary(pair("$or-array", array(
        pair("$and", dictionary(pair("entitlements", dictionary(pair("$query",
            array(array(one, text(passkeys)), array(five, yes))))))),
        pair("$and", dictionary(
            pair("signing-identifier", dictionary(pair("$in", array(text("com.google.Chrome"), text("com.google.Chrome.beta"))))),
            pair("team-identifier", text("EQHXZ8M8AV"))))))))

    static func be(_ value: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) } }
    static func le(_ value: Int) -> [UInt8] { [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: value >> $0) } }

    static func program(_ parent: Data?, overrun: Int = 0) -> [UInt8] {
        var slots: [(Int, [UInt8])] = [(2, be(0xfade0c01) + be(12) + be(0))]
        if let parent { slots.append((9, be(0xfade8181) + be(8 + parent.count + overrun) + [UInt8](parent))) }
        let header = 12 + slots.count * 8
        var index: [UInt8] = [], blobs: [UInt8] = []
        for (slot, blob) in slots { index += be(slot) + be(header + blobs.count); blobs += blob }
        let signature = be(0xfade0cc0) + be(header + blobs.count) + be(slots.count) + index + blobs
        return le(0xfeedfacf) + le(0x0100000c) + le(0) + le(2) + le(2) + le(40) + le(0) + le(0)
            + le(0x2) + le(24) + [UInt8](repeating: 0, count: 16)
            + le(0x1d) + le(16) + le(72) + le(signature.count) + signature
    }

    static func universal(_ slice: [UInt8]) -> Data {
        Data(be(0xcafebabe) + be(1) + be(0x0100000c) + be(0) + be(64) + be(slice.count) + be(14)
             + [UInt8](repeating: 0, count: 36) + slice)
    }

    static func universal64(_ slice: [UInt8]) -> Data {
        Data(be(0xcafebabf) + be(1) + be(0x0100000c) + be(0) + be(0) + be(64) + be(0) + be(slice.count) + be(14) + be(0)
             + [UInt8](repeating: 0, count: 24) + slice)
    }

    static func connects(_ helper: ICloudPasswordsSupport.Helper?,
                         as signer: Signer = Signer(identifier: "com.etsenake.parc", team: "PARCTEAM01"),
                         on version: OperatingSystemVersion) -> Bool {
        ICloudPasswordsSupport.connects(helper: helper, signer: signer, on: version)
    }

    @Test func theParentLaunchConstraintIsReadFromTheCodeSignatureInThinAndUniversalFiles() {
        let allowList = Self.allowList
        #expect(ICloudPasswordsSupport.parentConstraint(in: Data(Self.program(allowList))) == .restricted(allowList))
        #expect(ICloudPasswordsSupport.parentConstraint(in: Self.universal(Self.program(allowList))) == .restricted(allowList))
        #expect(ICloudPasswordsSupport.parentConstraint(in: Self.universal(Self.program(nil))) == .unrestricted)
    }

    @Test func sixtyFourBitUniversalFilesAreReadToo() {
        let allowList = Self.allowList
        #expect(ICloudPasswordsSupport.parentConstraint(in: Self.universal64(Self.program(allowList))) == .restricted(allowList))
    }

    @Test func aFileThatIsNotAWholeSignedProgramCannotBeInspected() {
        let allowList = Self.allowList
        #expect(ICloudPasswordsSupport.parentConstraint(in: Data("#!/bin/sh".utf8)) == nil)
        #expect(ICloudPasswordsSupport.parentConstraint(in: Self.universal(Array(Self.program(allowList).prefix(80)))) == nil)
        #expect(ICloudPasswordsSupport.parentConstraint(in: Self.universal(Self.program(allowList, overrun: 4096))) == nil)
    }

    @Test func theHelperChromiumsManifestNamesComesFirstThenItsUsualPlace() throws {
        let allowList = Self.allowList
        let scratch = try PresentationScratch("parc-icloud-helper")
        defer { scratch.remove() }
        let folder = scratch.url.appendingPathComponent("helper", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let restricted = folder.appendingPathComponent("restricted"), open = folder.appendingPathComponent("open")
        try Self.universal(Self.program(allowList)).write(to: restricted)
        try Self.universal(Self.program(nil)).write(to: open)
        let manifest = folder.appendingPathComponent("com.apple.passwordmanager.json")
        try JSONSerialization.data(withJSONObject: ["name": "com.apple.passwordmanager", "path": restricted.path]).write(to: manifest)
        let missing = folder.appendingPathComponent("missing")
        let stale = folder.appendingPathComponent("stale.json")
        try JSONSerialization.data(withJSONObject: ["path": missing.path]).write(to: stale)
        #expect(ICloudPasswordsSupport.installedHelper(manifest: manifest, fallback: open) == .restricted(allowList))
        #expect(ICloudPasswordsSupport.installedHelper(manifest: missing, fallback: open) == .unrestricted)
        #expect(ICloudPasswordsSupport.installedHelper(manifest: stale, fallback: restricted) == .restricted(allowList))
        #expect(ICloudPasswordsSupport.installedHelper(manifest: missing, fallback: missing) == nil)
    }

    @Test func anUpdatedSafariOnMacOS14OrEarly15AlreadyShipsTheAllowListSoSetupStopsOfferingTheExtension() {
        let allowList = Self.allowList
        #expect(!Self.connects(.restricted(allowList), on: Self.release(14, 6)))
        #expect(!Self.connects(.restricted(allowList), on: Self.release(15, 3)))
    }

    @Test func aHelperWithoutTheAllowListKeepsTheExtensionFromMacOS14On() {
        #expect(Self.connects(.unrestricted, on: Self.release(14, 6)))
        #expect(Self.connects(.unrestricted, on: Self.release(15, 6)))
        #expect(!Self.connects(.unrestricted, on: Self.release(13, 6)))
    }

    @Test func aListedSigningIdentifierConnectsOnlyWithItsListedTeam() {
        let allowList = Self.allowList
        let version = Self.release(27, 2)
        #expect(Self.connects(.restricted(allowList), as: Signer(identifier: "com.google.Chrome", team: "EQHXZ8M8AV"), on: version))
        #expect(!Self.connects(.restricted(allowList), as: Signer(identifier: "com.google.Chrome", team: "PARCTEAM01"), on: version))
        #expect(!Self.connects(.restricted(allowList), as: Signer(), on: version))
    }

    @Test func applesPasskeyBrowserEntitlementAdmitsABrowserOffTheList() {
        let allowList = Self.allowList
        let version = Self.release(27, 2)
        #expect(Self.connects(.restricted(allowList), as: Signer(entitlements: [Self.passkeys: true]), on: version))
        #expect(!Self.connects(.restricted(allowList), as: Signer(entitlements: [Self.passkeys: false]), on: version))
    }

    @Test func aMatchingAlternativeDecidesEvenBesideOneParcCannotEvaluate() {
        let unknown = Self.constraint(Self.dictionary(Self.pair("$or", Self.dictionary(
            Self.pair("on-system-volume", Self.yes), Self.pair("signing-identifier", Self.text("com.google.Chrome"))))))
        #expect(Self.connects(.restricted(unknown), as: Signer(identifier: "com.google.Chrome"), on: Self.release(27, 2)))
    }

    @Test func aConstraintParcCannotEvaluateFallsBackToTheMacOSRule() {
        let unknown = Self.constraint(Self.dictionary(Self.pair("$or", Self.dictionary(
            Self.pair("on-system-volume", Self.yes), Self.pair("signing-identifier", Self.text("com.google.Chrome"))))))
        #expect(Self.connects(.restricted(unknown), on: Self.release(15, 4, 1)))
        #expect(!Self.connects(.restricted(unknown), on: Self.release(15, 5)))
        #expect(Self.connects(.restricted(Data([0x70, 0x01])), on: Self.release(14, 0)))
        #expect(!Self.connects(.restricted(Data([0x70, 0x01])), on: Self.release(26, 1)))
    }

    @Test func withoutAnInspectableHelperICloudPasswordsIsOfferedOnlyFromMacOS14Through15Point4() {
        #expect(!Self.connects(nil, on: Self.release(13, 6)))
        #expect(Self.connects(nil, on: Self.release(14, 0)))
        #expect(Self.connects(nil, on: Self.release(15, 4, 1)))
        let later = [Self.release(15, 5), Self.release(15, 7, 2), Self.release(16, 0), Self.release(26, 1), Self.release(27, 2, 1)]
        #expect(later.allSatisfy { !Self.connects(nil, on: $0) })
    }
}
