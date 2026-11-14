import AppKit

enum NotePaper {
    static let color = NSColor(name: NSColor.Name("Parc.Note.Background")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
    }
}
