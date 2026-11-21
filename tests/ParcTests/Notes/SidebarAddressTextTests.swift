import Foundation
import Testing
@testable import Parc

struct SidebarAddressTextTests {
    @Test func noTabShowsTheSearchPlaceholder() {
        #expect(SidebarAddressText.label(forPage: nil) == SidebarAddressText.placeholder)
    }

    @Test func aBlankTabShowsTheSearchPlaceholder() {
        #expect(SidebarAddressText.label(forPage: "") == SidebarAddressText.placeholder)
    }

    @Test(arguments: [
        ("https://www.example.org/path?q=1", "example.org"),
        ("http://localhost:8080/", "localhost"),
    ])
    func webPagesShowTheirHost(address: String, label: String) {
        #expect(SidebarAddressText.label(forPage: address) == label)
    }

    @Test(arguments: [
        ("file:///Users/me/Downloads/Report.pdf", "Report.pdf"),
        ("file:///Users/me/Documents/Parc%20Notes/My%20Plan.md", "My Plan.md"),
        ("file:///Users/me/Documents/Parc%20Notes/Plan.md#launch-day", "Plan.md"),
        ("file:///Users/me/Desktop/todo.txt", "todo.txt"),
        ("file:///Users/me/Desktop/Notes.markdown", "Notes.markdown"),
        ("file://localhost/Users/me/Plan.md", "Plan.md"),
    ])
    func localFilesShowTheirFileName(address: String, label: String) {
        #expect(SidebarAddressText.label(forPage: address) == label)
    }

    @Test func easelsStillSayEasel() {
        #expect(SidebarAddressText.label(forPage: "parc://easel/" + UUID().uuidString.lowercased()) == SidebarAddressText.easel)
    }

    @Test(arguments: [("https://www.wikipedia.org", "wikipedia.org"), ("https://web.dev", "web.dev")])
    func hostsDropWwwAndKeepOtherNames(address: String, host: String) throws {
        #expect(SidebarAddressText.host(of: try #require(URL(string: address))) == host)
    }
}
