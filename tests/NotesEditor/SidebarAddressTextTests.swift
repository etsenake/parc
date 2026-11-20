import Foundation

@main
struct SidebarAddressTextTests {
    static func main() {
        exitOnFailure {
            let label = SidebarAddressText.label(forPage:)
            let placeholder = SidebarAddressText.placeholder
            expect(label(nil) == placeholder, "no tab shows the search placeholder")
            expect(label("") == placeholder, "a blank tab shows the search placeholder")
            expect(label("https://www.example.org/path?q=1") == "example.org", "web pages show their host without www")
            expect(label("http://localhost:8080/") == "localhost", "local servers show their host")
            expect(label("file:///Users/me/Downloads/Report.pdf") == "Report.pdf", "other local files show their file name")
            expect(label("file:///Users/me/Documents/Parc%20Notes/My%20Plan.md") == "My Plan.md", "notes show their file name")
            expect(label("file:///Users/me/Documents/Parc%20Notes/Plan.md#launch-day") == "Plan.md",
                       "a note's heading anchor stays out of the pill")
            expect(label("file:///Users/me/Desktop/todo.txt") == "todo.txt", "text notes keep their extension")
            expect(label("file:///Users/me/Desktop/Notes.markdown") == "Notes.markdown", "longer Markdown extensions stay visible")
            expect(label("file://localhost/Users/me/Plan.md") == "Plan.md", "localhost file addresses are notes too")
            expect(label("parc://easel/" + UUID().uuidString.lowercased()) == SidebarAddressText.easel, "Easels still say Easel")
            expect(SidebarAddressText.host(of: URL(string: "https://www.wikipedia.org")!) == "wikipedia.org", "www is trimmed")
            expect(SidebarAddressText.host(of: URL(string: "https://web.dev")!) == "web.dev", "other hosts stay whole")
            print("SidebarAddressTextTests passed")
        }
    }

    static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition { failTest(message, file: file, line: line) }
    }
}
