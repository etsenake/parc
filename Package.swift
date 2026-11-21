// swift-tools-version: 6.2
import Foundation
import PackageDescription

let root = Context.packageDirectory
let nativeHeaders = root + "/Engine/ParcNative"

let engineStubs = root + "/Stubs"

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let nativeFlags: [CSetting] = [.enableWarning("all"), .enableWarning("extra"), .treatAllWarnings(as: .error)]
let presentationFlags: [CSetting] = [.unsafeFlags(["-include", root + "/tests/ParcNativeTests/Support/ParcNativePresentation.h"])]
let facadeFlags: [CSetting] = nativeFlags + [
    .disableWarning("unused-parameter"), .disableWarning("incomplete-implementation"),
    .disableWarning("objc-property-implementation"), .disableWarning("objc-protocol-property-synthesis"),
    .disableWarning("protocol"), .disableWarning("objc-root-class"), .disableWarning("nullability-completeness"),
    .define("OS_MAC", to: "1"), .headerSearchPath("../../ParcNativeTests/Support"),
    .headerSearchPath("../../../Engine/ParcNative"), .headerSearchPath("../../../Sources/ParcEngine"),
]
let engineImport: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I", "-Xcc", nativeHeaders])]

let package = Package(
    name: "Parc",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Parc", targets: ["ParcMain"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "ParcCore", path: "Sources/ParcCore", swiftSettings: strict),
        .target(
            name: "ParcEngine",
            path: "Sources/ParcEngine",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../Engine/ParcNative"),
                .define("OS_MAC", to: "1"),
                .enableWarning("all"), .enableWarning("extra"), .treatAllWarnings(as: .error),
                .disableWarning("unused-parameter"),
                .unsafeFlags(["-O2"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", engineStubs, "-Xlinker", "-weak_framework", "-Xlinker", "Chromium Embedded Framework"]),
            ]
        ),
        .target(
            name: "Parc",
            dependencies: ["ParcCore", "ParcEngine", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ParcApp",
            swiftSettings: strict + engineImport,
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreSpotlight"),
            ]
        ),
        .executableTarget(
            name: "ParcMain",
            dependencies: ["Parc", "ParcEngine"],
            path: "Sources/ParcMain",
            swiftSettings: strict + engineImport,
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-fatal_warnings"]),
            ]
        ),
        .testTarget(name: "ParcCoreTests", dependencies: ["ParcCore"], path: "tests/ParcCoreTests",
                    swiftSettings: strict),
        .target(name: "ParcNative", path: "tests/ParcNativeLibrary",
                cSettings: presentationFlags + nativeFlags + [.disableWarning("unused-parameter"),
                                          .headerSearchPath("../../Engine/ParcNative")],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                                 .linkedFramework("Security"), .linkedFramework("SecurityInterface")]),
        .testTarget(name: "ParcNativeTests", dependencies: ["ParcNative"], path: "tests/ParcNativeTests",
                    exclude: ["Artwork/Borderless.png", "Artwork/Monochrome.png"],
                    resources: [.copy("Dialogs/certificate-fixture.pem"), .copy("Artwork/Monochrome.svg")],
                    cSettings: presentationFlags + nativeFlags + [.disableWarning("unused-parameter"), .headerSearchPath("Support"), .headerSearchPath("../../Engine/ParcNative"),
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
                    swiftSettings: strict + engineImport),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx20
)
