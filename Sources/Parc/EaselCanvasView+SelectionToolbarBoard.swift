import AppKit
import ParcCore

extension EaselCanvasView {
    private var selectionToolbarReady: Bool { editor?.hasMarkedText() != true && !session.isClosed && !session.isDeleted }

    func selectionToolbarBoardSupports(_ control: EaselToolbarControl, selected: [EaselItem]) -> Bool? {
        switch control {
        case .arrange, .tidyUp, .group, .createSection, .lock: return selected.count > 1
        case .unlock: return selected.allSatisfy(\.isLocked)
        case .stickyShape: return selected.allSatisfy { $0.kind == .sticky }
        case .sectionTitle: return selected.count == 1 && selected.first?.kind == .section
        case .crop, .replaceImage: return selectedImage != nil
        case .imageMask: return selectedImage != nil && hasImageChrome
        case .altText:
            return hasImageChrome && selected.count == 1 && selected.first.map { EaselToolbarSubject($0) == .image } == true
        default: return selectionToolbarStyleSupports(control, selected: selected)
        }
    }

    func selectionToolbarBoardButton(_ control: EaselToolbarControl, selected: [EaselItem]) -> EaselToolbarButtonModel? {
        let document = session.document, ids = selection, ready = selectionToolbarReady
        switch control {
        case .arrange:
            let enabled = EaselArrange.canAlign(ids, in: document) || EaselArrange.canDistribute(ids, in: document)
            return .init(control: control, face: .symbol(EaselAlignment.left.symbol), name: "Align and distribute",
                         isEnabled: ready && enabled, opens: .menu, showsDisclosure: true)
        case .tidyUp:
            return .init(control: control, face: .symbol("square.grid.2x2"), name: "Tidy up",
                         isEnabled: ready && EaselArrange.canTidy(ids, in: document))
        case .group:
            let ungroups = selectionToolbarUngroups
            return .init(control: control, face: .symbol(ungroups ? "rectangle.3.group.fill" : "rectangle.3.group"),
                         name: ungroups ? "Ungroup" : "Group", shortcut: ungroups ? "⇧⌘G" : "⌘G",
                         isEnabled: ready && (ungroups || EaselArrange.canGroup(ids, in: document)))
        case .createSection:
            return .init(control: control, face: .symbol("rectangle.dashed"), name: "Create section", isEnabled: ready)
        case .lock:
            let locks = EaselArrange.shouldLock(ids, in: document)
            return .init(control: control, face: .symbol(locks ? "lock" : "lock.open"), name: locks ? "Lock" : "Unlock",
                         shortcut: "⇧⌘L", isEnabled: ready)
        case .unlock:
            return .init(control: control, face: .symbolAndText("lock.fill", "Locked"), name: "Unlock", shortcut: "⇧⌘L",
                         isEnabled: ready, opens: .menu, showsDisclosure: true)
        case .stickyShape:
            return .init(control: control, face: .symbol("rectangle"), name: "Wide sticky", isChecked: isStickyWide, isEnabled: ready)
        case .sectionTitle:
            return .init(control: control, face: .symbolAndText("pencil", "Rename"), name: "Rename section", isEnabled: ready)
        case .crop:
            return .init(control: control, face: .symbol("crop"), name: "Crop", isEnabled: ready && canEditSelectedImage)
        case .imageMask:
            return .init(control: control, face: .symbol("circle.square"), name: "Mask", isEnabled: ready && canEditSelectedImage,
                         showsDisclosure: true)
        case .replaceImage:
            return .init(control: control, face: .symbol("photo.on.rectangle"), name: "Replace image",
                         isEnabled: ready && canEditSelectedImage)
        case .altText:
            let item = selected.first
            return .init(control: control, face: .symbolAndText("text.below.photo", "Alt text"), name: "Alt text",
                         isEnabled: ready && item?.isLocked == false)
        default:
            return selectionToolbarStyleButton(control, selected: selected)
        }
    }

