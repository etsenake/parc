import Foundation
import Testing
@testable import ParcCore

struct EaselToolKeyboardTests {
    func command(_ characters: String?, _ keyCode: UInt16, _ modifiers: EaselKeyModifiers = []) -> EaselKeyCommand? {
        EaselKeyCommands.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    let ansi: [Character: UInt16] = [
        "v": 9, "h": 4, "m": 46, "s": 1, "r": 15, "o": 31, "t": 17, "l": 37, "x": 7, "w": 13, "e": 14,
        "`": 50, "[": 33, "]": 30, "=": 24, "+": 24, "-": 27, "_": 27,

    ]

    private struct KeyCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let characters: String?
        let code: UInt16
        let modifiers: EaselKeyModifiers
        let expected: EaselKeyCommand?

        init(_ label: String, _ characters: String?, _ code: UInt16, _ modifiers: EaselKeyModifiers, _ expected: EaselKeyCommand?) {
            testDescription = label
            self.characters = characters
            self.code = code
            self.modifiers = modifiers
            self.expected = expected
        }
    }

    @Test
    func eachKeyIsBoundOnce() {
        let keys = EaselKeyCommands.bindings.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test(arguments: EaselKeyCommands.bindings.map(\.key))
    func eachKeyRunsItsBoundCommand(_ key: EaselKey) throws {
        let binding = try #require(EaselKeyCommands.bindings.first { $0.key == key })
        let flags: EaselKeyModifiers = binding.key.shift ? [.shift] : []
        switch binding.key.base {
        case .character(let character):
            let code = try #require(ansi[character], "Missing physical key for \(binding.key.label)")
            let typed = binding.key.shift ? String(character).uppercased() : String(character)
            #expect(command(typed, code, flags) == binding.command, "\(binding.key.label) runs its command")
        case .physical(let code, _):
            #expect(command(nil, code, flags) == binding.command, "\(binding.key.label) runs its command by position")
        }
    }

    private struct ToolKeys: Sendable, CustomTestStringConvertible {
        let tool: EaselTool
        let labels: [String]
        var testDescription: String { String(describing: tool) }

        init(_ tool: EaselTool, _ labels: [String]) {
            self.tool = tool
            self.labels = labels
        }
    }

    @Test(arguments: [
        ToolKeys(.select, ["V"]),
        ToolKeys(.hand, ["H"]),
        ToolKeys(.marker, ["M"]),
        ToolKeys(.highlighter, ["⇧M"]),
        ToolKeys(.washi, ["W"]),
        ToolKeys(.eraser, ["⇧⌫", "⇧⌦"]),
        ToolKeys(.sticky, ["S"]),
        ToolKeys(.section, ["⇧S"]),
        ToolKeys(.table, ["⇧T"]),
        ToolKeys(.rectangle, ["R"]),
        ToolKeys(.ellipse, ["O"]),
        ToolKeys(.text, ["T"]),
        ToolKeys(.straightConnector, ["L"]),
        ToolKeys(.elbowConnector, ["X", "⇧L"]),
        ToolKeys(.curvedConnector, []),
        ToolKeys(.stamp, ["E"]),
        ToolKeys(.codeBlock, ["`", "⇧`"]),
    ])
    private func toolsExposeTheirShortcutLabels(_ testCase: ToolKeys) {
        let labels = Dictionary(EaselTool.allCases.map { ($0, $0.keys.map(\.label)) }, uniquingKeysWith: { first, _ in first })
        #expect(labels[testCase.tool] == testCase.labels)
    }

    @Test(arguments: [
        KeyCase("Shift-H and Shift-V flip", "H", 4, [.shift], .flip(horizontal: true)),
        KeyCase("Shift-H and Shift-V flip", "V", 9, [.shift], .flip(horizontal: false)),
        KeyCase("] and [ change the layer order", "]", 30, [], .layer(.front)),
        KeyCase("] and [ change the layer order", "[", 33, [], .layer(.back)),
        KeyCase("Shift-] is not a layer key", "]", 30, [.shift], nil),
        KeyCase("Plain Delete stays the canvas delete", nil, 51, [], nil),
        KeyCase("Plain Delete stays the canvas delete", nil, 117, [], nil),
    ])
    private func flipLayerAndDeleteKeysKeepTheirBindings(_ testCase: KeyCase) {
        #expect(command(testCase.characters, testCase.code, testCase.modifiers) == testCase.expected)
    }

    @Test(arguments: [[.command], [.control], [.option], [.command, .shift], [.control, .shift], [.option, .shift]] as [EaselKeyModifiers])
    func commandControlAndOptionSuppressToolLetters(_ flags: EaselKeyModifiers) {
        #expect(command("v", 9, flags) == nil, "Tool letters never fire with Command, Control or Option held")
        #expect(command("r", 15, flags) == nil, "Rectangle stays quiet under shortcut modifiers")
    }

    @Test(arguments: [
        KeyCase("Shift-R is not a tool key", "R", 15, [.shift], nil),
        KeyCase("Caps Lock letters still pick their tool", "V", 9, [], .tool(.select)),
        KeyCase("A non-Latin layout falls back to the key's position", "м", 9, [], .tool(.select)),
        KeyCase("Cyrillic layouts reach the sticky tool by position", "ы", 1, [], .tool(.sticky)),
        KeyCase("A layout that types punctuation there keeps the key for itself", ",", 46, [], nil),
        KeyCase("AZERTY's M picks the marker wherever the layout puts it", "m", 41, [], .tool(.marker)),
        KeyCase("A layout with a letter on the bracket key reaches it by position", "ü", 33, [], .layer(.back)),
        KeyCase("Backtick drops a code block", "`", 50, [], .tool(.codeBlock)),
        KeyCase("Accented letters with no tool stay unbound", "é", 19, [], nil),
        KeyCase("An empty character string falls back to the key's position", "", 4, [], .tool(.hand)),
        KeyCase("Unused keys stay free for later tools", "q", 12, [], nil),
        KeyCase("Unused keys stay free for later tools", "1", 18, [], nil),
    ])
    private func toolsUseTheTypedLetterOrPhysicalKeyForTheLayout(_ testCase: KeyCase) {
        #expect(command(testCase.characters, testCase.code, testCase.modifiers) == testCase.expected)
    }

    @Test
    func spaceIsTheTemporaryHand() {
        #expect(EaselKeyCommands.spaceKeyCode == 49, "Space is the temporary hand")
    }

    @Test(arguments: [
        KeyCase("⌘= zooms in", "=", 24, [.command], .zoom(.zoomIn)),
        KeyCase("⌘+ zooms in", "+", 24, [.command, .shift], .zoom(.zoomIn)),
        KeyCase("Keypad plus zooms in", "+", 69, [.command], .zoom(.zoomIn)),
        KeyCase("⌘− zooms out", "-", 27, [.command], .zoom(.zoomOut)),
        KeyCase("⇧⌘− zooms out like the View menu's alternate", "_", 27, [.command, .shift], .zoom(.zoomOut)),
        KeyCase("Keypad minus zooms out", "-", 78, [.command], .zoom(.zoomOut)),
        KeyCase("⌘0 returns to 100%", "0", 29, [.command], .zoom(.actualSize)),
        KeyCase("French layouts reach 100% by the zero key", "à", 29, [.command], .zoom(.actualSize)),
        KeyCase("⇧⌘0 is not a zoom key", "0", 29, [.command, .shift], nil),
        KeyCase("Option keeps ⌥⌘= for the system", "=", 24, [.command, .option], nil),
        KeyCase("Control keeps ⌃⌘= for the system", "=", 24, [.command, .control], nil),
        KeyCase("⇧1 zooms to fit", "!", 18, [.shift], .zoom(.fit)),
        KeyCase("⇧1 zooms to fit on layouts with symbols on the number row", "1", 18, [.shift], .zoom(.fit)),
        KeyCase("⇧2 zooms to the selection", "@", 19, [.shift], .zoom(.selection)),
        KeyCase("⇧0 returns to 100%", ")", 29, [.shift], .zoom(.actualSize)),
        KeyCase("⇧+ and ⇧− zoom in and out", "+", 24, [.shift], .zoom(.zoomIn)),
        KeyCase("⇧+ and ⇧− zoom in and out", "_", 27, [.shift], .zoom(.zoomOut)),
        KeyCase("Bare = and − zoom like their Shift versions", "=", 24, [], .zoom(.zoomIn)),
        KeyCase("Bare = and − zoom like their Shift versions", "-", 27, [], .zoom(.zoomOut)),
        KeyCase("German's own + key zooms in", "+", 30, [], .zoom(.zoomIn)),
        KeyCase("German Shift-ß types ? and stays free", "?", 27, [.shift], nil),
        KeyCase("German Shift-´ types a backtick and drops a code block, not a zoom", "`", 24, [.shift], .tool(.codeBlock)),
        KeyCase("⇧⌘? stays the Help menu's search on German layouts", "?", 27, [.command, .shift], nil),
        KeyCase("⇧⌘¿ on Spanish layouts is not a zoom", "¿", 24, [.command, .shift], nil),
        KeyCase("German ⌘ß zooms out by position", "ß", 27, [.command], .zoom(.zoomOut)),
        KeyCase("Plain digits are not zoom keys", "1", 18, [], nil),
        KeyCase("Plain digits are not zoom keys", "2", 19, [], nil),
    ])
    private func zoomShortcutsFollowTheirModifiersAndLayout(_ testCase: KeyCase) {
        #expect(command(testCase.characters, testCase.code, testCase.modifiers) == testCase.expected)
    }

    @Test
    func zoomCommandTitlesUseSentenceCase() {
        #expect(EaselZoomCommand.allCases.map(\.title) == ["Zoom in", "Zoom out", "Zoom to 100%", "Zoom to fit", "Zoom to selection"], "Zoom commands read in the Notes menus' sentence case")
    }

    @Test
    func zoomShortcutLabelsFitTheKeycapRenderer() {
        #expect(EaselZoomCommand.allCases.allSatisfy { !$0.shortcut.isEmpty && !$0.shortcut.contains("+") }, "Zoom shortcut labels avoid the plus sign the keycap renderer uses as a separator")
    }
}
