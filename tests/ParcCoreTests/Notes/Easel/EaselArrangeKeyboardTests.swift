import Testing
@testable import ParcCore

struct EaselArrangeKeyboardTests {
    private func chord(_ characters: String, _ keyCode: UInt16, _ modifiers: EaselKeyModifiers) -> EaselChordCommand? {
        EaselChords.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    @Test
    func commandDDuplicates() {
        #expect(chord("d", 2, .command) == .duplicate, "⌘D duplicates")
    }

    @Test
    func commandGGroupsAndShiftCommandGUngroups() {
        #expect(chord("g", 5, .command) == .group, "⌘G groups")
        #expect(chord("G", 5, [.command, .shift]) == .ungroup, "⇧⌘G ungroups")
    }

    @Test
    func commandDeleteUnwrapsAGroup() {
        #expect(chord("", 51, .command) == .unwrap, "⌘Delete unwraps a group")
    }

    @Test
    func shiftCommandLTogglesLock() {
        #expect(chord("L", 37, [.command, .shift]) == .toggleLock, "⇧⌘L locks and unlocks")
    }

    @Test
    func commandBracketsStepThroughLayersAcrossLayouts() {
        #expect(chord("]", 30, .command) == .layer(.forward) && chord("[", 33, .command) == .layer(.backward), "⌘] and ⌘[ step through layers")
        #expect(chord("ж", 30, .command) == .layer(.forward), "Layer chords follow the physical key on other layouts")
    }

    @Test
    func commandReturnQuickCreatesFromEitherReturnKey() {
        #expect(chord("", 36, .command) == .quickCreate && chord("", 76, .command) == .quickCreate, "⌘Return quick creates from either Return key")
        #expect(EaselChords.command(characters: "", keyCode: 36, modifiers: .command, stampArmed: false) == .quickCreate, "⌘Return keeps quick create without the stamp tool")
    }

    @Test
    func anArmedStampToolClaimsOnlyCommandReturn() {
        func armed(_ keyCode: UInt16, _ modifiers: EaselKeyModifiers) -> EaselChordCommand? {
            EaselChords.command(characters: "", keyCode: keyCode, modifiers: modifiers, stampArmed: true)
        }
        #expect(armed(36, .command) == .stampSelection && armed(76, .command) == .stampSelection, "⌘Return stamps the selection while the stamp tool is armed")
        #expect(armed(36, [.command, .shift]) == .mindMapSibling && armed(2, .command) == .duplicate, "Armed stamps only claim ⌘Return")
    }

    @Test
    func shiftCommandEExportsTheSelection() {
        #expect(chord("E", 14, [.command, .shift]) == .exportSelection, "⇧⌘E exports the selection")
    }

    @Test
    func shiftCommandReturnAddsAMindMapSibling() {
        #expect(chord("", 36, [.command, .shift]) == .mindMapSibling && chord("", 76, [.command, .shift]) == .mindMapSibling, "⇧⌘Return adds a mind map sibling from either Return key")
    }

    @Test
    func otherReturnChordsDoNotQuickCreate() {
        #expect(chord("", 36, []) == nil && chord("", 36, [.command, .option]) == nil, "Other Return chords stay out of quick create")
    }

    @Test
    func addingOptionDoesNotDuplicate() {
        #expect(chord("d", 2, [.command, .option]) == nil, "Extra modifiers don't trigger Duplicate")
    }

    @Test
    func easelChordsLeaveReservedBindingsAlone() {
        #expect(EaselChords.reserved.allSatisfy { EaselChords.table[$0] == nil }, "Easels never take Parc's reserved chords")
    }

    @Test
    func plainBracketsMoveToTheFrontOrBack() {
        #expect(EaselKeyCommands.command(characters: "]", keyCode: 30, modifiers: []) == .layer(.front), "Bare ] brings to front")
        #expect(EaselKeyCommands.command(characters: "[", keyCode: 33, modifiers: []) == .layer(.back), "Bare [ sends to back")
        #expect(EaselKeyCommands.command(characters: "}", keyCode: 30, modifiers: [.shift]) != .layer(.front), "Shift-] is not a layer key")
    }

    @Test
    func toolLettersStillWork() {
        #expect(EaselKeyCommands.command(characters: "v", keyCode: 9, modifiers: []) == .tool(.select), "Tool letters still work")
    }
}
