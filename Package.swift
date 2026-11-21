// swift-tools-version: 6.2
import Foundation
import PackageDescription

let root = Context.packageDirectory
let nativeHeaders = root + "/Engine/ParcNative"

func sparkleCache() -> String {
    let script = (try? String(contentsOfFile: root + "/scripts/sparkle.py", encoding: .utf8)) ?? ""
    func value(_ name: String) -> String {
        guard let line = script.split(separator: "\n").first(where: { $0.hasPrefix(name + " = \"") }) else { return "" }
        return String(line.dropFirst(name.count + 4).dropLast())
    }
    return root + "/build/sparkle/Sparkle-\(value("VERSION"))-\(value("SHA256").prefix(12))"
}

let engineStubs = root + "/Stubs"
let sparkleFrameworks = Context.environment["PARC_SPARKLE_FRAMEWORKS"] ?? sparkleCache()

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let nativeFlags: [CSetting] = [.unsafeFlags(["-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror"])]
let facadeFlags: [CSetting] = nativeFlags + [
    .unsafeFlags(["-Wno-unused-parameter", "-Wno-incomplete-implementation", "-Wno-objc-property-implementation",
                  "-Wno-objc-protocol-property-synthesis", "-Wno-protocol", "-Wno-objc-root-class", "-Wno-nullability-completeness"]),
    .define("OS_MAC", to: "1"), .headerSearchPath("../../ParcNativeTests/Support"),
    .headerSearchPath("../../../Engine/ParcNative"), .headerSearchPath("../../../Sources/ParcEngine"),
]
let engineImport: [SwiftSetting] = [
    .unsafeFlags(["-Xcc", "-I", "-Xcc", nativeHeaders, "-Xcc", "-DOS_MAC=1", "-F", sparkleFrameworks]),
]
let frameworkRuntime = ["-Xlinker", "-rpath", "-Xlinker", sparkleFrameworks]

let package = Package(
    name: "Parc",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ParcCore", path: "Sources/ParcCore", swiftSettings: strict),
        .target(
            name: "ParcEngine",
            path: "Sources/ParcEngine",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../Engine/ParcNative"),
                .define("OS_MAC", to: "1"),
                .unsafeFlags(["-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter"]),
                .unsafeFlags(["-O2"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", engineStubs, "-Xlinker", "-weak_framework", "-Xlinker", "Chromium Embedded Framework"]),
            ]
        ),
        .executableTarget(
            name: "Parc",
            dependencies: ["ParcCore", "ParcEngine"],
            path: "Sources/ParcApp",
            swiftSettings: strict + engineImport,
            linkerSettings: [
                .unsafeFlags(["-F", sparkleFrameworks,
                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-fatal_warnings"]),
                .linkedFramework("Sparkle"),
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreSpotlight"),
            ]
        ),
        .testTarget(name: "ParcCoreTests", dependencies: ["ParcCore"], path: "tests/ParcCoreTests",
                    swiftSettings: strict),
        .target(name: "ParcNative", path: "tests/ParcNativeLibrary",
                cSettings: nativeFlags + [.unsafeFlags(["-Wno-unused-parameter"]),
                                          .headerSearchPath("../../Engine/ParcNative")],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                                 .linkedFramework("Security"), .linkedFramework("SecurityInterface")]),
        .testTarget(name: "ParcNativeTests", dependencies: ["ParcNative"], path: "tests/ParcNativeTests",
                    cSettings: nativeFlags + [.unsafeFlags(["-Wno-unused-parameter"]), .headerSearchPath("Support"), .headerSearchPath("../../Engine/ParcNative"),
                                              .headerSearchPath("../../Engine/ParcHost/native"), .headerSearchPath("../../Engine/ParcRenderer"), .headerSearchPath("../../Engine/ParcChromium"),
                                              .headerSearchPath("Media/FairPlayIdentityDoubles/include"),
                                              .headerSearchPath("../../Sources/ParcEngine")]),
        .testTarget(name: "EngineFacadeMediaTests", path: "tests/EngineFacadeTests/Media", cSettings: facadeFlags),
        .testTarget(name: "EngineFacadeImportTests", path: "tests/EngineFacadeTests/Imports",
                    cSettings: facadeFlags + [.headerSearchPath("../Shared")]),
        .testTarget(name: "EngineFacadeOldEngineTests", path: "tests/EngineFacadeTests/OldEngine",
                    cSettings: facadeFlags + [.headerSearchPath("../Shared")]),
        .plugin(
            name: "GenerateEngineStub",
            capability: .command(
                intent: .custom(verb: "generate-engine-stub",
                                description: "Regenerate the engine framework text stub from the bridge headers"),
                permissions: [.writeToPackageDirectory(reason: "Writes Stubs/Chromium Embedded Framework.framework")]
            )
        ),
        .target(name: "ParcEngineDoubles", path: "tests/ParcEngineDoubles", publicHeadersPath: "."),
        .testTarget(name: "ParcTests", dependencies: ["Parc", "ParcEngineDoubles"], path: "tests/ParcTests",
                    swiftSettings: strict + engineImport,
                    linkerSettings: [.unsafeFlags(frameworkRuntime)]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx20
)
