import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSettings

struct AppIconControllerTests {
    static let icons = ["Original", "Sorbet", "AfterHours", "RainGlass", "Recess", "Twilight",
                        "Opal", "TracingPaper", "Grapefruit", "Terminal"]

    private struct CatalogFixture {
        let directory: URL
        var preference: URL { directory.appendingPathComponent("app-icon.json") }

        init() throws {
            let fixtures = try #require(Bundle.module.resourceURL)
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let icons = directory.appendingPathComponent("AppIcons")
            try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
            do {
                let catalog: [String: Any] = ["default": "Original", "variants": Array(AppIconControllerTests.icons.reversed())]
                try JSONSerialization.data(withJSONObject: catalog).write(to: icons.appendingPathComponent("catalog.json"))
                let png = fixtures.appendingPathComponent("AppIcons/Marks/Borderless.png")
                try AppIconControllerTests.icons.forEach { id in
                    try FileManager.default.copyItem(at: png, to: artwork(id, extension: "png"))
                }
            } catch {
                remove()
                throw error
            }
        }

        func artwork(_ id: String, extension ext: String) -> URL {
            directory.appendingPathComponent("AppIcons/\(id).\(ext)")
        }

        func saveChoice(_ id: String) throws {
            try JSONSerialization.data(withJSONObject: ["version": 1, "icon": id]).write(to: preference)
        }

        func storedChoice() throws -> String? {
            let record = try JSONSerialization.jsonObject(with: Data(contentsOf: preference)) as? [String: Any]
            return record?["icon"] as? String
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }

        @MainActor func controller() -> AppIconController { AppIconController(resources: directory) }
    }

    @Test @MainActor func theCatalogKeepsTheApprovedOrderAndUsesOriginalByDefault() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let controller = fixture.controller()
        #expect(controller.availabilityError == nil)
        #expect(controller.variants.map(\.id) == Self.icons)
        #expect(controller.selectedID == "Original")
    }

    @Test @MainActor func aMissingPreferenceLeavesThePackagedIconAlone() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        fixture.controller().configure(preferenceURL: fixture.preference) { _ in
            Issue.record("Applied an icon before any choice was saved")
            return nil
        }
    }

    @Test(arguments: AppIconControllerTests.icons)
    @MainActor func everyCatalogChoiceAppliesThePickerImageAndRestores(id: String) throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let controller = fixture.controller()
        let image = try #require(controller.variants.first { $0.id == id }?.image)
        var applied: NSImage?
        controller.configure(preferenceURL: fixture.preference) { applied = $0; return nil }
        controller.select(id)
        #expect(applied === image)
        #expect(try fixture.storedChoice() == id)

        let restored = fixture.controller()
        restored.configure(preferenceURL: fixture.preference) { applied = $0; return nil }
        #expect(restored.selectedID == id)
        #expect(applied === restored.variants.first { $0.id == id }?.image)
    }

    @Test(arguments: [("Candy", "Sorbet"), ("Neon", "AfterHours"), ("FlutedGlass", "RainGlass"),
                      ("Schoolbook", "Recess"), ("Colorful", "Twilight"), ("Hologram", "Opal"),
                      ("EarlyBirds", "TracingPaper"), ("Canary", "Grapefruit"), ("Dev", "Terminal")])
    @MainActor func olderIconChoicesAreRewrittenUnderTheirCurrentNames(names: (String, String)) throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.saveChoice(names.0)
        let controller = fixture.controller()
        var applied: NSImage?
        controller.configure(preferenceURL: fixture.preference) { applied = $0; return nil }
        #expect(controller.selectedID == names.1)
        #expect(applied === controller.variants.first { $0.id == names.1 }?.image)
        #expect(try fixture.storedChoice() == names.1)
    }

    @Test @MainActor func aSavedUnknownChoiceIsKeptForTheUserToReplace() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.saveChoice("Unapproved")
        let original = try Data(contentsOf: fixture.preference)
        let controller = fixture.controller()
        controller.configure(preferenceURL: fixture.preference) { _ in
            Issue.record("Applied an unapproved icon")
            return nil
        }
        #expect(controller.message != nil)
        #expect(try Data(contentsOf: fixture.preference) == original)
    }

    @Test @MainActor func selectingAnUnknownChoiceLeavesTheCurrentIconAlone() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.saveChoice("Terminal")
        let controller = fixture.controller()
        var applications = 0
        controller.configure(preferenceURL: fixture.preference) { _ in applications += 1; return nil }
        controller.select("../../Unapproved")
        #expect(applications == 1)
        #expect(controller.selectedID == "Terminal")
        #expect(try fixture.storedChoice() == "Terminal")
    }

    @Test @MainActor func thePickerAndIdentityUseTheSameMultisizeNativeIcon() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let native = try #require(Bundle.module.url(forResource: "NativeIcon", withExtension: "icns"))
        try FileManager.default.copyItem(at: native, to: fixture.artwork("Opal", extension: "icns"))
        try Data("invalid preview".utf8).write(to: fixture.artwork("Opal", extension: "png"))
        let controller = fixture.controller()
        let variant = try #require(controller.variants.first { $0.id == "Opal" })
        #expect(Set(variant.image.representations.map(\.pixelsWide)) == [16, 32, 128, 256, 512])
        var applied: NSImage?
        controller.configure(preferenceURL: fixture.preference) { applied = $0; return nil }
        controller.select("Opal")
        #expect(applied === variant.image)
    }

    @Test @MainActor func anUnreadableNativeIconDoesNotFallBackToThePreview() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try Data("invalid icon".utf8).write(to: fixture.artwork("Original", extension: "icns"))
        let controller = fixture.controller()
        #expect(controller.availabilityError != nil)
        #expect(controller.variants.isEmpty)
        controller.configure(preferenceURL: fixture.preference) { _ in
            Issue.record("Applied an unavailable icon")
            return nil
        }
        controller.select("Original")
        #expect(!FileManager.default.fileExists(atPath: fixture.preference.path))
    }
}

struct BrandMarkTests {
    @MainActor private func load(_ style: ParcBrandMark.Style) throws -> NSImage {
        let resources = try #require(Bundle.module.resourceURL)
        return try #require(ParcBrandMark.image(style, resources: resources))
    }

    @Test(arguments: [false, true])
    @MainActor func onlyTheMonochromeMarkIsATemplate(monochrome: Bool) throws {
        let image = try load(monochrome ? .monochrome : .borderless)
        #expect(image.isTemplate == monochrome)
    }

    @Test @MainActor func aMissingBrandMarkReturnsNoImage() {
        #expect(ParcBrandMark.image(.borderless, resources: nil) == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func theMonochromeMarkUsesTheRequestedInkAndPreservesNegativeSpace(dark: Bool) throws {
        let mark = try load(.monochrome)
        let context = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        context.setFillColor((dark ? NSColor.black : NSColor.white).cgColor)
        context.fill(bounds)
        ParcBrandMark.drawMonochrome(mark, in: CGRect(x: 4, y: 2, width: 8, height: 12),
                                      color: dark ? .white : .black, context: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let outside: UInt8 = dark ? 0 : 255
        #expect(pixels[0] == outside)
        #expect((0..<256).contains { pixels[$0 * 4] != outside })
        #expect((0..<256).allSatisfy {
            let i = $0 * 4
            return pixels[i] == pixels[i + 1] && pixels[i] == pixels[i + 2] && pixels[i + 3] == 255
        })
    }
}
