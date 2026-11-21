import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteLinkFollowingTests {
    let web = URL(string: "https://example.com/page")!

    @Test func clicks() throws {
        #expect(NoteLinkClick(shift: false, command: false, option: false, control: false) == .plain, "no keys is a plain click")
        #expect(NoteLinkClick(shift: true, command: false, option: false, control: false) == .shift, "Shift alone is a Shift-click")
        #expect(NoteLinkClick(shift: false, command: true, option: false, control: false) == .modified, "Command keeps its own route")
        #expect(NoteLinkClick(shift: true, command: true, option: false, control: false) == .modified, "Shift-Command keeps its own route")
        #expect(NoteLinkClick(shift: true, command: false, option: true, control: false) == .modified, "Shift-Option keeps its own route")
        #expect(NoteLinkClick(shift: false, command: false, option: false, control: true) == .modified, "Control keeps its own route")
    }

    @Test func settings() throws {
        #expect(NoteLinkClick.plain.route(for: web, automaticPeek: true, shiftPeek: false) == .peek, "every web link in a note is a link to another site")
        #expect(NoteLinkClick.plain.route(for: web, automaticPeek: false, shiftPeek: true) == .usual, "a plain click opens as before when links to other sites don't peek")
        #expect(NoteLinkClick.shift.route(for: web, automaticPeek: false, shiftPeek: true) == .peek, "Shift-click peeks whenever its trigger is on")
        #expect(NoteLinkClick.shift.route(for: web, automaticPeek: true, shiftPeek: false) == .usual, "Shift-click opens as before when its trigger is off")
        for click in NoteLinkClick.allCases {
            #expect(click.route(for: web, automaticPeek: false, shiftPeek: false) == .usual, "both triggers off keep today's behaviour")
        }
        #expect(NoteLinkClick.modified.route(for: web, automaticPeek: true, shiftPeek: true) == .usual, "other modifier clicks never peek")
    }

    @Test func schemes() throws {
        #expect(NoteLinkClick.plain.route(for: URL(string: "HTTP://example.com")!, automaticPeek: true, shiftPeek: true) == .peek, "schemes match case-insensitively")
        for raw in ["mailto:someone@example.com", "file:///tmp/a.md", "parc://notes", "ftp://example.com", "https:relative"] {
            for click in NoteLinkClick.allCases {
                #expect(click.route(for: URL(string: raw)!, automaticPeek: true, shiftPeek: true) == .usual, "\(raw) never opens in a Peek")
            }
        }
    }
}
