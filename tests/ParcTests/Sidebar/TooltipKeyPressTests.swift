import AppKit
import Testing
@testable import Parc

@MainActor
struct TooltipKeyPressTests {
    typealias Chord = (NSEvent) -> KeyboardShortcut?
    private static let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    private static let typed: Chord = { KeyboardShortcut.characterCapture($0) }
    private static let none: Chord = { _ in nil }
    private static let shiftedSymbols: Chord = { event in
        guard let chord = KeyboardShortcut.characterCapture(event), chord.flags.contains(.shift),
              let symbol = event.charactersIgnoringModifiers, ["}", "{", "+"].contains(symbol) else { return nil }
        return KeyboardShortcut(key: symbol, flags: chord.flags.subtracting(.shift))
    }

    private static func key(_ code: UInt16, _ typed: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: typed, charactersIgnoringModifiers: typed, isARepeat: false, keyCode: code)!
    }
    private static func press(_ event: NSEvent, _ shortcut: KeyboardShortcut, chord: Chord? = nil, symbolic: Chord? = nil) -> TooltipKeyPress {
        TooltipController.keyPress(for: event, showing: shortcut, eventChord: chord ?? typed, symbolicChord: symbolic)
    }
    private static func pressed(_ event: NSEvent, _ shortcut: KeyboardShortcut, chord: Chord? = nil, symbolic: Chord? = nil) -> [Bool] {
        let press = press(event, shortcut, chord: chord, symbolic: symbolic)
        let held = event.modifierFlags.intersection(KeyboardShortcut.modifierMask)
        return TooltipKeycap.keycaps(for: shortcut).map { $0.isPressed(modifiers: held, characters: press.key) }
    }
    private static func holds(_ event: NSEvent, _ shortcut: KeyboardShortcut, symbolic: Chord? = nil) -> Bool {
        pressed(event, shortcut, symbolic: symbolic).allSatisfy { $0 }
    }
    private static func performs(_ event: NSEvent, _ shortcut: KeyboardShortcut, chord: Chord? = nil, symbolic: Chord? = nil) -> Bool {
        let press = press(event, shortcut, chord: chord, symbolic: symbolic)
        var state = TooltipPresentationState<String>()
        state.didPresent("tooltip")
        return state.keyDown(escape: event.keyCode == 53, modifiers: press.modifiers, characters: press.key, shortcut: shortcut, now: t0) != nil
    }

    private static let two = KeyboardShortcut.keyForPhysicalCode(19)!, s = KeyboardShortcut.keyForPhysicalCode(1)!
    private static var capture: KeyboardShortcut { KeyboardShortcut(key: two, flags: [.command, .shift]) }
    private static var save: KeyboardShortcut { KeyboardShortcut(key: s, flags: .command) }
    private static let nextTab = KeyboardShortcut(key: "}", flags: .command)

    @Test func commandShiftTwoIsTheTwoKeyReadThroughTheLayoutWithoutShift() {
        let event = Self.key(19, "@", [.command, .shift])
        #expect(Self.two != "@")
        #expect(Self.press(event, Self.capture) == TooltipKeyPress(modifiers: [.command, .shift], key: Self.two))
    }

    @Test func capturesTwoKeycapPressesAndTheShortcutFadesItsTooltip() {
        let event = Self.key(19, "@", [.command, .shift])
        #expect(Self.holds(event, Self.capture) && Self.performs(event, Self.capture))
    }

    @Test func commandShiftSIsNotCommandS() {
        let event = Self.key(1, Self.s.uppercased(), [.command, .shift])
        #expect(Self.holds(event, Self.save) && !Self.performs(event, Self.save))
    }

    @Test func aKeyNoCommandTakesAloneStillPressesItsOwnKeycap() {
        #expect(Self.pressed(Self.key(1, Self.s, []), Self.save) == [false, true])
    }

    @Test func shiftTwoAlonePressesCapturesShiftAndTwoKeycapsFromThePhysicalKey() {
        let event = Self.key(19, "@", .shift)
        #expect(Self.pressed(event, Self.capture) == [true, false, true])
        #expect(!Self.performs(event, Self.capture))
    }

    @Test func aLoneShiftLetterPressesItsLetterKeycap() {
        #expect(Self.pressed(Self.key(1, Self.s.uppercased(), .shift), KeyboardShortcut(key: Self.s, flags: [.command, .shift])) == [true, false, true])
    }

    @Test func aShortcutStoredAsItsShiftedSymbolFoldsShiftIntoTheSymbol() {
        let event = Self.key(30, "}", [.command, .shift])
        #expect(Self.press(event, Self.nextTab, symbolic: Self.shiftedSymbols) == TooltipKeyPress(modifiers: .command, key: "}"))
        #expect(Self.holds(event, Self.nextTab, symbolic: Self.shiftedSymbols))
        #expect(Self.performs(event, Self.nextTab, symbolic: Self.shiftedSymbols))
    }

    @Test func commandPlusCountsFromTheKeyThatTypesPlusWithShift() {
        let event = Self.key(24, "+", [.command, .shift]), zoomIn = KeyboardShortcut(key: "+", flags: .command)
        #expect(Self.holds(event, zoomIn, symbolic: Self.shiftedSymbols) && Self.performs(event, zoomIn, symbolic: Self.shiftedSymbols))
    }

    @Test func otherTooltipsKeepThePhysicalKey() {
        let bracket = KeyboardShortcut.keyForPhysicalCode(30)!
        #expect(Self.press(Self.key(30, "}", [.command, .shift]), Self.save, symbolic: Self.shiftedSymbols)
                == TooltipKeyPress(modifiers: [.command, .shift], key: bracket))
    }

    @Test func holdingShiftBracketAlonePressesTheBraceKeycapWithoutPerformingTheShortcut() {
        let event = Self.key(30, "}", .shift)
        #expect(Self.pressed(event, Self.nextTab, symbolic: Self.shiftedSymbols) == [false, true])
        #expect(!Self.performs(event, Self.nextTab, symbolic: Self.shiftedSymbols))
    }

    @Test func whenDispatchGivesThatChordToAnotherCommandTheSymbolIsNotThisTooltipsShortcut() {
        let event = Self.key(30, "}", [.command, .shift])
        #expect(!Self.holds(event, Self.nextTab, symbolic: Self.none) && !Self.performs(event, Self.nextTab, symbolic: Self.none))
    }

    @Test func anAssignedKeypadChordKeepsItsOwnKey() {
        let keypadOne = KeyboardShortcut.keypadKey(forPhysicalCode: 83)!
        let keypad = KeyboardShortcut(key: keypadOne, flags: .control), controlOne = KeyboardShortcut(key: "1", flags: .control)
        let chord: Chord = { $0.keyCode == 83 ? KeyboardShortcut(key: keypadOne, flags: $0.modifierFlags) : KeyboardShortcut.characterCapture($0) }
        let event = Self.key(83, "1", .control)
        #expect(Self.press(event, keypad, chord: chord).key == keypadOne)
        #expect(Self.performs(event, keypad, chord: chord) && !Self.performs(event, controlOne, chord: chord))
    }

    @Test func anUnassignedKeypadKeyFallsBackToItsCharacter() {
        let keypad = KeyboardShortcut(key: KeyboardShortcut.keypadKey(forPhysicalCode: 83)!, flags: .control)
        let controlOne = KeyboardShortcut(key: "1", flags: .control), event = Self.key(83, "1", .control)
        #expect(Self.press(event, controlOne).key == "1")
        #expect(Self.performs(event, controlOne) && !Self.performs(event, keypad))
    }

    @Test func anUnassignedClearStaysClearAndNeverPerformsEscape() {
        let clear = Self.key(71, KeyboardShortcut.clearKey, []), exit = KeyboardShortcut(key: "\u{1b}", flags: [])
        #expect(Self.press(clear, exit).key == KeyboardShortcut.clearKey)
        #expect(!Self.performs(clear, exit))
    }
}
