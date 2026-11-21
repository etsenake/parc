import Foundation

@main @MainActor
struct NoteLinkFollowingTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { failTest(message) }
    }

    static let web = URL(string: "https://example.com/page")!

    static func main() {
        exitOnFailure {
            try clicks()
            try settings()
            try schemes()
            print("NoteLinkFollowing: \(assertions) assertions passed")
        }
    }

    static func clicks() throws {
        try expect(NoteLinkClick(shift: false, command: false, option: false, control: false) == .plain, "no keys is a plain click")
        try expect(NoteLinkClick(shift: true, command: false, option: false, control: false) == .shift, "Shift alone is a Shift-click")
        try expect(NoteLinkClick(shift: false, command: true, option: false, control: false) == .modified, "Command keeps its own route")
        try expect(NoteLinkClick(shift: true, command: true, option: false, control: false) == .modified, "Shift-Command keeps its own route")
        try expect(NoteLinkClick(shift: true, command: false, option: true, control: false) == .modified, "Shift-Option keeps its own route")
        try expect(NoteLinkClick(shift: false, command: false, option: false, control: true) == .modified, "Control keeps its own route")
    }

    static func settings() throws {
        try expect(NoteLinkClick.plain.route(for: web, automaticPeek: true, shiftPeek: false) == .peek,
                   "every web link in a note is a link to another site")
        try expect(NoteLinkClick.plain.route(for: web, automaticPeek: false, shiftPeek: true) == .usual,
                   "a plain click opens as before when links to other sites don't peek")
        try expect(NoteLinkClick.shift.route(for: web, automaticPeek: false, shiftPeek: true) == .peek,
                   "Shift-click peeks whenever its trigger is on")
        try expect(NoteLinkClick.shift.route(for: web, automaticPeek: true, shiftPeek: false) == .usual,
                   "Shift-click opens as before when its trigger is off")
        for click in NoteLinkClick.allCases {
            try expect(click.route(for: web, automaticPeek: false, shiftPeek: false) == .usual,
                       "both triggers off keep today's behaviour")
        }
        try expect(NoteLinkClick.modified.route(for: web, automaticPeek: true, shiftPeek: true) == .usual,
                   "other modifier clicks never peek")
    }

    static func schemes() throws {
        try expect(NoteLinkClick.plain.route(for: URL(string: "HTTP://example.com")!, automaticPeek: true, shiftPeek: true) == .peek,
                   "schemes match case-insensitively")
        for raw in ["mailto:someone@example.com", "file:///tmp/a.md", "parc://notes", "ftp://example.com", "https:relative"] {
            for click in NoteLinkClick.allCases {
                try expect(click.route(for: URL(string: raw)!, automaticPeek: true, shiftPeek: true) == .usual,
                           "\(raw) never opens in a Peek")
            }
        }
    }
}
