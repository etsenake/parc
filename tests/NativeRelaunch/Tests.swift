import Foundation

@main
struct NativeRelaunchTests {
    static func main() {
        let cwd = URL(fileURLWithPath: "/tmp/parc-relaunch", isDirectory: true)
        var assertions = 0
        func check(_ args: [String], _ expected: [NativeRelaunchRequest.Destination], _ label: String) {
            let actual = NativeRelaunchRequest(arguments: args, currentDirectory: cwd).destinations
            precondition(actual == expected, "\(label): \(actual)")
            assertions += 1
        }
        let web = URL(string: "https://example.test/path?item=one#section")!
        check([], [], "missing argv")
        check(["/Applications/Parc.app/Contents/MacOS/Parc"], [], "executable not opened")
        check(["Parc", "--parc-profile", "/tmp/private-profile"], [], "profile operand not opened")
        check(["Parc", "--parc-profile=/tmp/private-profile", "--parc-diagnostics"], [], "settings not forwarded")
        check(["Parc", "--parc-profile"], [], "missing profile operand")
        check(["Parc", "--parc-open"], [], "missing destination")
        check(["Parc", "--parc-open="], [], "empty destination")
        check(["Parc", web.absoluteString], [.url(web)], "explicit launch URL")
        check(["Parc", "--parc-open", web.absoluteString], [.url(web)], "separate URL switch")
        check(["Parc", "--parc-open=" + web.absoluteString], [.url(web)], "joined URL switch")
        check(["Parc", "--parc-open", "find a local recipe"], [.input("find a local recipe")], "explicit search input")
        check(["Parc", "ignored bare words"], [], "unknown operands not searches")
        check(["Parc", "./document.html"], [.url(cwd.appendingPathComponent("document.html"))], "relative file origin")
        check(["Parc", "../document.html"], [.url(URL(fileURLWithPath: "/tmp/document.html"))], "relative parent")
        check(["Parc", "/tmp/document with spaces.html"], [.url(URL(fileURLWithPath: "/tmp/document with spaces.html"))], "file path with spaces")
        check(["Parc", "file:///tmp/document.html"], [.url(URL(string: "file:///tmp/document.html")!)], "explicit file URL")
        check(["Parc", "--", "--parc-open=https://ignored.test", web.absoluteString], [.url(web)], "end of switches")
        check(["Parc", "--parc-open", "first search", web.absoluteString], [.input("first search"), .url(web)], "destination order")
        check(["Parc", "javascript:alert(1)", "data:text/plain,ignored"], [], "positional executable schemes refused")
        check(["Parc", "--parc-profile", "/tmp/private-profile", "--parc-open", web.absoluteString], [.url(web)], "profile and actual destination separated")
        check(["Parc", "--parc-profile=/tmp/private-profile", "--parc-open=" + web.absoluteString, "./document.html"], [.url(web), .url(cwd.appendingPathComponent("document.html"))], "Chromium grouped switch representation")
        check(["Parc", "--", "/tmp/document.html"], [.url(URL(fileURLWithPath: "/tmp/document.html"))], "literal file after switch terminator")
        print("NativeRelaunch: \(assertions) assertions passed")
    }
}