    func selectionToolbarBoardMenu(_ control: EaselToolbarControl) -> [EaselToolbarMenuEntry]? {
        let document = session.document, ids = selection, ready = selectionToolbarReady
        switch control {
        case .arrange:
            let aligns = ready && EaselArrange.canAlign(ids, in: document)
            let distributes = ready && EaselArrange.canDistribute(ids, in: document)
            let alignments = EaselAlignment.allCases.map {
                EaselToolbarMenuEntry(id: "align." + $0.rawValue, title: $0.title, symbol: $0.symbol, isEnabled: aligns)
            }
            let spacings = EaselAxis.allCases.enumerated().map { index, axis in
                EaselToolbarMenuEntry(id: "distribute." + axis.rawValue, title: axis.distributeTitle, symbol: axis.symbol,
                                      isEnabled: distributes, separatorBefore: index == 0)
            }
            return alignments + spacings
        case .unlock:
            let group = EaselSelectionToolbarPlan.unlocksGroup(session.document.items.filter { ids.contains($0.id) })
            return [EaselToolbarMenuEntry(id: "unlock", title: group ? "Unlock Group" : "Unlock", symbol: "lock.open", shortcut: "⇧⌘L",
                                          isEnabled: ready)]
        case .more:
            return selectionToolbarMoreMenu()
        default:
            return selectionToolbarStyleMenu(control)
        }
    }

    private func selectionToolbarMoreMenu() -> [EaselToolbarMenuEntry] {
        let document = session.document, ids = selection, ready = selectionToolbarReady
        let selected = document.items.filter { ids.contains($0.id) }
        let allLocked = !selected.isEmpty && selected.allSatisfy(\.isLocked)
        let sections = selectedSections
        var entries: [EaselToolbarMenuEntry] = equationToolbarEntries(selected, ready: ready)
        if !sections.isEmpty, !allLocked {
            let hidden = sections.allSatisfy { $0.contentsHidden == true }
            entries.append(EaselToolbarMenuEntry(id: "section.lockAll", title: "Lock All", symbol: "lock", isEnabled: ready))
            entries.append(EaselToolbarMenuEntry(id: "section.lockBackground", title: "Lock Background Only", symbol: "lock.rectangle",
                                                 isEnabled: ready))
            entries.append(EaselToolbarMenuEntry(id: "section.hide", title: hidden ? "Show Contents" : "Hide Contents",
                                                 symbol: hidden ? "eye" : "eye.slash", isEnabled: ready))
        }
        let layers = ready && EaselArrange.canMoveLayer(ids, in: document)
        for (index, move) in EaselLayerMove.allCases.enumerated() {
            entries.append(EaselToolbarMenuEntry(id: "layer." + move.rawValue, title: move.title, symbol: move.symbol, shortcut: move.shortcut,
                                                 isEnabled: layers, separatorBefore: index == 0 && !entries.isEmpty))
        }
        let flips = ready && EaselRotation.canFlip(selected), turns = ready && EaselRotation.canRotate(selected)
        if EaselRotation.canFlip(selected) || EaselRotation.canRotate(selected) {
            entries.append(EaselToolbarMenuEntry(id: "flip.horizontal", title: "Flip Horizontal",
                                                 symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", shortcut: "⇧H",
                                                 isEnabled: flips, separatorBefore: true))
            entries.append(EaselToolbarMenuEntry(id: "flip.vertical", title: "Flip Vertical",
                                                 symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", shortcut: "⇧V",
                                                 isEnabled: flips))
            entries.append(EaselToolbarMenuEntry(id: "rotate.left", title: "Rotate 90° Left", symbol: "rotate.left", isEnabled: turns))
            entries.append(EaselToolbarMenuEntry(id: "rotate.right", title: "Rotate 90° Right", symbol: "rotate.right", isEnabled: turns))
        }
        entries += mediaToolbarEntries(ready: ready && !allLocked)
        entries.append(EaselToolbarMenuEntry(id: "duplicate", title: "Duplicate", symbol: "plus.square.on.square", shortcut: "⌘D",
                                             isEnabled: ready, separatorBefore: true))
        entries.append(EaselToolbarMenuEntry(id: "copy-image", title: "Copy as Image", symbol: "photo.on.rectangle", isEnabled: ready))
        if selected.count == 1, !allLocked {
            entries.append(EaselToolbarMenuEntry(id: "lock", title: "Lock", symbol: "lock", shortcut: "⇧⌘L", isEnabled: ready))
        }
        if !sections.isEmpty, !allLocked {
            entries.append(EaselToolbarMenuEntry(id: "section.deleteKeepingContents", title: "Delete Section Only",
                                                 symbol: "rectangle.dashed", isEnabled: ready, separatorBefore: true))
        }
        entries.append(EaselToolbarMenuEntry(id: "delete", title: "Delete", symbol: "trash", shortcut: "⌫", isEnabled: ready && !allLocked,
                                             isDestructive: true, separatorBefore: sections.isEmpty || allLocked))
        return entries
    }

