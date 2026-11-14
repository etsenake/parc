import CoreGraphics

enum CommandBarResidentLayout {
    static let maximumWidth: CGFloat = 765
    static let restHeight: CGFloat = 64
    static let rowHeight: CGFloat = 50
    static let visibleRows = 5
    static let resultChrome: CGFloat = 76
    static let restingToken = "resident-rest"

    static func rests(query: String, scoped: Bool, scopeInvalidated: Bool) -> Bool {
        query.isEmpty && !scoped && !scopeInvalidated
    }

    static func expands(resultCount: Int, actionsScope: Bool, websiteScoped: Bool, inputIsEmpty: Bool,
                        scopeInvalidated: Bool, hasError: Bool) -> Bool {
        if actionsScope || scopeInvalidated { return true }
        if websiteScoped { return !(inputIsEmpty && resultCount == 0 && !hasError) }
        return resultCount > 0
    }

    static func height(expanded: Bool, rows: Int, banner: CGFloat = 0) -> CGFloat {
        guard expanded else { return restHeight + banner }
        return resultChrome + CGFloat(min(max(rows, 1), visibleRows)) * rowHeight + banner
    }

    static func surfaceFrame(in slot: CGRect, height: CGFloat) -> CGRect {
        let width = max(0, min(slot.width, maximumWidth))
        let fitted = slot.height >= restHeight ? min(height, slot.height) : restHeight
        return CGRect(x: slot.midX - width / 2, y: slot.maxY - fitted, width: width, height: fitted)
    }
}
