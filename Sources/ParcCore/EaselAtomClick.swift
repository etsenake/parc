import Foundation

enum EaselAtomClick {
    static func opens(_ kind: EaselRichText.Inline.Kind) -> Bool {
        kind == .date || kind == .equation
    }

    static func isUpright(_ item: EaselItem) -> Bool {
        (item.rotation ?? 0) == 0 && item.flipHorizontal != true && item.flipVertical != true
    }

    static func carriesAtom(_ item: EaselItem) -> Bool {
        guard item.kind.holdsText || item.kind == .arrow, !item.text.isEmpty else { return false }
        return item.richText?.runs.contains { $0.attributes.inline.map { opens($0.kind) } == true } == true
    }

    static func allowsClick(on item: EaselItem, selection: Set<UUID>, editable: Bool, clickCount: Int, plain: Bool) -> Bool {
        editable && plain && clickCount == 1 && !item.isLocked && selection == [item.id] && isUpright(item) && carriesAtom(item)
    }
}