    func performSelectionToolbarBoard(_ control: EaselToolbarControl) -> Bool? {
        guard selectionToolbarReady else { return false }
        switch control {
        case .tidyUp: return tidyUpSelection()
        case .group: return selectionToolbarUngroups ? ungroupSelection() : groupSelection()
        case .createSection: return createSection(from: selection)
        case .lock: return toggleLock()
        case .stickyShape: return setStickyWide(!isStickyWide)
        case .sectionTitle:
            guard let section = selectedSections.first, selection.count == 1 else { return false }
            beginSectionRename(section.id)
            return true
        case .crop: return beginImageCrop()
        case .replaceImage:
            guard canEditSelectedImage else { return false }
            if let item = selectedImage, performHostedAction(.replace, on: item.id) { return true }
            chooseReplacementImage()
            return true
        case .altText:
            editImageAltText()
            return true
        default: return nil
        }
    }

    func performSelectionToolbarBoard(_ control: EaselToolbarControl, anchor: NSView?) -> Bool? {
        guard control == .imageMask else { return performSelectionToolbarBoard(control) }
        guard selectionToolbarReady, canEditSelectedImage, hasImageChrome else { return false }
        showImageMaskPicker(anchor: anchor.map { convert($0.bounds, from: $0) })
        return true
    }

    func performSelectionToolbarBoardMenu(_ control: EaselToolbarControl, entry id: String) -> Bool? {
        guard selectionToolbarReady else { return false }
        switch control {
        case .arrange:
            if id.hasPrefix("align."), let alignment = EaselAlignment(rawValue: String(id.dropFirst("align.".count))) {
                return alignSelection(alignment)
            }
            if id.hasPrefix("distribute."), let axis = EaselAxis(rawValue: String(id.dropFirst("distribute.".count))) {
                return distributeSelection(axis)
            }
            return false
        case .unlock:
            guard id == "unlock" else { return false }
            let ids = selection.union(EaselBoardObjects.lockTargets(selection, all: true, in: session.document))
            return setLock(false, ids: ids)
        case .more:
            return performSelectionToolbarMore(id)
        default:
            return performSelectionToolbarStyleMenu(control, entry: id)
        }
    }

    private func performSelectionToolbarMore(_ id: String) -> Bool {
        if let equation = performEquationToolbar(id) { return equation }
        if id.hasPrefix("layer."), let move = EaselLayerMove(rawValue: String(id.dropFirst("layer.".count))) { return moveLayer(move) }
        if let handled = performMediaToolbarEntry(id) { return handled }
        switch id {
        case "duplicate": return duplicateSelection()
        case "copy-image": return copySelectionAsImage()
        case "flip.horizontal": return flipSelection(horizontal: true)
        case "flip.vertical": return flipSelection(horizontal: false)
        case "rotate.left": return rotateSelection(by: -90)
        case "rotate.right": return rotateSelection(by: 90)
        case "lock": return toggleLock()
        case "delete":
            deleteObjects(nil)
            return true
        case "section.lockAll": return lockSections(all: true)
        case "section.lockBackground": return lockSections(all: false)
        case "section.hide": return setSectionContentsHidden(!selectedSections.allSatisfy { $0.contentsHidden == true })
        case "section.deleteKeepingContents": return deleteSectionsKeepingContents()
        default: return false
        }
    }

    private var selectionToolbarUngroups: Bool {
        let document = session.document
        return EaselArrange.canUngroup(selection, in: document) && !EaselArrange.canGroup(selection, in: document)
    }
}
