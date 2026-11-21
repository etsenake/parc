import Foundation

@main
struct EaselRoundTripTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let corpus = ["words", "shapes", "web", "empty"]
    static let itemFields: Set<String> = ["id", "kind", "frame", "zIndex", "movedToFrontAt", "text", "textStyle", "richText", "url",
                                          "assetID", "color", "points", "capturedAt", "captureLayout", "liveCapture"]
    static let styleFields: Set<String> = ["fill", "family", "size"]
    static let documentFields: Set<String> = ["version", "id", "title", "createdAt", "modifiedAt", "items"]
    static let layoutFields: Set<String> = ["viewport", "scroll", "region", "scrollContainers"]

    static func fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/EaselRoundTrip")
        return try Data(contentsOf: directory.appendingPathComponent(name + ".json"))
    }

    static func isEmpty(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    static func strayFields(_ value: Any, allowed: Set<String>) -> [String] {
        Mirror(reflecting: value).children.compactMap { child in
            guard let label = child.label, !allowed.contains(label), !isEmpty(child.value) else { return nil }
            return label
        }
    }

    static func keyPaths(_ value: Any, _ path: String = "") -> Set<String> {
        if let dictionary = value as? [String: Any] {
            var paths = Set<String>()
            for (key, child) in dictionary {
                let next = path + "/" + key
                paths.insert(next)
                paths.formUnion(keyPaths(child, next))
            }
            return paths
        }
        if let array = value as? [Any] {
            var paths = Set<String>()
            for (index, child) in array.enumerated() { paths.formUnion(keyPaths(child, path + "[\(index)]")) }
            return paths
        }
        return []
    }

    static func keys(_ data: Data) throws -> Set<String> {
        keyPaths(try JSONSerialization.jsonObject(with: data))
    }

    static func encode(_ document: EaselDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    @MainActor static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-roundtrip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @MainActor static func main() { exitOnFailure(runChecks) }

    @MainActor static func runChecks() throws {
        for name in corpus { try decodedValues(name) }
        try oldLooks()
        for name in corpus { try reencoding(name) }
        for name in corpus { try storeRoundTrip(name) }
        try storeEditAndUndo()
        try storeListing()
        noteLinks()
        print("EaselRoundTrip: \(assertions) assertions passed (\(corpus.count) saved Easels)")
    }

    @MainActor static func decode(_ name: String) throws -> EaselDocument {
        try JSONDecoder().decode(EaselDocument.self, from: fixture(name))
    }

    @MainActor static func decodedValues(_ name: String) throws {
        let document = try decode(name)
        let json = try JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any] ?? [:]
        let rawItems = json["items"] as? [[String: Any]] ?? []
        expect(document.version == 1, "\(name): format version stays 1")
        expect(document.items.count == rawItems.count, "\(name): every saved object decodes")
        expect(strayFields(document, allowed: documentFields).isEmpty, "\(name): the document gains no values on open")
        for (item, raw) in zip(document.items, rawItems) {
            expect(item.id.uuidString.lowercased() == raw["id"] as? String, "\(name): object ID survives")
            expect(item.kind.rawValue == raw["kind"] as? String, "\(name): kind survives")
            expect(item.text == raw["text"] as? String, "\(name): text survives")
            expect(item.color == raw["color"] as? String, "\(name): colour survives")
            expect(item.zIndex == raw["zIndex"] as? Int, "\(name): layer survives")
            expect(item.url == raw["url"] as? String && item.assetID == raw["assetID"] as? String, "\(name): URL and asset survive")
            expect(strayFields(item, allowed: itemFields).isEmpty, "\(name): \(item.kind) gains no value for any new field on open: \(strayFields(item, allowed: itemFields))")
            if let style = item.textStyle { expect(strayFields(style, allowed: styleFields).isEmpty, "\(name): text style gains no new value on open") }
            if let layout = item.captureLayout { expect(strayFields(layout, allowed: layoutFields).isEmpty, "\(name): capture layout gains no new value on open") }
        }
        switch name {
        case "words": try words(document)
        case "shapes": try shapes(document)
        case "web": try web(document)
        default:
            expect(document.items.isEmpty && document.title == "Untitled Easel", "empty: a blank Easel opens blank")
        }
    }

    @MainActor static func words(_ document: EaselDocument) throws {
        let items = document.items
        expect(document.title == "Words" && items.count == 4 && items.allSatisfy { $0.kind == .text }, "words: four text objects")
        expect(items[0].text == "Plain words" && items[0].textStyle == nil && items[0].richText == nil, "words: plain text stays plain")
        expect(items[0].movedToFrontAt == Date(timeIntervalSinceReferenceDate: 700_000_000), "words: front-moved date survives")
        expect(items[0].frame == EaselRect(x: 40, y: 50, width: 260, height: 90), "words: frame survives")
        let styled = items[1].textStyle
        expect(styled?.family == .hip && styled?.size == .h1 && styled?.fill == .contentHugging, "words: text style survives")
        expect(styled?.alignment == nil && styled?.textScale == nil && styled?.customSize == nil && styled?.autoWidth == nil, "words: style gains no sizing or alignment")
        expect(styled?.pointSize == 44 && items[1].color == "#C0322D", "words: style still sizes like before")
        expect(items[2].textStyle?.family == .mono && items[2].textStyle?.size == .ultra && items[2].textStyle?.fill == nil, "words: style without fill stays without")
        expect(items[2].textStyle?.pointSize == 80, "words: ultra mono still sizes like before")
        guard let rich = items[3].richText else { fatalError("words: rich text survives") }
        expect(rich.runs.count == 4 && rich.runs.map(\.length) == [5, 1, 11, 7], "words: run ranges survive")
        expect(rich.runs[0].attributes.font.name == "Helvetica-Bold" && rich.runs[0].attributes.font.variations == ["2003265652": 700], "words: font survives")
        expect(rich.runs[0].attributes.font.style?.family == .clean, "words: font style survives")
        expect(rich.runs[1].attributes.image?.fileType == "public.png" && rich.runs[1].attributes.image?.data == png, "words: inline image survives")
        expect(rich.runs[2].attributes.link == "https://example.com/page?x=1" && rich.runs[2].attributes.background == "#FFEB3B80", "words: link and highlight survive")
        expect(rich.runs[2].attributes.paragraph?.heading == 2 && rich.runs[2].attributes.paragraph?.lists.first?.marker == "{disc}", "words: paragraph and list survive")
        expect(rich.runs[3].attributes.semanticInk == .noteBody, "words: semantic ink survives")
        try rich.validate(text: items[3].text)
    }

    @MainActor static func shapes(_ document: EaselDocument) throws {
        let items = document.items
        expect(items.map(\.kind) == [.rectangle, .rectangle, .circle, .arrow, .arrow, .freehand, .rectangle], "shapes: every drawing kind decodes in order")
        expect(items[0].text == "Box" && items[0].color == "#2C6C91", "shapes: rectangle text and colour survive")
        expect(items[1].color == "#252525" && items[1].frame == EaselRect(x: 200, y: 20, width: 80.5, height: 40.25), "shapes: automatic ink and fractional frame survive")
        expect(items[2].textStyle?.family == .fancy && items[2].textStyle?.size == .h2, "shapes: circle text style survives")
        expect(items[3].points == [EaselPoint(x: 300, y: 20), EaselPoint(x: 440, y: 80)] && items[3].text == "to", "shapes: arrow points and label survive")
        expect(items[4].points.count == 2, "shapes: arrow without label survives")
        expect(items[5].points == [EaselPoint(x: 20, y: 260), EaselPoint(x: 45.5, y: 280.25), EaselPoint(x: 80, y: 262), EaselPoint(x: 140, y: 300)], "shapes: freehand points survive")
        expect(items[5].color == "#3E8E5A", "shapes: freehand colour survives")
        expect(items[6].frame == EaselRect(x: -1_000_000, y: 1_000_000, width: 1, height: 1) && items[6].zIndex == -4 && items[6].color == "#abcdef", "shapes: extreme frame, negative layer and lowercase colour survive")
    }

    @MainActor static func web(_ document: EaselDocument) throws {
        let items = document.items
        expect(items.map(\.kind) == [.image, .link, .webCard, .webCard, .browser], "web: image, link, captures and browser decode in order")
        expect(items[0].assetID == "00000000-0000-4000-8000-000000000999.png", "web: image asset survives")
        expect(items[1].url == "https://example.com/article" && items[1].text == "Example page", "web: link survives")
        expect(items[2].capturedAt == Date(timeIntervalSinceReferenceDate: 700_200_000) && items[2].captureLayout == nil && items[2].liveCapture == nil, "web: still capture stays still")
        expect(!items[2].ownsEmbeddedPage && !items[1].ownsEmbeddedPage, "web: only live captures and browsers own pages")
        let live = items[3]
        expect(live.liveCapture == true && live.ownsEmbeddedPage, "web: live capture stays live")
        expect(live.capturedAt == Date(timeIntervalSinceReferenceDate: 700_200_100.5), "web: fractional capture date survives")
        expect(live.captureLayout?.viewport == EaselPoint(x: 1280, y: 800) && live.captureLayout?.region == EaselRect(x: 10, y: 20, width: 600, height: 400), "web: capture geometry survives")
        expect(live.captureLayout?.scrollContainers?.first?.anchorID == "feed" && live.captureLayout?.scrollContainers?.first?.path == "main:0>div:2", "web: scroll containers survive")
        expect(items[4].url == "https://example.com/docs" && items[4].ownsEmbeddedPage, "web: browser survives")
    }

    @MainActor static func oldLooks() throws {
        for name in corpus {
            for item in try decode(name).items {
                let label = "\(name) \(item.kind)"
                switch item.kind {
                case .rectangle: expect(item.resolvedShape == .rectangle, "\(label): plain rectangles stay rectangles")
                case .circle: expect(item.resolvedShape == .ellipse, "\(label): circles stay ellipses")
                default: expect(item.resolvedShape == nil, "\(label): other objects have no outline shape")
                }
                expect(!item.isLocked && item.resolvedRotation == 0 && item.resolvedQuarterTurns == 0, "\(label): unlocked and unrotated")
                expect(item.resolvedStartHead == .none && item.resolvedEndHead == .arrow, "\(label): arrows keep an open head at the end only")
                expect(item.resolvedRouting == .straight && item.resolvedBrush == .marker && item.resolvedLabelPosition == 0.5, "\(label): straight, marker, label in the middle")
                expect(item.resolvedTextStyle.resolvedFill == (item.textStyle?.fill ?? .none), "\(label): text style fill resolves as before")
                expect(item.textStyle != nil || item.resolvedTextStyle == EaselTextStyle(), "\(label): no style means the default style")
                if item.textStyle == nil { expect(item.resolvedTextStyle.pointSize == 15, "\(label): default text stays 15 points") }
                expect(!item.ownsEmbeddedPage || item.kind == .browser || item.liveCapture == true, "\(label): page ownership unchanged")
            }
        }
    }

    @MainActor static func reencoding(_ name: String) throws {
        let original = try fixture(name)
        let document = try decode(name)
        let output = try encode(document)
        let leaked = try keys(output).subtracting(keys(original))
        expect(leaked.isEmpty, "\(name): re-encoding leaks keys that were not in the file: \(leaked.sorted())")
        let lost = try keys(original).subtracting(keys(output))
        expect(lost.isEmpty, "\(name): re-encoding drops keys the file had: \(lost.sorted())")
        expect(output == original, "\(name): re-encoding reproduces the saved bytes")
        let decoded = try JSONDecoder().decode(EaselDocument.self, from: output)
        expect(decoded == document, "\(name): re-encoded file decodes back equal")
        let plain = try JSONEncoder().encode(document)
        let plainKeys = try keys(plain)
        let originalKeys = try keys(original)
        expect(plainKeys == originalKeys, "\(name): the unsorted encoder writes the same keys")
        let text = String(decoding: output, as: UTF8.self)
        for key in ["shape", "fill", "fillOpacity", "strokeWidth", "strokeDash", "startHead", "endHead", "routing", "startConnection", "endConnection",
                    "labelPosition", "labelBackground", "waypoints", "brush", "pattern", "groupID", "locked", "rotation", "flipHorizontal",
                    "flipVertical", "attachedTo", "contentsHidden", "crop", "mask", "altText", "quarterTurns", "table", "language", "stamp",
                    "poster", "alignment", "textScale", "customSize", "autoWidth"] {
            let present = text.contains("\"\(key)\":")
            expect(!present || (name == "words" && ["fill", "alignment"].contains(key)), "\(name): unused field \(key) stays out of the file")
        }
    }

    @MainActor static func install(_ name: String, in directory: URL) throws -> (EaselStore, UUID, URL) {
        let document = try decode(name)
        let store = try EaselStore(directory: directory, now: { document.modifiedAt })
        let file = directory.appendingPathComponent("documents/" + document.id.uuidString.lowercased() + ".json")
        try fixture(name).write(to: file)
        for asset in Set(document.items.compactMap(\.assetID)) {
            try png.write(to: directory.appendingPathComponent("assets/" + asset))
        }
        return (store, document.id, file)
    }

    @MainActor static func storeRoundTrip(_ name: String) throws {
        try withDirectory { directory in
            let (store, id, file) = try install(name, in: directory)
            let session = try store.load(id)
            let expected = try decode(name)
            expect(session.document == expected, "\(name): the store opens a main-format file as the same document")
            try Data("{}".utf8).write(to: file)
            try session.save()
            let saved = try Data(contentsOf: file)
            let original = try fixture(name)
            expect(saved == original, "\(name): saving after opening writes the same bytes main wrote")
            let reopened = try EaselStore(directory: directory).load(id)
            expect(reopened.document == session.document, "\(name): a fresh store reopens the resaved file as the same document")
        }
    }

    @MainActor static func storeEditAndUndo() throws {
        try withDirectory { directory in
            let (store, id, file) = try install("shapes", in: directory)
            let session = try store.load(id)
            try session.perform("Nudge") { $0.items[0].frame.x += 5; $0.items[1].text = "Changed" }
            let edited = try keys(Data(contentsOf: file))
            let baseline = try keys(fixture("shapes"))
            expect(edited == baseline, "an edited main-format Easel writes no new keys")
            try session.perform("Add a note") { $0.items.append(EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 100, height: 40), text: "New")) }
            let added = try keys(Data(contentsOf: file)).subtracting(keys(fixture("shapes")))
            expect(added.allSatisfy { $0.hasPrefix("/items[7]") }, "a new plain text object adds only its own keys: \(added.sorted())")
            expect(!added.contains { ["/items[7]/shape", "/items[7]/fill", "/items[7]/locked", "/items[7]/rotation", "/items[7]/textStyle"].contains($0) }, "a new plain text object writes none of the new fields")
            try session.undo()
            try session.undo()
            let restored = try Data(contentsOf: file)
            let shapesBytes = try fixture("shapes")
            expect(restored == shapesBytes, "undoing every edit restores the exact bytes main wrote")
        }
    }

    @MainActor static func storeListing() throws {
        try withDirectory { directory in
            var expected: [UUID: Int] = [:]
            var store: EaselStore?
            for name in corpus {
                let (installed, id, _) = try install(name, in: directory)
                store = installed
                expected[id] = try decode(name).items.count
            }
            let summaries = try (store ?? EaselStore(directory: directory)).list()
            expect(summaries.count == corpus.count, "every main-format file shows up in the Easel list")
            expect(summaries.allSatisfy { expected[$0.id] == $0.itemCount }, "listed object counts match the files")
            expect(summaries.first(where: { $0.title == "Web" })?.modifiedAt == Date(timeIntervalSinceReferenceDate: 700_300_900), "listed dates match the files")
        }
    }

    @MainActor static func noteLinks() {
        for fileExtension in NoteFileKind.markdownExtensions.union(NoteFileKind.plainTextExtensions) {
            expect(EaselRichText.validLink("file:///Users/me/Notes/a.\(fileExtension)"), "Easel note links accept the .\(fileExtension) files Notes opens")
        }
        expect(!EaselRichText.validLink("file:///Users/me/Notes/a.png"), "Easel note links refuse file types Notes doesn't open")
        expect(EaselRichText.validLink("file:///Users/me/Parc%20Notes/Plan.md"), "A link to a note file is a valid text link")
        expect(EaselRichText.validLink("file:///Users/me/Notes/ideas.TXT#top"), "Note links keep fragments and any extension case")
        for refused in ["file:///etc/passwd", "file:///Applications/Parc.app", "file://server/share/a.md", "file:relative/a.md", "file:///tmp/a.md/.."] {
            expect(!EaselRichText.validLink(refused), "Non-note file link refused: \(refused)")
        }
    }
}
