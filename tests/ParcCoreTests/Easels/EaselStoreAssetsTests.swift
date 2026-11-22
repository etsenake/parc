import Foundation
import Testing
@testable import ParcCore

struct EaselStoreAssetsTests {
    @MainActor @Test(arguments: [false, true])
    func aMalformedOrOversizedImageCannotBeImported(_ oversized: Bool) throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let input = oversized ? Data(repeating: 0, count: EaselStore.maximumAssetBytes + 1) : Data("not PNG".utf8)
            #expect(throws: EaselStoreError.self) { _ = try session.importPNG(input) }
        }
    }

    @MainActor @Test(arguments: [false, true])
    func legacyQuickTimeAndAv1UseTheirOwnAssetTypes(_ legacyMovie: Bool) throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let bytes: Data
            let type: EaselAssetType
            if legacyMovie {
                var legacy = Data([0, 0, 0, 0x08])
                legacy.append(contentsOf: "wide".utf8)
                legacy.append(contentsOf: [0, 0, 0, 0x10])
                legacy.append(contentsOf: "mdat".utf8)
                legacy.append(Data(count: 8))
                bytes = legacy
                type = .mov
            } else {
                var av1 = Data([0, 0, 0, 0x18])
                av1.append(contentsOf: "ftypav01".utf8)
                av1.append(Data(count: 4))
                av1.append(contentsOf: "iso8".utf8)
                av1.append(Data(count: 4))
                bytes = av1
                type = .mp4
            }
            let asset = try session.importAsset(bytes, type: type)
            #expect(asset.hasSuffix("." + type.rawValue))
        }
    }

    @MainActor @Test
    func aHeicImageCannotBeImportedAsVideo() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            var heic = Data([0, 0, 0, 0x18]); heic.append(contentsOf: Array("ftypheic".utf8)); heic.append(Data(count: 4))
            heic.append(contentsOf: Array("mif1".utf8)); heic.append(Data(count: 4))
            EaselStoreTestsSupport.expectThrows("HEIC still image as a video") { _ = try session.importAsset(heic, type: .mp4) }
        }
    }

    @MainActor @Test
    func pngImportGeneratesAnAssetID() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let id = try session.importPNG(EaselStoreTestsSupport.png)
            #expect(id.count == 40 && id.hasSuffix(".png"), "Asset name is generated, not user-supplied")
        }
    }

    @MainActor @Test(arguments: ["../outside.png", "/tmp/outside.png"])
    func assetLookupsRefuseAbsoluteAndParentPaths(_ path: String) throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            #expect(throws: EaselStoreError.self) { _ = try session.assetURL(path) }
        }
    }

    @MainActor @Test
    func aSymlinkCannotActAsAnAsset() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let id = try session.importPNG(EaselStoreTestsSupport.png)
            let asset = try session.assetURL(id)
            try FileManager.default.removeItem(at: asset)
            let outside = directory.appendingPathComponent("outside.png")
            try EaselStoreTestsSupport.png.write(to: outside)
            try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: outside)
            EaselStoreTestsSupport.expectThrows("asset symlink") { _ = try session.assetURL(id) }
            EaselStoreTestsSupport.expectThrows("document referencing symlink") { try session.perform("Image") { $0.items = [EaselItem(kind: .image, frame: EaselStoreTestsSupport.frame, assetID: id)] } }
            #expect(try! Data(contentsOf: outside) == EaselStoreTestsSupport.png, "External target was not touched")
        }
    }
}
