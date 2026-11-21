import Foundation
import Testing
@testable import ParcCore

struct NativeRelaunchTests {
    typealias Destination = NativeRelaunchRequest.Destination

    static let cwd = URL(fileURLWithPath: "/tmp/parc-relaunch", isDirectory: true)
    static let web = URL(string: "https://example.test/path?item=one#section")!

    func destinations(_ arguments: [String]) -> [Destination] {
        NativeRelaunchRequest(arguments: arguments, currentDirectory: Self.cwd).destinations
    }

    @Test(arguments: [
        [],
        ["/Applications/Parc.app/Contents/MacOS/Parc"],
        ["Parc", "--parc-profile", "/tmp/private-profile"],
        ["Parc", "--parc-profile=/tmp/private-profile", "--parc-diagnostics"],
        ["Parc", "--parc-profile"],
        ["Parc", "--parc-open"],
        ["Parc", "--parc-open="],
        ["Parc", "ignored bare words"],
        ["Parc", "javascript:alert(1)", "data:text/plain,ignored"],
    ])
    func argumentsWithoutADestinationOpenNothing(_ arguments: [String]) {
        #expect(destinations(arguments).isEmpty)
    }

    @Test(arguments: [
        ["Parc", web.absoluteString],
        ["Parc", "--parc-open", web.absoluteString],
        ["Parc", "--parc-open=" + web.absoluteString],
        ["Parc", "--", "--parc-open=https://ignored.test", web.absoluteString],
        ["Parc", "--parc-profile", "/tmp/private-profile", "--parc-open", web.absoluteString],
    ])
    func aWebAddressOpensOnce(_ arguments: [String]) {
        #expect(destinations(arguments) == [.url(Self.web)])
    }

    @Test func anExplicitSearchStaysInput() {
        #expect(destinations(["Parc", "--parc-open", "find a local recipe"]) == [.input("find a local recipe")])
    }

    @Test func filePathsResolveAgainstTheLaunchFolder() {
        #expect(destinations(["Parc", "./document.html"]) == [.url(Self.cwd.appendingPathComponent("document.html"))])
        #expect(destinations(["Parc", "../document.html"]) == [.url(URL(fileURLWithPath: "/tmp/document.html"))])
        #expect(destinations(["Parc", "/tmp/document with spaces.html"])
                == [.url(URL(fileURLWithPath: "/tmp/document with spaces.html"))])
        #expect(destinations(["Parc", "file:///tmp/document.html"]) == [.url(URL(string: "file:///tmp/document.html")!)])
        #expect(destinations(["Parc", "--", "/tmp/document.html"]) == [.url(URL(fileURLWithPath: "/tmp/document.html"))])
    }

    @Test func destinationsKeepTheirOrder() {
        #expect(destinations(["Parc", "--parc-open", "first search", Self.web.absoluteString])
                == [.input("first search"), .url(Self.web)])
        #expect(destinations(["Parc", "--parc-profile=/tmp/private-profile", "--parc-open=" + Self.web.absoluteString,
                              "./document.html"])
                == [.url(Self.web), .url(Self.cwd.appendingPathComponent("document.html"))])
    }
}
