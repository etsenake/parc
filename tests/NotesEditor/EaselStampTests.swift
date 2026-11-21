import Foundation

@main
struct EaselStampTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    static func item(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double, z: Int = 0) -> EaselItem {
        var value = EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z)
        if kind == .arrow || kind == .freehand { value.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: width, y: height)] }
        return value
    }

    static func stamp(_ face: EaselStampFace, at point: EaselPoint = EaselPoint(x: 100, y: 100)) -> EaselItem {
        var value = EaselItem(kind: .stamp, frame: EaselStamps.frame(centeredAt: point, side: 64))
        face.apply(to: &value)
        return value
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Stamps", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @MainActor static func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }

    @MainActor static func main() {
        faces()
        emojiAndSymbols()
        validation()
        savedFormat()
        growthAndPlacement()
        tilt()
        attachment()
        stamping()
        wheelAndKeyboard()
        recents()
        icons()
        artwork()
        vectorExport()
        iconColour()
        print("EaselStampTests passed")
    }

    static func faces() {
        for design in EaselStampDesign.allCases {
            let face = EaselStampFace.design(design)
            expect(EaselStampFace(item: stamp(face)) == face, "\(design.title) survives a trip through the object")
            expect(EaselStampFace(token: face.token) == face, "\(design.title) survives a trip through recents")
            expect(face.stamp == design.rawValue && face.text.isEmpty, "Built-in stamps store their name and no text")
            expect(face.accessibilityLabel() == design.title + " stamp", "\(design.title) reads as a stamp")
        }
        expect(EaselStampFace.design(.thumbsUp).accessibilityLabel() == "Thumbs up stamp", "VoiceOver hears Thumbs up stamp")
        let party = EaselStampFace.emoji("🎉")
        expect(EaselStampFace(item: stamp(party)) == party && party.text == "🎉" && party.stamp == nil, "Emoji stamps keep the emoji as text")
        expect(party.accessibilityLabel(emojiName: "party popper") == "Party popper stamp", "Emoji stamps read their name")
        expect(party.accessibilityLabel() == "🎉 stamp", "An unnamed emoji still reads as a stamp")
        let cloud = EaselStampFace.icon("cloud")
        expect(cloud.text == "icon:cloud" && EaselStampFace(text: "icon:cloud") == cloud, "Icons store a prefixed symbol name")
        expect(cloud.accessibilityLabel() == "Cloud icon", "Icons read as icons")
        expect(EaselStampFace.icon("server.rack.fill").title() == "Server rack", "Unknown symbols get a readable name")
        expect(EaselStampFace(token: "icon:cloud") == cloud && EaselStampFace(token: "emoji:🎉") == party, "Tokens decode")
        for bad in ["", "stamp", "stamp:", "stamp:wave", "emoji:hi", "icon:Cloud", "icon:..", "logo:cloud", ":cloud"] {
            expect(EaselStampFace(token: bad) == nil, "Token \(bad) is refused")
        }
        var item = stamp(.design(.heart))
        EaselStampFace.icon("bolt").apply(to: &item)
        expect(item.stamp == nil && item.text == "icon:bolt", "Changing a face clears the old one")
        EaselStampFace.design(.star).apply(to: &item)
        expect(item.stamp == "star" && item.text.isEmpty, "And back again")
    }

    static func emojiAndSymbols() {
        for good in ["🎉", "👍🏽", "❤️", "1️⃣", "#️⃣", "🇨🇦", "👩‍👩‍👧‍👦", "🏳️‍🌈", "😀", "☝🏽", "©️", "☺️"] {
            expect(EaselStampFace.isEmoji(good), "\(good) is an emoji")
        }
        for bad in ["", "a", "1", "ab", "🎉🎉", " ", "\n", "🎉 ", "™", "❤", "☺", "A\u{FE0F}", "1\u{FE0F}", "x\u{FE0F}\u{20E3}",
                    "\u{20E3}", "👩‍👩‍👧‍👦x"] {
            expect(!EaselStampFace.isEmoji(bad), "\(bad.debugDescription) is not a single emoji")
        }
        expect(EaselStampFace(emoji: "❤") == .emoji("❤️") && EaselStampFace(emoji: "☺") == .emoji("☺️"),
               "Bare text-style emoji get their emoji look when picked")
        expect(EaselStampFace(emoji: "🎉") == .emoji("🎉") && EaselStampFace(emoji: "☝🏽") == .emoji("☝🏽")
               && EaselStampFace(emoji: "❤️") == .emoji("❤️"), "Emoji that already look right stay as they are")
        for bad in ["", "A", "1", "hi", "🎉🎉", "\u{FE0F}"] {
            expect(EaselStampFace(emoji: bad) == nil, "\(bad.debugDescription) never becomes an emoji stamp")
        }
        let custom = EaselStampFace.emoji(":party-parrot:")
        expect(EaselStampFace(emoji: ":party-parrot:") == custom && EaselStampFace(text: ":party-parrot:") == custom && EaselStampFace(token: "emoji::party-parrot:") == custom,
               "A custom emoji stamps by its name")
        expect(custom.customEmojiName == "party-parrot" && EaselStampFace.emoji("🎉").customEmojiName == nil, "Only references name a custom emoji")
        expect(custom.text == ":party-parrot:" && custom.token == "emoji::party-parrot:", "A custom emoji saves as its :name: text")
        for bad in [":", "::", ":a", "a:", ":UPPER:", ":two words:", ":-:", ":" + String(repeating: "a", count: 49) + ":", ":bad/name:"] {
            expect(!EaselStampFace.isEmoji(bad) && EaselStampFace(emoji: bad) == nil, "\(bad) is not a custom emoji name")
        }
        expect(EaselStampFace(text: "❤") == nil && EaselStampFace(token: "emoji:❤") == nil, "Saved stamps must already be tidy")
        for good in ["cloud", "server.rack", "chevron.left.forwardslash.chevron.right", "cylinder.split.1x2"] {
            expect(EaselStampFace.isSymbolName(good), "\(good) is a symbol name")
        }
        for bad in ["", "Cloud", "cloud fill", ".cloud", "cloud.", "cloud..fill", "../etc", String(repeating: "a", count: 97)] {
            expect(!EaselStampFace.isSymbolName(bad), "\(bad.debugDescription) is not a symbol name")
        }
    }

    @MainActor static func validation() {
        let plain = item(.rectangle, 10, 10, 100, 100)
        expect(accepts([plain, stamp(.design(.heart)), stamp(.emoji("🎉")), stamp(.icon("cloud"))]), "Every face saves")
        var wrongKind = plain; wrongKind.stamp = "heart"
        expect(!accepts([wrongKind]), "A stamp face on a rectangle is refused")
        var unknown = stamp(.design(.heart)); unknown.stamp = "wave"
        expect(!accepts([unknown]), "Unknown built-in stamps are refused")
        var both = stamp(.design(.heart)); both.text = "🎉"
        expect(!accepts([both]), "A built-in stamp with emoji text is refused")
        var empty = stamp(.emoji("🎉")); empty.text = ""
        expect(!accepts([empty]), "A stamp needs a face")
        var words = stamp(.emoji("🎉")); words.text = "hello"
        expect(!accepts([words]), "Plain words are not a stamp")
        var path = stamp(.icon("cloud")); path.text = "icon:../../etc"
        expect(!accepts([path]), "Odd symbol names are refused")
        var stroked = stamp(.design(.star)); stroked.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 1, y: 1)]
        expect(!accepts([stroked]), "Stamps carry no stroke points")
        var linked = stamp(.design(.star)); linked.url = "https://example.com"
        expect(!accepts([linked]), "Stamps carry no links")
        var styled = stamp(.design(.star)); styled.textStyle = EaselTextStyle()
        expect(!accepts([styled]), "Stamps carry no text style")
        var tilted = stamp(.design(.star)); tilted.rotation = -7.5; tilted.attachedTo = plain.id
        expect(accepts([plain, tilted]), "Tilted, attached stamps save")
    }

    static func savedFormat() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = item(.rectangle, 0, 0, 10, 10)
        guard let plainJSON = try? encoder.encode(plain), let plainText = String(data: plainJSON, encoding: .utf8) else {
            failTest("Plain objects encode")
        }
        expect(!plainText.contains("\"stamp\""), "Objects without stamps leave the field out")
        let heart = stamp(.design(.heart))
        guard let heartJSON = try? encoder.encode(heart), let heartText = String(data: heartJSON, encoding: .utf8),
              let decoded = try? JSONDecoder().decode(EaselItem.self, from: heartJSON) else { failTest("Stamps encode") }
        expect(heartText.contains("\"stamp\":\"heart\"") && heartText.contains("\"kind\":\"stamp\""), "Stamps save their kind and face")
        expect(decoded == heart, "Stamps decode unchanged")
        let legacy = Data("{\"id\":\"\(UUID().uuidString)\",\"kind\":\"rectangle\",\"frame\":{\"x\":0,\"y\":0,\"width\":5,\"height\":5},\"zIndex\":0,\"text\":\"\",\"color\":\"#252525\",\"points\":[]}".utf8)
        expect((try? JSONDecoder().decode(EaselItem.self, from: legacy))?.stamp == nil, "Older objects open without a stamp")
    }

    static func growthAndPlacement() {
        expect(EaselStamps.sizes.count == 4 && EaselStamps.sizes == EaselStamps.sizes.sorted(), "Four growing sizes")
        expect(EaselStamps.stage(heldFor: 0) == 0 && EaselStamps.stage(heldFor: -1) == 0 && EaselStamps.stage(heldFor: .nan) == 0,
               "A tap is the smallest stamp")
        expect(EaselStamps.stage(heldFor: 0.29) == 0 && EaselStamps.stage(heldFor: 0.31) == 1, "The first step comes after a short hold")
        expect(EaselStamps.stage(heldFor: 0.61) == 2 && EaselStamps.stage(heldFor: 0.91) == 3, "Holding keeps growing")
        expect(EaselStamps.stage(heldFor: 60) == 3 && EaselStamps.side(heldFor: 60) == EaselStamps.sizes[3], "Growth stops at the biggest size")
        let centred = EaselStamps.frame(centeredAt: EaselPoint(x: 200, y: 150), side: 64)
        expect(centred == EaselRect(x: 168, y: 118, width: 64, height: 64), "Stamps centre on the click")
        let corner = EaselStamps.frame(centeredAt: EaselPoint(x: 5, y: 10), side: 64)
        expect(corner.x == 0 && corner.y == 0 && corner.width == 64, "Stamps near the edge stay on the board")
        let odd = EaselStamps.frame(centeredAt: EaselPoint(x: .infinity, y: .nan), side: .nan)
        expect([odd.x, odd.y, odd.width, odd.height].allSatisfy(\.isFinite) && odd.width == EaselStamps.sizes[0], "Bad input still lands sanely")
    }

    static func tilt() {
        var generator = Seeded(state: 42)
        var signs = Set<Bool>()
        for _ in 0..<200 {
            let angle = EaselStamps.tilt(using: &generator)
            expect(abs(angle) >= EaselStamps.tiltRange.lowerBound && abs(angle) <= EaselStamps.tiltRange.upperBound,
                   "Tilt \(angle) stays a gentle lean")
            expect((angle * 10).rounded() == angle * 10, "Tilt is rounded to a tenth of a degree")
            signs.insert(angle > 0)
        }
        expect(signs.count == 2, "Stamps lean both ways")
    }

    static func attachment() {
        let sticky = item(.sticky, 0, 0, 200, 200, z: 1)
        let note = item(.rectangle, 50, 50, 100, 100, z: 2)
        let arrow = item(.arrow, 0, 0, 300, 300, z: 5)
        var placed = stamp(.design(.heart), at: EaselPoint(x: 100, y: 100)); placed.zIndex = 9; placed.attachedTo = note.id
        let items = [sticky, note, arrow, placed]
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 100, y: 100), in: items) == note.id,
               "A stamp on a stamp joins the same object")
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 60, y: 60), in: [sticky, note, arrow]) == note.id,
               "The topmost object under the click carries the stamp, never a connector")
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 20, y: 180), in: [sticky, note]) == sticky.id, "Lower objects carry stamps too")
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 500, y: 500), in: items) == nil, "The bare board carries nothing")
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 60, y: 60), in: [sticky, note], excluding: [note.id]) == sticky.id,
               "Excluded objects are skipped")
        var highlight = item(.freehand, 40, 40, 40, 40, z: 3); highlight.attachedTo = sticky.id
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 45, y: 45), in: [sticky, highlight]) == sticky.id,
               "Doodles never hold stamps, so a stamp on one sticks to the object below")
        var locked = item(.rectangle, 0, 0, 100, 100, z: 4); locked.locked = true
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 20, y: 20), in: [sticky, locked]) == sticky.id,
               "Locked backdrops never hold stamps")
        let section = item(.section, 0, 0, 600, 600, z: 0)
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 400, y: 400), in: [section]) == nil, "Sections carry stamps by holding them, not by sticking")
        var turned = item(.rectangle, 300, 0, 200, 40, z: 1); turned.rotation = 90
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 400, y: 90), in: [turned]) == turned.id
               && EaselStamps.attachmentTarget(at: EaselPoint(x: 310, y: 20), in: [turned]) == nil, "Rotated objects hold stamps where they really are")
        var loopA = item(.rectangle, 0, 0, 100, 100, z: 1), loopB = item(.rectangle, 0, 0, 100, 100, z: 2)
        loopA.attachedTo = loopB.id; loopB.attachedTo = loopA.id
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 10, y: 10), in: [loopA, loopB]) == nil, "Attachment loops never hang")
        let same = item(.rectangle, 0, 0, 100, 100, z: 0), later = item(.rectangle, 0, 0, 100, 100, z: 0)
        expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 10, y: 10), in: [same, later]) == later.id, "Ties go to the later object")
        expect(EaselStamps.centre(of: placed) == EaselPoint(x: 100, y: 100), "Stamps aim from their centre")

        let base = item(.sticky, 0, 0, 200, 200, z: 1), other = item(.sticky, 400, 0, 200, 200, z: 1)
        var riding = stamp(.design(.star), at: EaselPoint(x: 100, y: 100)); riding.attachedTo = base.id; riding.zIndex = 4
        let before = document([base, other, riding])
        func moving(_ ids: Set<UUID>, by dx: Double) -> EaselDocument {
            var next = before
            for index in next.items.indices where ids.contains(next.items[index].id) { next.items[index].frame.x += dx }
            return EaselDependents.settle(next, previous: before, moved: ids)
        }
        let dropped = moving([riding.id], by: 400)
        expect(dropped.items[2].attachedTo == other.id, "Dropping a stamp on another object moves it there")
        expect(moving([riding.id], by: 1200).items[2].attachedTo == nil, "Dropping it on the board lets go")
        let carried = moving([base.id], by: 30)
        expect(carried.items[2].attachedTo == base.id && carried.items[2].frame.x == riding.frame.x + 30, "Stamps ride along when their object moves")
        let together = moving([base.id, riding.id], by: 900)
        expect(together.items[2].attachedTo == base.id && together.items[2].frame.x == riding.frame.x + 900, "Moving both keeps them together")
        var turnedBase = before
        turnedBase.items[0].rotation = 90
        let spun = EaselDependents.settle(turnedBase, previous: before, moved: [base.id])
        expect(spun.items[2].rotation == 90 && spun.items[2].attachedTo == base.id, "Stamps turn with the object they ride")
        var arriving = stamp(.design(.heart), at: EaselPoint(x: 500, y: 100)); arriving.zIndex = 6
        var pasting = before
        pasting.items.append(arriving)
        expect(EaselDependents.settle(pasting, previous: before, moved: []).items[3].attachedTo == other.id,
               "Pasted and duplicated stamps stick to whatever they land on")
        pasting.items[3].frame = EaselStamps.frame(centeredAt: EaselPoint(x: 900, y: 900), side: 64)
        expect(EaselDependents.settle(pasting, previous: before, moved: []).items[3].attachedTo == nil, "Stamps pasted on bare board stay free")
        var unstuck = before
        unstuck.items[2].attachedTo = nil
        expect(EaselDependents.settle(unstuck, previous: before, moved: []).items[2].attachedTo == nil, "Existing free stamps are left alone")
        let cleared = EaselDependents.removing([base.id], from: before)
        expect(!cleared.items.contains { $0.id == riding.id } && cleared.items.contains { $0.id == other.id },
               "Deleting an object takes its stamps with it")
    }

    static func stamping() {
        let sticky = item(.sticky, 0, 0, 200, 200, z: 3)
        let doc = document([sticky])
        let heart = EaselStamps.stamped(.design(.heart), at: EaselPoint(x: 100, y: 100), tilt: -6.5, color: "#C0322D", in: doc)
        expect(heart.kind == .stamp && heart.stamp == "heart" && heart.text.isEmpty, "Stamping makes a stamp")
        expect(heart.frame == EaselRect(x: 68, y: 68, width: 64, height: 64) && heart.zIndex == 4, "It lands centred, on top")
        expect(heart.rotation == -6.5 && heart.attachedTo == sticky.id, "It leans and sticks")
        expect(heart.color == "#252525", "Built-in stamps keep their own colours")
        let icon = EaselStamps.stamped(.icon("cloud"), at: EaselPoint(x: 600, y: 600), side: 136, tilt: 0, color: "#c0322dff", in: doc)
        expect(icon.color == "#C0322D" && icon.attachedTo == nil && icon.rotation == nil, "Icons take the ink colour; flat stamps store no angle")
        expect(icon.frame.width == 136, "Grown stamps keep their size")
        let wild = EaselStamps.stamped(.emoji("🎉"), at: EaselPoint(x: 10, y: 10), tilt: .infinity, color: "nope", in: doc)
        expect(wild.rotation == nil && wild.color == "#252525", "Bad tilt and colour fall back")
    }

    static func wheelAndKeyboard() {
        for index in EaselStamps.ring.indices {
            let offset = EaselStamps.wheelOffset(of: index, radius: 80)
            expect(EaselStamps.wheelIndex(dx: offset.x, dy: offset.y, inner: 40, outer: 110) == index, "Pointing at wheel slot \(index) picks it")
        }
        expect(EaselStamps.wheelOffset(of: 0, radius: 80).y < -79 && EaselStamps.wheelOffset(of: 2, radius: 80).x > 79,
               "The wheel starts at the top and runs clockwise")
        expect(EaselStamps.wheelIndex(dx: 5, dy: 5, inner: 40, outer: 110) == nil
               && EaselStamps.wheelIndex(dx: 200, dy: 0, inner: 40, outer: 110) == nil
               && EaselStamps.wheelIndex(dx: .nan, dy: 0, inner: 40, outer: 110) == nil, "The hub and the outside pick no ring stamp")

        let sticky = item(.sticky, 100, 100, 200, 200, z: 1)
        let first = EaselStamps.pinnedPoint(on: sticky, side: 64, slot: 0), second = EaselStamps.pinnedPoint(on: sticky, side: 64, slot: 1)
        expect(abs(first.x - 274.4) < 0.01 && abs(first.y - 125.6) < 0.01, "Keyboard stamps land in the top right corner")
        expect(second.x < first.x && second.y == first.y, "More keyboard stamps line up beside the first")
        let later = EaselStamps.pinnedPoint(on: sticky, side: 64, slot: 40)
        expect(later.x >= 125 && later.y <= 275, "Crowded objects keep stamps inside")
        var turned = sticky; turned.rotation = 90
        let spun = EaselStamps.pinnedPoint(on: turned, side: 64, slot: 0)
        expect(abs(spun.x - 274.4) < 0.01 && abs(spun.y - 274.4) < 0.01, "Turned objects get stamps on their turned corner")
        let tiny = item(.rectangle, 0, 0, 10, 10, z: 0)
        expect(EaselStamps.pinnedPoint(on: tiny, side: 184, slot: 3) == EaselPoint(x: 5, y: 5), "Tiny objects get stamps in the middle")

        var riding = stamp(.design(.heart), at: EaselPoint(x: 150, y: 150)); riding.attachedTo = sticky.id
        var locked = item(.rectangle, 500, 0, 100, 100, z: 1); locked.locked = true
        let arrow = item(.arrow, 0, 0, 50, 50, z: 1), other = item(.rectangle, 700, 0, 100, 100, z: 1)
        let all = [sticky, riding, locked, arrow, other]
        expect(EaselStamps.keyboardTargets([riding.id, sticky.id, other.id, locked.id, arrow.id], in: all) == [sticky.id, other.id],
               "⌘Return stamps each selected object once, through its stamps, never locked objects or connectors")
    }

    static func recents() {
        var list: [String] = []
        list = EaselStamps.recording(.emoji("🎉"), in: list)
        list = EaselStamps.recording(.design(.heart), in: list)
        list = EaselStamps.recording(.icon("cloud"), in: list)
        list = EaselStamps.recording(.emoji("🎉"), in: list)
        expect(list == ["emoji:🎉", "icon:cloud", "stamp:heart"], "Recents move to the front without repeats")
        list = EaselStamps.recording(.icon("bolt"), in: list + ["junk", "emoji:hi", "icon:cloud"])
        expect(list == ["icon:bolt", "emoji:🎉", "icon:cloud", "stamp:heart"], "Damaged and repeated recents are dropped")
        for index in 0..<20 { list = EaselStamps.recording(.icon("icon\(index)"), in: list) }
        expect(list.count == EaselStamps.recentsLimit, "Recents stay short")
        let hub = EaselStamps.hubFaces(["stamp:heart", "emoji:🎉", "icon:cloud", "emoji:🎉", "icon:bolt", "emoji:😀"])
        expect(hub == [.emoji("🎉"), .icon("cloud"), .icon("bolt")], "The wheel's centre shows three recent extras, never ring stamps")
        expect(EaselStamps.hubFaces([]).isEmpty, "No recents, empty centre")
        expect(Set(EaselStamps.ring) == Set(EaselStampDesign.allCases) && EaselStamps.ring.count == 8, "The ring holds all eight stamps")
    }

    static func icons() {
        let all = EaselStampIcons.all
        expect(all.count >= 80, "A generous icon set")
        expect(Set(all.map(\.symbol)).count == all.count, "Each icon appears once")
        expect(Set(all.map { $0.title.lowercased() }).count == all.count, "Icon names are unique for VoiceOver")
        expect(all.allSatisfy { EaselStampFace.isSymbolName($0.symbol) && !$0.title.isEmpty }, "Icons have valid symbols and names")
        expect(EaselStampIcons.sections.allSatisfy { !$0.icons.isEmpty && !$0.title.isEmpty }, "Sections are named and filled")
        for (query, symbol) in [("database", "cylinder.split.1x2"), ("server", "server.rack"), ("user", "person"), ("mail", "envelope"),
                                ("credit", "creditcard"), ("auth", "person.badge.key"), ("settings", "gearshape"), ("wifi", "wifi"),
                                ("location", "mappin.and.ellipse"), ("chat", "bubble.left"), ("package", "shippingbox")] {
            expect(EaselStampIcons.search(query).contains { $0.symbol == symbol }, "Searching \(query) finds \(symbol)")
        }
        expect(EaselStampIcons.search("Cl").first?.symbol == "cloud", "Name matches come first")
        expect(EaselStampIcons.search("  ").count == all.count && EaselStampIcons.search("zzzz").isEmpty, "Blank searches show everything")
        expect(EaselStampIcons.icon(named: "cloud")?.title == "Cloud" && EaselStampIcons.icon(named: "nope") == nil, "Icons look up by symbol")
    }

    static func artwork() {
        for design in EaselStampDesign.allCases {
            let layers = EaselStampArt.layers(design)
            expect(layers.count >= 5, "\(design.title) has a rim, shadow and body")
            expect(layers.contains { $0.tone == .rim && $0.outline == EaselStampArt.rimWidth }, "\(design.title) wears a sticker rim")
            expect(layers.filter { $0.tone == .shadow }.allSatisfy { $0.opacity < 0.2 }, "\(design.title) casts a soft shadow")
            for layer in layers {
                expect(!layer.path.elements.isEmpty, "\(design.title) layers have shapes")
                expect(layer.path.points.allSatisfy { $0.x >= -1 && $0.x <= 101 && $0.y >= -1 && $0.y <= 101 && $0.x.isFinite && $0.y.isFinite },
                       "\(design.title) stays inside its square")
                expect(layer.opacity > 0 && layer.opacity <= 1, "\(design.title) opacities are sane")
                expect(layer.filled || layer.outline != nil, "\(design.title) layers paint something")
                let hex = EaselStampArt.hex(layer.tone, for: design)
                expect(hex.count == 7 && hex.hasPrefix("#") && hex.dropFirst().allSatisfy(\.isHexDigit), "\(design.title) colours are hex")
            }
        }
        let thumbsUp = EaselStampArt.layers(.thumbsUp), thumbsDown = EaselStampArt.layers(.thumbsDown)
        expect(thumbsUp.count == thumbsDown.count && thumbsUp.last?.path != thumbsDown.last?.path, "Thumbs down is its own pose")
        let disc = EaselStampPath.circle(50, 50, 40)
        let xs = disc.points.map(\.x), ys = disc.points.map(\.y)
        expect(abs((xs.min() ?? 0) - 10) < 1e-9 && abs((xs.max() ?? 0) - 90) < 1e-9 && abs((ys.min() ?? 0) - 10) < 1e-9, "Circles fit their radius")
        let svg = disc.svgData(in: EaselRect(x: 100, y: 200, width: 50, height: 50))
        expect(svg.hasPrefix("M145 225C") && svg.hasSuffix("Z"), "Paths map into the stamp's frame for SVG")
        let turned = EaselStampPath.roundedRect(0, 0, 10, 10, 2).rotated(by: 180, around: EaselPoint(x: 5, y: 5))
        expect(turned.points.allSatisfy { $0.x > -1e-9 && $0.x < 10 + 1e-9 }, "Rotating about the centre stays in place")
        let star = EaselStampPath.star(centre: EaselPoint(x: 50, y: 50), outer: 40, inner: 20)
        expect(star.elements.filter { if case .curve = $0 { return true } else { return false } }.count == 10, "Stars round all ten corners")
        let ring = EaselStampPath.ring(centre: EaselPoint(x: 50, y: 50), outer: 20, inner: 10, from: 180, to: 450)
        expect(ring.points.allSatisfy { hypot($0.x - 50, $0.y - 50) < 23 }, "Arcs hug their circle")
    }

    static func vectorExport() {
        let art = EaselVectorArt()
        var heart = stamp(.design(.heart)); heart.rotation = 8
        let heartSVG = EaselVectorExport.element(heart, art: art)
        expect(heartSVG.contains("<g class=\"easel-stamp\">") && heartSVG.components(separatedBy: "<path").count - 1 == EaselStampArt.layers(.heart).count,
               "Built-in stamps export as vector paths")
        expect(heartSVG.hasPrefix("<g transform=\"rotate(8 ") && heartSVG.components(separatedBy: "rotate(").count == 2,
               "A tilted stamp exports its tilt once, around its centre")
        expect(heartSVG.contains("#F2506A") && heartSVG.contains("stroke:#FFFFFF"), "Their colours and rim come along")
        let party = EaselVectorExport.element(stamp(.emoji("🎉")), art: art)
        expect(party.contains(">🎉</text>") && party.contains("text-anchor=\"middle\""), "Emoji export as text")
        let parrot = stamp(.emoji(":party-parrot:"))
        expect(EaselVectorExport.element(parrot, art: art).contains(">:party-parrot:</text>"), "A deleted custom emoji falls back to its :name: text")
        var parrotArt = EaselVectorArt()
        parrotArt.images[parrot.id] = EaselVectorImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        let parrotSVG = EaselVectorExport.element(parrot, art: parrotArt)
        expect(parrotSVG.contains("<image") && parrotSVG.contains("data:image/png;base64,") && !parrotSVG.contains("<text"), "A custom emoji exports as its picture")
        var cloud = stamp(.icon("cloud"))
        expect(EaselVectorExport.element(cloud, art: art).isEmpty, "Icons without a picture export nothing rather than junk")
        var withPicture = EaselVectorArt()
        withPicture.images[cloud.id] = EaselVectorImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        let automatic = EaselVectorExport.element(cloud, art: withPicture)
        expect(automatic.contains("<mask") && automatic.contains("fill:var(--easel-ink)") && automatic.contains("data:image/png;base64,"),
               "Icons export as a tinted mask that follows light and dark")
        cloud.color = "#123456"
        expect(EaselVectorExport.element(cloud, art: withPicture).contains("fill:#123456"), "Custom icon colours stay exact")
        cloud.color = "#2C6C91"
        expect(EaselVectorExport.element(cloud, art: withPicture).contains("fill:var(--"), "Palette icon colours follow light and dark like other Easel colours")
        var broken = stamp(.design(.heart)); broken.stamp = "wave"
        expect(EaselVectorExport.element(broken, art: art).isEmpty, "Damaged stamps export nothing")
        let doc = document([item(.rectangle, 0, 0, 50, 50), heart, stamp(.emoji("🎉"))])
        let html = EaselVectorExport.htmlDocument(doc, art: art)
        expect(html.contains("easel-stamp") && html.contains("🎉"), "Stamps make it into the HTML page")
    }

    @MainActor static func iconColour() {
        var cloud = stamp(.icon("cloud"))
        let party = stamp(.emoji("🎉")), heart = stamp(.design(.heart))
        expect(EaselStyleFamily.of(cloud) == .icons && EaselStyleFamily.of(party) == nil && EaselStyleFamily.of(heart) == nil,
               "Only icon stamps take a colour")
        expect(EaselSelectionToolbarPlan.groups(for: [EaselToolbarSubject(cloud)], editingText: false, locked: false) == [[.color], [.more]],
               "A selected icon gets the style button")
        expect(EaselSelectionToolbarPlan.groups(for: [EaselToolbarSubject(party)], editingText: false, locked: false) == [[.more]],
               "Emoji and built-in stamps stay colourless")
        guard let palette = EaselPalette.colors(for: .ink).first(where: { $0 != .automatic }) else { failTest("No ink palette") }
        expect(EaselStyle.apply(.color(.palette(palette)), to: &cloud) && cloud.color == EaselPalette.stored(palette, role: .ink),
               "The style button recolours icons with palette colours")
        expect(EaselStyle.colorChoice(of: cloud) == .palette(palette), "The picker shows the icon's palette colour")
        var art = EaselVectorArt()
        art.images[cloud.id] = EaselVectorImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        expect(EaselVectorExport.element(cloud, art: art).contains("fill:var(--"), "Recoloured icons export their palette colour for light and dark")
        var mixed = party
        expect(!EaselStyle.apply(.color(.palette(palette)), to: &mixed) && mixed == party, "Recolouring a mixed selection leaves emoji alone")
        expect(accepts([cloud]), "Recoloured icons still save")
    }
}
