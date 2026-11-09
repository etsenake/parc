import AppKit
import SwiftUI

/// The import result keeps each source profile's tree and selection separate.
/// A folder's circle selects its subtree; its icon/title only expands it.
struct OnboardingImportBookmarksPicker: View {
    struct Page: Identifiable {
        let id: UUID
        let title: String
        let selection: BrowserImportSelection
        /// Whether ticks can change. A page the menu window already added
        /// shows as disabled, but its folders still open.
        let enabled: Bool
        let expandable: Bool
        let select: (String?) -> Void
        let expand: (String) -> Void
    }
    let pages: [Page]
    let selectionColor: NSColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(pages) { page in
                        if pages.count > 1 {
                            Text(page.title).font(.headline).padding(.bottom, 8)
                        }
                        contents(page)
                    }
                }.padding(10)
            }
            .textSelection(.disabled)
            .overlay(BookmarkArrowCursor().allowsHitTesting(false))
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: 1))
            // BookmarksSelectionView forces this white surface to light; the
            // surrounding setup card keeps its own appearance and theme.
            .environment(\.colorScheme, .light)
        }
        // The setup parent supplies the original 384 × 430 frame. The scroll view
        // fills it; source-row padding does not belong around this surface.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose bookmarks to bring to Parc")
    }

    @ViewBuilder private func contents(_ page: Page) -> some View {
        Button { page.select(nil) } label: {
            HStack {
                selectionMark(page.selection.allSelected)
                Text("Select All").font(.title3).bold().foregroundColor(Color(nsColor: OnboardingBookmarkPalette.stroke))
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!page.enabled || page.selection.roots.isEmpty)
        .accessibilityLabel("Select all bookmarks from \(page.title)")
        .accessibilityValue(page.selection.allSelected ? "Selected" : "Not selected")
        .padding(.bottom, 12)
        ForEach(page.selection.roots) { item in
            OnboardingImportBookmarkBranch(item: item, depth: 0, page: page, selectionColor: selectionColor,
                                           reduceMotion: reduceMotion)
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .imageScale(.large).foregroundColor(Color(nsColor: selectionColor)).accessibilityHidden(true)
    }
}

private struct OnboardingImportBookmarkBranch: View {
    let item: BrowserImportBookmark
    let depth: Int
    let page: OnboardingImportBookmarksPicker.Page
    let selectionColor: NSColor
    let reduceMotion: Bool
    private var expanded: Bool { page.selection.expanded.contains(item.id) }
    private var selected: Bool { page.selection.selected.contains(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { page.select(item.id) } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large).foregroundColor(Color(nsColor: selectionColor))
                }
                .buttonStyle(.plain)
                .disabled(!page.enabled)
                .accessibilityLabel("Select \(item.title)")
                .accessibilityValue(selected ? "Selected" : "Not selected")
                Button {
                    if item.url == nil {
                        withAnimation(reduceMotion ? nil : .default) { page.expand(item.id) }
                    } else { page.select(item.id) }
                } label: {
                    HStack {
                        if item.url == nil {
                            OnboardingBookmarkFolderIcon(expanded: expanded)
                                .frame(width: 16, height: 16).accessibilityHidden(true)
                        }
                        Text(item.title).font(.title3).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(depth) * 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.url == nil ? !page.expandable : !page.enabled)
                .accessibilityLabel(item.url == nil ? "\(expanded ? "Collapse" : "Expand") \(item.title)" : item.title)
                .accessibilityValue(item.url == nil ? (expanded ? "Expanded" : "Collapsed") : (selected ? "Selected" : "Not selected"))
            }
            .padding(.bottom, 12)
            if expanded {
                ForEach(item.children) { child in
                    // Type erasure terminates the recursive View type; source IDs
                    // remain the row identity and no collapsed descendants render.
                    AnyView(OnboardingImportBookmarkBranch(item: child, depth: depth + 1, page: page,
                        selectionColor: selectionColor, reduceMotion: reduceMotion))
                }
                .transition(reduceMotion ? .identity : .move(edge: .top))
            }
        }
    }
}

/// Own the cursor without intercepting row clicks or scroll-wheel events.
/// This also covers disabled rows on macOS 13 and 14.
private struct BookmarkArrowCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ArrowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class ArrowView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
        override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
            super.updateTrackingAreas()
        }
    }
}
