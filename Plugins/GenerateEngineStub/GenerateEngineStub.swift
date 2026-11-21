import Foundation
import PackagePlugin

@main
struct GenerateEngineStub: CommandPlugin {
    enum Failure: Error, CustomStringConvertible {
        case tool([String], String)
        case noHeaders(String)

        var description: String {
            switch self {
            case .tool(let arguments, let output): "xcrun \(arguments.joined(separator: " ")) failed:\n\(output)"
            case .noHeaders(let directory): "No engine headers are reached from \(directory)"
            }
        }
    }

    static let engineName = "Chromium Embedded Framework"
    static let target = "arm64-apple-macos13.0"

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let root = context.package.directoryURL
        let native = root.appending(path: "Engine/ParcNative").resolvingSymlinksInPath()
        let facade = root.appending(path: "Sources/ParcEngine")
        let work = context.pluginWorkDirectoryURL
        let stub = root.appending(path: "Stubs/\(Self.engineName).framework/\(Self.engineName).tbd")
        let files = FileManager.default.enumerator(at: facade, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        let includes = [native] + Set(files.filter { $0.pathExtension == "h" }.map { $0.deletingLastPathComponent() })
            .sorted { $0.path < $1.path }
        var headers = Set<String>()
        for source in files.filter({ $0.pathExtension == "m" }).sorted(by: { $0.path < $1.path }) {
            let dependencies = try run(["clang", "-target", Self.target, "-x", "objective-c", "-fobjc-arc", "-fblocks",
                                        "-DOS_MAC=1"] + includes.flatMap { ["-I", $0.path] } + ["-M", source.path],
                                       work: work)
            for token in dependencies.replacingOccurrences(of: "\\\n", with: " ").split(whereSeparator: \.isWhitespace)
            where token.hasSuffix(".h") {
                let header = URL(filePath: String(token)).resolvingSymlinksInPath().path
                if header.hasPrefix(native.path + "/") { headers.insert(header) }
            }
        }
        guard !headers.isEmpty else { throw Failure.noHeaders(facade.path) }
        let framework = work.appending(path: "\(Self.engineName).framework")
        try? FileManager.default.removeItem(at: framework)
        try FileManager.default.createDirectory(at: framework.appending(path: "Headers"), withIntermediateDirectories: true)
        let generated = work.appending(path: "stub.tbd")
        let sdk = try run(["--sdk", "macosx", "--show-sdk-path"], work: work).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try run(["tapi", "installapi", "-target", Self.target, "-isysroot", sdk, "-x", "objective-c", "-fobjc-arc",
                     "-DOS_MAC=1", "-I", native.path,
                     "-install_name", "@executable_path/../Frameworks/\(Self.engineName).framework/\(Self.engineName)"]
                    + headers.sorted().flatMap { ["-extra-public-header", $0] }
                    + ["-o", generated.path, framework.path], work: work)
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: generated))
        var text = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        text.append(0x0A)
        try FileManager.default.createDirectory(at: stub.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: stub)
        let doubles = root.appending(path: "tests/ParcEngineDoubles/EngineDoubles.m")
        try FileManager.default.createDirectory(at: doubles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(try doubleSource(classes: exportedClasses(value), headers: headers.sorted()).utf8).write(to: doubles)
        print("Wrote \(stub.path) and \(doubles.path) from \(headers.count) engine headers")
    }

    func exportedClasses(_ stub: Any) -> [String] {
        guard let library = (stub as? [String: Any])?["main_library"] as? [String: Any],
              let exports = library["exported_symbols"] as? [[String: Any]] else { return [] }
        return exports.flatMap { (($0["data"] as? [String: Any])?["objc_class"] as? [String]) ?? [] }.sorted()
    }

    func doubleSource(classes: [String], headers: [String]) throws -> String {
        let declaration = try Regex(#"@interface\s+(\w+)\s*:\s*(\w+)"#)
        var superclasses: [String: String] = [:]
        for header in headers {
            for match in try String(contentsOfFile: header, encoding: .utf8).matches(of: declaration) {
                guard let name = match.output[1].substring, let parent = match.output[2].substring else { continue }
                superclasses[String(name)] = superclasses[String(name)] ?? String(parent)
            }
        }
        var ordered: [String] = []
        func visit(_ name: String) {
            guard classes.contains(name), !ordered.contains(name) else { return }
            if let parent = superclasses[name] { visit(parent) }
            ordered.append(name)
        }
        classes.forEach(visit)
        let body = ordered.map { name in
            "@interface \(name) : \(superclasses[name] ?? "NSObject")\n@end\n\n@implementation \(name)\n@end\n"
        }
        return "#import <AppKit/AppKit.h>\n\n" + body.joined(separator: "\n")
    }

    func run(_ arguments: [String], work: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = arguments
        let errors = work.appending(path: "tool-errors.txt")
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = try FileHandle(forWritingTo: errors)
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.tool(arguments, (try? String(contentsOf: errors, encoding: .utf8)) ?? "")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
