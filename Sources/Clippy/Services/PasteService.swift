import AppKit
import ApplicationServices
import ClippyCore

/// Puts clips back on the pasteboard and pastes them where the user's cursor was.
/// No notifications: the paste itself is the feedback.
@MainActor
final class PasteService {
    private let repo: ClipRepository
    private let settings: AppSettings
    private let monitor: ClipboardMonitor
    private let pasteboard = NSPasteboard.general

    /// The app that was frontmost before the popover opened: where pastes go.
    var targetApp: NSRunningApplication?
    /// Called when a paste can't be typed because Accessibility isn't granted.
    var onPermissionMissing: () -> Void = {}

    init(repo: ClipRepository, settings: AppSettings, monitor: ClipboardMonitor) {
        self.repo = repo
        self.settings = settings
        self.monitor = monitor
    }

    /// Pastes a stored clip, as-is (every stored format) or as plain text, into the
    /// previously active app at its cursor. With "Paste automatically on click" off, it only copies.
    func paste(clipID: Int64, plain: Bool) async {
        let repo = repo
        let loaded: (PasteboardSnapshot, ClipSummary?)? = await Task.detached {
            guard let snap = try? repo.snapshot(for: clipID), !snap.isEmpty else { return nil }
            return (snap, try? repo.summary(for: clipID))
        }.value
        guard let (snapshot, summary) = loaded else { return }

        let change: Int
        if plain {
            let text = summary?.plainText ?? PasteboardCodec.plainText(from: snapshot) ?? ""
            guard !text.isEmpty else { return }
            change = PasteboardCodec.writePlain(text, to: pasteboard)
        } else {
            change = PasteboardCodec.write(snapshot, to: pasteboard)
        }
        monitor.ignore(changeCount: change)
        try? repo.markUsed(clipID)

        await returnFocus(to: targetApp)
        let front = NSWorkspace.shared.frontmostApplication
        NSLog("Clippy paste: target=\(targetApp?.bundleIdentifier ?? "nil") frontmost=\(front?.bundleIdentifier ?? "nil") autoPaste=\(settings.autoPaste) ax=\(AXIsProcessTrusted()) postEvent=\(CGPreflightPostEventAccess())")
        guard settings.autoPaste else { return }
        guard Permissions.accessibilityGranted else {
            // Synthesizing ⌘V needs Accessibility. The clip is on the clipboard meanwhile;
            // take the user to the switch that fixes it rather than failing silently.
            Permissions.requestAccessibility()
            onPermissionMissing()
            return
        }
        Self.postCommandV()
    }

    /// Gives focus back to the app the user was in, so its focused text field receives the paste.
    private func returnFocus(to target: NSRunningApplication?) async {
        // Hiding an accessory app hands activation back to the previously active app and its key window.
        NSApp.hide(nil)
        if let target, !target.isTerminated, !target.isActive {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
        // Wait (briefly) until the target is really frontmost before typing into it.
        for _ in 0..<20 {
            if let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            if target == nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        // Let the target's key window and text field become first responder again.
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// System-wide ⌘⇧V: paste the current clipboard as plain text, then put the original
    /// (formatted) contents back so a normal ⌘V still pastes them as-is.
    func pasteClipboardAsPlainText() async {
        guard Permissions.accessibilityGranted else {
            Permissions.requestAccessibility()
            return
        }
        guard let original = PasteboardCodec.read(pasteboard),
              let text = PasteboardCodec.analyze(original)?.plainText ?? PasteboardCodec.plainText(from: original),
              !text.isEmpty
        else {
            // Nothing textual (e.g. an image): fall back to a normal paste.
            Self.postCommandV()
            return
        }
        monitor.ignore(changeCount: PasteboardCodec.writePlain(text, to: pasteboard))
        try? await Task.sleep(for: .milliseconds(30))
        Self.postCommandV()
        // Give the target app time to read the pasteboard before restoring.
        try? await Task.sleep(for: .milliseconds(400))
        monitor.ignore(changeCount: PasteboardCodec.write(original, to: pasteboard))
    }

    /// Synthesizes ⌘V. The flags are set explicitly, so a Shift key still held from
    /// the ⌘⇧V hotkey doesn't turn it into ⇧⌘V.
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.v), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.v), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
