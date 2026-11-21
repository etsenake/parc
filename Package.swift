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
let siteFilmScenes = Context.environment["PARC_SITE_FILM"] == "1" ? [
    "base", "spaces", "collapse", "crank", "peek", "preview", "split",
    "commandbar-easel", "notes", "capture-archive", "mini-card", "startpage",
] : []

let package = Package(
    name: "Parc",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Parc", targets: ["ParcMain"])] + siteFilmScenes.map { scene in
        .executable(name: "parc-film-\(scene)", targets: ["parc-film-\(scene)"])
    },
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
                    resources: [.copy("Notes/Fixtures"), .copy("Easels/Fixtures/EaselRoundTrip"), .copy("Resources/ArcSidebar")],
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
        .target(name: "ParcEngineDoubles", path: "tests/ParcEngineDoubles", publicHeadersPath: ".",
                cSettings: [.headerSearchPath("../../Engine/ParcNative"), .headerSearchPath("../../Sources/ParcEngine")]),
        .testTarget(name: "ParcTests", dependencies: ["Parc", "ParcEngineDoubles"], path: "tests/ParcTests",
                    resources: [.copy("Notes/Fixtures"), .copy("Presentation/Fixtures/AppIcons"), .copy("Presentation/Fixtures/NativeIcon.icns"),
                                .copy("Presentation/Fixtures/MembershipCard"), .copy("Presentation/Fixtures/ThemeEditor"),
                                .copy("Easels/Fixtures/EaselFonts"),
                                .copy("Capture/CaptureFixtures"),
                                .copy("Windows/Fixtures/NavigationControls"),
                                .copy("CommandBar/CommandBarFixtures"),
                                .copy("Sidebar/Fixtures/SidebarPreview"),
                                .copy("Sidebar/ChromeFixtures"),
                                .copy("Sidebar/Fixtures/SidebarPlusMenu")],
                    swiftSettings: strict + engineImport),
    ] + (siteFilmScenes.isEmpty ? [] : [
        .target(
            name: "SiteFilmMedia",
            dependencies: ["ParcEngine"],
            path: "scripts/site-film/mini-card/Media",
            cSettings: nativeFlags + [.headerSearchPath("../../../../Engine/ParcNative")]
        ),
    ]) + siteFilmScenes.map { scene in
        let dependencies: [Target.Dependency] = ["Parc", "ParcCore", "ParcEngineDoubles"]
        return .executableTarget(
            name: "parc-film-\(scene)",
            dependencies: scene == "mini-card" ? dependencies + ["SiteFilmMedia"] : dependencies,
            path: "scripts/site-film/\(scene)/Harness",
            swiftSettings: strict + engineImport,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-fatal_warnings"])]
        )
    },
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx20
)
