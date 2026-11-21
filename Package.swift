// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let nativeFlags: [CSetting] = [.unsafeFlags(["-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror"])]

let package = Package(
    name: "Parc",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ParcCore", path: "Sources/ParcCore", swiftSettings: strict),
        .testTarget(name: "ParcCoreTests", dependencies: ["ParcCore"], path: "tests/ParcCoreTests",
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
                cSettings: nativeFlags + [.unsafeFlags(["-Wno-unused-parameter"]),
                                          .headerSearchPath("../../tests/ParcNativeTests/Headers/Chromium")],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"),
                                 .linkedFramework("Security"), .linkedFramework("SecurityInterface")]),
        .testTarget(name: "ParcNativeTests", dependencies: ["ParcNative"], path: "tests/ParcNativeTests",
                    exclude: ["Headers"],
                    cSettings: nativeFlags + [.unsafeFlags(["-Wno-unused-parameter"]), .headerSearchPath("Support"), .headerSearchPath("../../Engine/ParcNative"),
                                              .headerSearchPath("../../Engine/ParcHost/native"), .headerSearchPath("../../Engine/ParcRenderer"),
                                              .headerSearchPath("../../Sources/ParcEngine")]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx20
)
