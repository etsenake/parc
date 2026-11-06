import Foundation

/// A second-process command is data for the existing shell, not a second set
/// of engine/profile settings. Only launch destinations cross this boundary.
struct NativeRelaunchRequest {
    enum Destination: Equatable { case url(URL), input(String) }
    let destinations: [Destination]

    init(arguments: [String], currentDirectory: URL) {
        var result: [Destination] = []
        var index = 1 // argv[0] is the executable, never a document.
        var positionalOnly = false
        while index < arguments.count {
            let value = arguments[index]
            index += 1
            if !positionalOnly {
                if value == "--" { positionalOnly = true; continue }
                if value == "--parc-profile" { if index < arguments.count { index += 1 }; continue }
                if value.hasPrefix("--parc-profile=") { continue }
                if value == "--parc-open" {
                    if index < arguments.count {
                        let input = arguments[index]; index += 1
                        if !input.isEmpty { result.append(Self.destination(input, currentDirectory: currentDirectory)) }
                    }
                    continue
                }
                if value.hasPrefix("--parc-open=") {
                    let input = String(value.dropFirst("--parc-open=".count))
                    if !input.isEmpty { result.append(Self.destination(input, currentDirectory: currentDirectory)) }
                    continue
                }
                if value.hasPrefix("-") { continue }
            }
            // Positional launch arguments must be explicit URLs or file paths.
            // Chromium switch operands and ordinary words are not search input.
            if let url = Self.explicitURL(value, currentDirectory: currentDirectory) {
                result.append(.url(url))
            }
        }
        destinations = result
    }

    private static func destination(_ value: String, currentDirectory: URL) -> Destination {
        if let url = explicitURL(value, currentDirectory: currentDirectory) { return .url(url) }
        return .input(value) // Explicit --parc-open preserves the existing command-bar parser.
    }

    private static func explicitURL(_ value: String, currentDirectory: URL) -> URL? {
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           ["https", "http", "file"].contains(scheme) { return url }
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return URL(fileURLWithPath: value, relativeTo: currentDirectory).standardizedFileURL
        }
        return nil
    }
}
