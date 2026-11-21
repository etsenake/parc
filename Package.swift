// swift-tools-version: 6.2
import Foundation
import PackageDescription

let root = Context.packageDirectory
let nativeHeaders = root + "/Engine/ParcNative"

let engineStubs = root + "/Stubs"

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let nativeFlags: [CSetting] = [.enableWarning("all"), .enableWarning("extra"), .treatAllWarnings(as: .error)]
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
                    resources: [.copy("Easels/Fixtures/EaselRoundTrip")],
                    swiftSettings: strict),
        .target(name: "ParcNative", path: "Engine/ParcNative",
                sources: ["autofill_save_presenter.mm", "certificate_viewer_presenter.mm", "content_drop_router.mm",
                          "devtools_pane_view.mm", "dialog_style.mm", "extension_install_presenter.mm",
                          "extension_popup_presenter.mm", "extension_uninstall_presenter.mm",
                          "external_protocol_presenter.mm", "find_bar_view.mm", "focus_manager.mm",
                          "http_auth_presenter.mm", "javascript_dialog_presenter.mm", "page_host.mm",
                          "pane_compositor_view.mm", "site_permission_presenter.mm", "status_text.mm",
                          "window_security_reservation.mm"],
                publicHeadersPath: "fairplay_chromium/testdata",
                cSettings: nativeFlags + [.disableWarning("unused-parameter"),
                                          .headerSearchPath("../../tests/ParcNativeTests/Headers/Chromium")],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                                 .linkedFramework("Security"), .linkedFramework("SecurityInterface")]),
        .testTarget(name: "ParcNativeTests", dependencies: ["ParcNative"], path: "tests/ParcNativeTests",
                    exclude: ["Headers"],
                    cSettings: nativeFlags + [.disableWarning("unused-parameter"), .headerSearchPath("Support"), .headerSearchPath("../../Engine/ParcNative"),
                                              .headerSearchPath("../../Engine/ParcHost/native"), .headerSearchPath("../../Engine/ParcRenderer"),
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
                    resources: [.copy("Easels/Fixtures/EaselFonts")],
                    swiftSettings: strict + engineImport),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx20
)
