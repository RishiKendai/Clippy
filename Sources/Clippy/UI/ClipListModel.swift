import AppKit
import ClippyCore
import SwiftUI

/// State behind the popover: search, the two lists and the selection.
@MainActor
final class ClipListModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { reload() } } }
    @Published private(set) var history: [ClipSummary] = []
    @Published private(set) var pinned: [ClipSummary] = []
    @Published var selectedID: Int64?
    /// Bumped to move focus into the search field (type-to-search). The field is NOT focused on open.
    @Published private(set) var focusToken = 0
    /// True while there are no clips at all (vs. a search with no matches).
    @Published private(set) var isEmptyStore = true
    /// Tallest the popover content may be on the current screen (set each time it opens).
    @Published var maxContentHeight: CGFloat = 800
    /// The pinned clip being dragged to a new position, if any.
    @Published private(set) var draggingID: Int64?

    /// Pinned clips can be rearranged only when the whole list is visible (no search).
    var canReorderPinned: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && pinned.count > 1 }

    let repo: ClipRepository
    let settings: AppSettings

    /// Wired by the AppDelegate.
    var onPaste: (Int64, Bool) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    /// Hover preview: called with the hovered clip and its row frame (SwiftUI global coords), or nil to hide.
    var onPreview: (ClipSummary?, CGRect) -> Void = { _, _ in }

    private var reloadGeneration = 0

    init(repo: ClipRepository, settings: AppSettings) {
        self.repo = repo
        self.settings = settings
        reload()
    }

    var visibleIDs: [Int64] { history.map(\.id) + pinned.map(\.id) }

    /// The row under the mouse, if any (drives the hover preview).
    private(set) var hoveredID: Int64?

    /// Row hover: selects the row and shows its preview; leaving hides it.
    /// Also called when a hovered row moves (scrolling), to keep the preview aligned.
    func hover(_ clip: ClipSummary, inside: Bool, frame: CGRect) {
        if draggingID != nil { return }
        if inside {
            hoveredID = clip.id
            if selectedID != clip.id { selectedID = clip.id }
            onPreview(clip, frame)
        } else if hoveredID == clip.id {
            hoveredID = nil
            onPreview(nil, frame)
        }
    }

    func reload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        let q = query
        let repo = repo
        Task {
            let result = await Task.detached { () -> (h: [ClipSummary], p: [ClipSummary], empty: Bool)? in
                guard let lists = try? repo.list(query: q) else { return nil }
                let counts = try? repo.counts()
                return (lists.history, lists.pinned, (counts?.history ?? 0) + (counts?.pinned ?? 0) == 0)
            }.value
            guard generation == reloadGeneration, let result else { return }
            history = result.h
            // Don't yank the Pinned rows out from under an ongoing drag.
            if draggingID == nil { pinned = result.p }
            isEmptyStore = result.empty
            if let id = selectedID, visibleIDs.contains(id) { return }
            selectedID = visibleIDs.first
        }
    }

    func prepareForOpen() {
        draggingID = nil
        query = ""
        selectedID = visibleIDs.first
        reload()
    }

    func focusSearch() { focusToken += 1 }

    func moveSelection(_ delta: Int) {
        let ids = visibleIDs
        guard !ids.isEmpty else { return }
        guard let current = selectedID, let i = ids.firstIndex(of: current) else {
            selectedID = ids.first
            return
        }
        selectedID = ids[max(0, min(ids.count - 1, i + delta))]
    }

    // MARK: Actions

    func use(_ id: Int64, plain: Bool = false) {
        onPreview(nil, .zero)
        onPaste(id, plain)
    }

    func togglePin(_ id: Int64) {
        let nowPinned = !(pinned.contains { $0.id == id })
        let limits = settings.limits
        let repo = repo
        Task {
            await Task.detached { try? repo.setPinned(id, nowPinned, limits: limits) }.value
            reload()
        }
    }

    // MARK: Pinned order

    /// Moves a pinned clip up (-1) or down (+1) one place.
    func movePinned(_ id: Int64, by delta: Int) {
        guard canReorderPinned, let from = pinned.firstIndex(where: { $0.id == id }) else { return }
        let to = from + delta
        guard pinned.indices.contains(to) else { return }
        animateReorder { pinned.swapAt(from, to) }
        persistPinnedOrder()
    }

    func beginDrag(_ id: Int64) {
        draggingID = id
        onPreview(nil, .zero)
    }

    /// Swaps two pinned rows during a drag (saved when the drag ends). `alongside` runs in the
    /// same animation so the dragged row stays under the mouse.
    func swapPinned(_ i: Int, _ j: Int, alongside: () -> Void) {
        animateReorder {
            pinned.swapAt(i, j)
            alongside()
        }
    }

    func endDrag() {
        guard draggingID != nil else { return }
        draggingID = nil
        persistPinnedOrder()
    }

    private func animateReorder(_ change: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.15), change)
        }
    }

    private var orderWrite: Task<Void, Never>?

    /// Saves the current Pinned order. Writes are chained so a fast drag can't save out of order.
    private func persistPinnedOrder() {
        let ids = pinned.map(\.id)
        let repo = repo
        let previous = orderWrite
        orderWrite = Task.detached {
            await previous?.value
            try? repo.reorderPinned(ids)
        }
    }

    func delete(_ id: Int64) {
        onPreview(nil, .zero)
        let ids = visibleIDs
        if selectedID == id, let i = ids.firstIndex(of: id) {
            selectedID = i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil)
        }
        let repo = repo
        Task {
            await Task.detached { try? repo.delete(id) }.value
            reload()
        }
    }

    func clearSearchOrClose(close: () -> Void) {
        if query.isEmpty { close() } else { query = "" }
    }
}

/// Decoded thumbnails, so image rows don't re-decode PNG data on every render.
@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSNumber, NSImage>()

    static func image(for clip: ClipSummary) -> NSImage? {
        let key = NSNumber(value: clip.id)
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = clip.thumbnail, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
