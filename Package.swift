// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let nativeFlags: [CSetting] = [.unsafeFlags(["-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror"])]
let facadeFlags: [CSetting] = nativeFlags + [
    .unsafeFlags(["-Wno-unused-parameter", "-Wno-incomplete-implementation", "-Wno-objc-property-implementation",
                  "-Wno-objc-protocol-property-synthesis", "-Wno-protocol", "-Wno-objc-root-class", "-Wno-nullability-completeness"]),
    .define("OS_MAC", to: "1"), .headerSearchPath("../../ParcNativeTests/Support"),
    .headerSearchPath("../../../Engine/ParcNative"), .headerSearchPath("../../../Sources/ParcEngine"),
]

let package = Package(
    name: "Parc",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ParcCore", path: "Sources/ParcCore", swiftSettings: strict),
        .testTarget(name: "ParcCoreTests", dependencies: ["ParcCore"], path: "tests/ParcCoreTests",
                    swiftSettings: strict),
        .target(name: "ParcNative", path: "tests/ParcNativeLibrary",
                cSettings: nativeFlags + [.unsafeFlags(["-Wno-unused-parameter"]),
                                          .headerSearchPath("../../Engine/ParcNative")],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                                 .linkedFramework("Security"), .linkedFramework("SecurityInterface")]),
        .testTarget(name: "ParcNativeTests", dependencies: ["ParcNative"], path: "tests/ParcNativeTests",
                    cSettings: nativeFlags + [.unsafeFlags(["-Wno-unused-parameter"]), .headerSearchPath("Support"), .headerSearchPath("../../Engine/ParcNative"),
                                              .headerSearchPath("../../Engine/ParcHost/native"), .headerSearchPath("../../Engine/ParcRenderer"),
                                              .headerSearchPath("../../Sources/ParcEngine")]),
        .testTarget(name: "EngineFacadeMediaTests", path: "tests/EngineFacadeTests/Media", cSettings: facadeFlags),
        .testTarget(name: "EngineFacadeImportTests", path: "tests/EngineFacadeTests/Imports",
                    cSettings: facadeFlags + [.headerSearchPath("../Shared")]),
        .testTarget(name: "EngineFacadeOldEngineTests", path: "tests/EngineFacadeTests/OldEngine",
                    cSettings: facadeFlags + [.headerSearchPath("../Shared")]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx20
)
