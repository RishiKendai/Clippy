import ClippyCore
import SwiftUI

/// The menu bar popover (DESIGN.md §4): search, History, Pinned (when non-empty), footer.
struct PopoverView: View {
    @ObservedObject var model: ClipListModel
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = PopoverTheme(scheme)
        let heights = listHeights()
        VStack(alignment: .leading, spacing: 0) {
            SearchField(model: model, theme: theme)

            SectionHeader(title: "History", count: countLabel(model.history.count), theme: theme)
                .padding(.top, 12)
            if model.history.isEmpty {
                Text(model.query.trimmingCharacters(in: .whitespaces).isEmpty ? "Copy something to get started" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ClipList(clips: model.history, maxHeight: heights.history, reorderable: false, model: model, theme: theme)
            }

            if !model.pinned.isEmpty {
                theme.divider.frame(height: 1).padding(.horizontal, 6).padding(.top, 8)
                SectionHeader(title: "Pinned", count: "\(model.pinned.count)", theme: theme)
                    .padding(.top, 10)
                ClipList(clips: model.pinned, maxHeight: heights.pinned, reorderable: model.canReorderPinned, model: model, theme: theme)
            }

            theme.divider.frame(height: 1).padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
            MenuRow(title: "Settings…", shortcut: "⌘,", theme: theme, action: model.onOpenSettings)
            MenuRow(title: "Quit Clippy", shortcut: "⌘Q", theme: theme, action: model.onQuit)
        }
        .padding(8)
        .frame(width: 380)
        // Light: white-based glass over the popover's native material. Dark: the native glass as is.
        .background(scheme == .light ? Color.white.opacity(0.55) : Color.clear)
    }

    private func countLabel(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    /// Each list shows its configured number of rows, then scrolls. If both together don't fit
    /// on the screen, they shrink: the shorter list keeps its height when it fits in half the
    /// space, otherwise each gets half.
    private func listHeights() -> (history: CGFloat, pinned: CGFloat) {
        func wanted(_ clips: [ClipSummary], _ rows: Int) -> CGFloat {
            clips.prefix(rows).reduce(0) { $0 + ClipRow.height(for: $1) }
        }
        let h = wanted(model.history, settings.historyRows)
        let p = wanted(model.pinned, settings.pinnedRows)
        // Search, headers, dividers, Settings/Quit rows and padding.
        let chrome: CGFloat = model.pinned.isEmpty ? 150 : 190
        let budget = max(model.maxContentHeight - chrome, 160)
        guard h + p > budget else { return (h, p) }
        let half = budget / 2
        if h <= half { return (h, budget - h) }
        if p <= half { return (budget - p, p) }
        return (half, half)
    }
}

private struct SearchField: View {
    @ObservedObject var model: ClipListModel
    let theme: PopoverTheme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.sub)
                .accessibilityHidden(true)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .focused($focused)
                .accessibilityLabel("Search clipboard history")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.sub)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.field))
        .onChange(of: model.focusToken) { focused = true }
    }
}

private struct SectionHeader: View {
    let title: String
    let count: String
    let theme: PopoverTheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(count).font(.system(size: 11).monospacedDigit())
        }
        .foregroundStyle(theme.sub)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

/// A list that grows with its rows up to `maxHeight`, then scrolls.
private struct ClipList: View {
    let clips: [ClipSummary]
    let maxHeight: CGFloat
    /// Pinned list: rows can be dragged into a new order.
    let reorderable: Bool
    @ObservedObject var model: ClipListModel
    let theme: PopoverTheme

    /// Vertical mouse travel since the drag started.
    @ViewState private var dragTranslation: CGFloat = 0
    /// Height of the rows the dragged row has already swapped past (signed).
    @ViewState private var dragShift: CGFloat = 0

    var body: some View {
        let contentHeight = clips.reduce(CGFloat(0)) { $0 + ClipRow.height(for: $1) }
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(clips) { clip in
                        row(clip).id(clip.id)
                    }
                }
            }
            .scrollIndicators(contentHeight > maxHeight + 0.5 ? .automatic : .never)
            .frame(height: min(contentHeight, maxHeight))
            .onChange(of: model.selectedID) { _, id in
                if let id, model.draggingID == nil, clips.contains(where: { $0.id == id }) {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    @ViewBuilder private func row(_ clip: ClipSummary) -> some View {
        let base = ClipRow(clip: clip, selected: model.selectedID == clip.id, theme: theme, model: model)
        if reorderable {
            let dragging = model.draggingID == clip.id
            base
                .background(RoundedRectangle(cornerRadius: 6).fill(dragging ? theme.hover : .clear))
                .shadow(color: .black.opacity(dragging ? 0.18 : 0), radius: 6, y: 2)
                .offset(y: dragging ? dragTranslation - dragShift : 0)
                .zIndex(dragging ? 1 : 0)
                // High priority so a drag wins over the row's click; a click (no movement) still pastes.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { value in dragChanged(clip, value.translation.height) }
                        .onEnded { _ in dragEnded() }
                )
        } else {
            base
        }
    }

    /// Live reorder: once the row has moved past half of its neighbour, they swap places.
    private func dragChanged(_ clip: ClipSummary, _ translation: CGFloat) {
        if model.draggingID != clip.id {
            model.beginDrag(clip.id)
            dragShift = 0
        }
        dragTranslation = translation
        while let index = model.pinned.firstIndex(where: { $0.id == clip.id }) {
            let offset = dragTranslation - dragShift
            if offset > 0, index + 1 < model.pinned.count,
               offset > ClipRow.height(for: model.pinned[index + 1]) / 2 {
                let h = ClipRow.height(for: model.pinned[index + 1])
                model.swapPinned(index, index + 1) { dragShift += h }
            } else if offset < 0, index > 0,
                      -offset > ClipRow.height(for: model.pinned[index - 1]) / 2 {
                let h = ClipRow.height(for: model.pinned[index - 1])
                model.swapPinned(index, index - 1) { dragShift -= h }
            } else {
                break
            }
        }
    }

    private func dragEnded() {
        model.endDrag()
        dragTranslation = 0
        dragShift = 0
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String
    let theme: PopoverTheme
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(theme.text)
                Spacer()
                Text(shortcut).foregroundStyle(theme.sub)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
