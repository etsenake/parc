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

let engineFrameworks = Context.environment["PARC_ENGINE_FRAMEWORKS"]
    ?? "/Volumes/Parc/chromium/src/out/ParcDistribution_GN_arm64"
let sparkleFrameworks = Context.environment["PARC_SPARKLE_FRAMEWORKS"] ?? sparkleCache()

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let engineImport: [SwiftSetting] = [
    .unsafeFlags(["-Xcc", "-I", "-Xcc", nativeHeaders, "-Xcc", "-DOS_MAC=1", "-F", sparkleFrameworks]),
]
let frameworkRuntime = ["-Xlinker", "-rpath", "-Xlinker", engineFrameworks,
                        "-Xlinker", "-rpath", "-Xlinker", sparkleFrameworks]

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
                .unsafeFlags(["-F", engineFrameworks]),
                .linkedFramework("Chromium Embedded Framework"),
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
        .testTarget(name: "ParcTests", dependencies: ["Parc"], path: "tests/ParcTests",
                    swiftSettings: strict + engineImport,
                    linkerSettings: [.unsafeFlags(frameworkRuntime)]),
    ],
    swiftLanguageModes: [.v5]
)
