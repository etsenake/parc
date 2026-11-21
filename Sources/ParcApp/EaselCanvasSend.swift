import AppKit

struct EaselSendDestination: Equatable {
    var id: UUID
    var title: String
}

@MainActor
struct EaselSendProvider {
    var destinations: () -> [EaselSendDestination]
    var session: (UUID) -> EaselSession?
    var create: () -> EaselSession?
    var sent: (_ title: String, _ count: Int, _ copied: Bool) -> Void
}

extension EaselCanvasView {
    static let maximumSendDestinations = 12

    func sendMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target != .canvas, fixedCanvasSize == nil, !session.isClosed, !isDocumentLocked,
              let provider = sendProvider else { return [] }
        let destinations = Array(provider.destinations().prefix(Self.maximumSendDestinations))
        let movable = !removableIDs(for: Set(context.items.map(\.id))).isEmpty
        func rows(copying: Bool) -> [EaselMenuRow] {
            var children = destinations.map { destination in
                EaselMenuRow(id: (copying ? "copy-to-" : "send-to-") + destination.id.uuidString,
                             title: destination.title.isEmpty ? "Untitled Easel" : destination.title, symbol: "rectangle.on.rectangle",
                             perform: guardedMenuAction { canvas in
                    guard let target = provider.session(destination.id) else { return }
                    canvas.send(to: target, copying: copying, provider: provider)
                })
            }
            children.append(EaselMenuRow(id: (copying ? "copy-to-new" : "send-to-new"), title: "New Easel", symbol: "plus",
                                         separatorBefore: !children.isEmpty, perform: guardedMenuAction { canvas in
                guard let target = provider.create() else { return }
                canvas.send(to: target, copying: copying, provider: provider)
            }))
            return children
        }
        return [EaselMenuRow(id: "send-to-easel", title: "Send to Easel", symbol: "arrow.right.square", isEnabled: movable, children: rows(copying: false)),
                EaselMenuRow(id: "copy-to-easel", title: "Copy to Easel", symbol: "plus.square.on.square", children: rows(copying: true))]
    }

    @discardableResult
    func send(to target: EaselSession, copying: Bool, provider: EaselSendProvider) -> Bool {
        cancelPointerInteraction()
        guard !session.isClosed, !session.isDeleted, target.document.id != session.fullDocument.id, !target.document.isLocked,
              finishEditing() else { return false }
        let ids = copying ? selection : removableIDs(for: selection)
        guard !ids.isEmpty else { return false }
        do {
            let document = session.document
            var assets: [String: Data] = [:]
            for id in EaselClipboardPayload.assetIDs(of: ids, in: document) { assets[id] = try session.assetData(id) }
            guard let payload = try EaselClipboardPayload.capturing(ids, in: document, assets: assets) else { return false }
            var imported: [String: String] = [:]
            var created: [String] = []
            do {
                for (original, data) in payload.assets.sorted(by: { $0.key < $1.key }) {
                    let id = try target.importAsset(data, type: EaselAssetType.of(assetID: original) ?? .png)
                    imported[original] = id
                    created.append(id)
                }
                let items = payload.items.map { item -> EaselItem in
                    var copy = item
                    copy.assetID = item.assetID.flatMap { imported[$0] }
                    return copy
                }
                guard let landed = EaselBoardSend.landing(items, in: target.document) else {
                    target.discardUnusedAssets(created)
                    return false
                }
                try target.perform(copying ? "Copy Here" : "Send Here") { $0 = landed }
            } catch {
                target.discardUnusedAssets(created)
                throw error
            }
            if !copying {
                let doomed = removableIDs(for: ids)
                let next = EaselArrange.dissolvingSingletonGroups(EaselDependents.removing(doomed, from: session.document))
                let removed = withObjectMotion(.vanish) { commit("Send to Easel", { $0 = next }) }
                guard removed else {
                    try? target.retractLastStep()
                    target.discardUnusedAssets(created)
                    return false
                }
                selection.subtract(doomed)
            }
            provider.sent(target.document.title, payload.items.count, copying)
            return true
        } catch {
            onError?(error)
            return false
        }
    }
}
