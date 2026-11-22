// swift-tools-version: 6.2
import Foundation
import PackageDescription

let root = Context.packageDirectory
let nativeHeaders = root + "/Engine/ParcNative"

let engineStubs = root + "/Stubs"

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let nativeFlags: [CSetting] = [.enableWarning("all"), .enableWarning("extra"), .treatAllWarnings(as: .error)]
let nativeLibraryExcludes = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
    .filter { !$0.hasPrefix(".") && $0 != "Engine" && $0 != "tests" }
let nativeLibrarySources = [
    "autofill_save_presenter.mm", "certificate_viewer_presenter.mm", "content_drop_router.mm", "devtools_pane_view.mm",
    "dialog_style.mm", "extension_install_presenter.mm", "extension_popup_presenter.mm", "extension_uninstall_presenter.mm",
    "external_protocol_presenter.mm", "find_bar_view.mm", "focus_manager.mm", "http_auth_presenter.mm",
    "javascript_dialog_presenter.mm", "page_host.mm", "pane_compositor_view.mm", "site_permission_presenter.mm",
    "status_text.mm", "window_security_reservation.mm",
]
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
        .target(name: "ParcCore", path: "Sources/ParcCore", exclude: ["README.md"], swiftSettings: strict),
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
        .target(name: "ParcKit", dependencies: ["ParcCore", "ParcEngine"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcNotes", dependencies: ["ParcCore", "ParcEngine", "ParcKit"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcEasels", dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcNotes"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcLibrary", dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcNotes", "ParcEasels"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcCommandBar", dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcNotes"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcSidebar", dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcNotes", "ParcEasels", "ParcLibrary", "ParcCommandBar"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcSettings", dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcNotes", "ParcCommandBar", "ParcSidebar"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(name: "ParcOnboarding", dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcSidebar", "ParcSettings"], exclude: ["README.md"], swiftSettings: strict + engineImport),
        .target(
            name: "Parc",
            dependencies: ["ParcCore", "ParcEngine", "ParcKit", "ParcNotes", "ParcEasels", "ParcLibrary", "ParcCommandBar", "ParcSidebar", "ParcSettings", "ParcOnboarding", .product(name: "Sparkle", package: "Sparkle")],
            exclude: ["README.md"],
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
            exclude: ["README.md"],
            swiftSettings: strict + engineImport,
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-fatal_warnings"]),
            ]
        ),
        .target(name: "ParcTestSupport", path: "tests/ParcTestSupport", exclude: ["README.md"], swiftSettings: strict),
        .testTarget(name: "ParcCoreTests", dependencies: ["ParcCore", "ParcTestSupport"], path: "tests/ParcCoreTests", exclude: ["README.md"],
                    resources: [.process("Notes/Fixtures"), .copy("Easels/Fixtures/EaselRoundTrip"), .copy("Resources/ArcSidebar")],
                    swiftSettings: strict),
        .target(name: "ParcNative", path: ".", exclude: nativeLibraryExcludes,
                sources: nativeLibrarySources.map { "Engine/ParcNative/" + $0 },
                publicHeadersPath: "tests/ParcNativeShims",
                cSettings: nativeFlags + [.disableWarning("unused-parameter"), .headerSearchPath("Engine/ParcNative")],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                                 .linkedFramework("Security"), .linkedFramework("SecurityInterface")]),
        .testTarget(name: "ParcNativeTests", dependencies: ["ParcNative"], path: "tests/ParcNativeTests",
                    exclude: ["Artwork/Borderless.png", "Artwork/Monochrome.png"],
                    resources: [.copy("Dialogs/certificate-fixture.pem"), .copy("Artwork/Monochrome.svg")],
                    cSettings: nativeFlags + [.disableWarning("unused-parameter"), .headerSearchPath("Support"), .headerSearchPath("../../Engine/ParcNative"),
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
        .testTarget(name: "ParcTests", dependencies: ["Parc", "ParcKit", "ParcNotes", "ParcEasels", "ParcLibrary", "ParcCommandBar", "ParcSidebar", "ParcSettings", "ParcOnboarding", "ParcEngineDoubles", "ParcTestSupport"], path: "tests/ParcTests", exclude: ["README.md"],
                    resources: [.copy("Notes/Fixtures"), .process("Notes/emoji.json"), .copy("Presentation/Fixtures/AppIcons"), .copy("Presentation/Fixtures/NativeIcon.icns"),
                                .copy("Presentation/Fixtures/MembershipCard"), .copy("Presentation/Fixtures/ThemeEditor"),
                                .process("Easels/Fixtures/EaselFonts"),
                                .copy("Capture/CaptureFixtures"), .copy("Capture/Library"),
                                .copy("Windows/Fixtures/NavigationControls"),
                                .copy("Windows/Fixtures/SplitViews"), .process("Windows/Fixtures/emojis.json"),
                                .copy("CommandBar/CommandBarFixtures"),
                                .copy("CommandBar/RecentSwitcher"),
                                .copy("Sidebar/Fixtures/SidebarPreview"),
                                .copy("Sidebar/ChromeFixtures"),
                                .copy("Sidebar/Fixtures/SidebarPlusMenu"),
                                .copy("Data/Fixtures/ArcSidebar"),
                                .copy("Data/Fixtures/Scripting"),
                                .copy("Data/Fixtures/SiteControlCenter"),
                                .copy("Presentation/Fixtures/ThemeTextures")],
                    swiftSettings: strict + engineImport),
    ] + (siteFilmScenes.isEmpty ? [] : [
        .target(
            name: "SiteFilmMedia",
            dependencies: ["ParcEngine"],
            path: "scripts/site-film/mini-card/Media",
            cSettings: nativeFlags + [.headerSearchPath("../../../../Engine/ParcNative")]
        ),
    ]) + siteFilmScenes.map { scene in
        let dependencies: [Target.Dependency] = ["Parc", "ParcCore", "ParcKit", "ParcNotes", "ParcEasels", "ParcLibrary",
                                                   "ParcCommandBar", "ParcSidebar", "ParcSettings", "ParcOnboarding",
                                                   "ParcEngineDoubles"]
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
