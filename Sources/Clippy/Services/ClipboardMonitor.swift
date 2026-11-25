import AppKit
import ClippyCore

/// Watches the general pasteboard and records every new copy with all its formats.
@MainActor
final class ClipboardMonitor {
    private let repo: ClipRepository
    private let settings: AppSettings
    private let onSaved: () -> Void
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    /// Change counts produced by Clippy itself (pasting from history, plain paste, restore).
    private var ownChangeCounts: Set<Int> = []
    private var timer: Timer?

    init(repo: ClipRepository, settings: AppSettings, onSaved: @escaping () -> Void) {
        self.repo = repo
        self.settings = settings
        self.onSaved = onSaved
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
        timer?.tolerance = 0.1
    }

    /// Call after Clippy writes to the pasteboard so that write isn't recorded as a new copy.
    func ignore(changeCount: Int) {
        ownChangeCounts.insert(changeCount)
        if changeCount > lastChangeCount { lastChangeCount = changeCount }
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if ownChangeCounts.remove(count) != nil { return }
        if settings.ignoreSecrets && PasteboardCodec.hasSecretMarker(pasteboard) { return }

        // Reading must happen on the main thread (pasteboard promises); analysis and storage don't.
        guard let snapshot = PasteboardCodec.read(pasteboard) else { return }
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let limits = settings.limits
        let repo = repo
        let playSound = settings.playSound

        Task.detached(priority: .utility) {
            guard let clip = PasteboardCodec.analyze(snapshot) else { return }
            do {
                try repo.save(clip, sourceApp: sourceApp, limits: limits)
            } catch {
                NSLog("Clippy: failed to save clip: \(error)")
                return
            }
            await MainActor.run {
                if playSound { NSSound(named: "Pop")?.play() }
                self.onSaved()
            }
        }
    }
}
