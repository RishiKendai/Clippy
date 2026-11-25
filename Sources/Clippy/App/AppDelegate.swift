import AppKit
import ApplicationServices
import Carbon
import ClippyCore
import Combine

/// Wires the repository, clipboard monitor, popover, paste service, hotkeys and timers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var repo: ClipRepository!
    private var model: ClipListModel!
    private var statusBar: StatusBarController!
    private var monitor: ClipboardMonitor!
    private var paste: PasteService!
    private var settingsWindow: SettingsWindowController!
    private var retentionTimer: Timer?
    private let uninstaller = Uninstaller()
    private var cancellables: Set<AnyCancellable> = []

    private enum HotKeyID { static let open: UInt32 = 1, plainPaste: UInt32 = 2 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.applyAppearance()

        do {
            repo = try ClipRepository(path: ClipRepository.defaultURL().path)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Clippy couldn’t open its database"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        model = ClipListModel(repo: repo, settings: settings)
        statusBar = StatusBarController(model: model)
        monitor = ClipboardMonitor(repo: repo, settings: settings) { [weak self] in self?.model.reload() }
        paste = PasteService(repo: repo, settings: settings, monitor: monitor)
        settingsWindow = SettingsWindowController(settings: settings, model: model)

        statusBar.onOpen = { [weak self] app in self?.paste.targetApp = app }
        paste.onPermissionMissing = { [weak self] in self?.settingsWindow.show(tab: .permissions) }
        model.onPaste = { [weak self] id, plain in
            guard let self else { return }
            self.statusBar.close()
            Task {
                await self.paste.paste(clipID: id, plain: plain)
                self.model.reload()
            }
        }
        model.onOpenSettings = { [weak self] in
            self?.statusBar.close()
            self?.settingsWindow.show()
        }
        model.onQuit = { NSApp.terminate(nil) }

        NSLog("Clippy started (\(Bundle.main.bundlePath)); accessibility=\(AXIsProcessTrusted()) postEvent=\(CGPreflightPostEventAccess())")
        monitor.start()
        watchForAccessibilityGrant()
        reclassifyOnce()
        // Trashing the installed app removes Clippy completely (see Uninstaller).
        uninstaller.start()
        registerHotKeys()
        startRetention()
        observeSettings()

        // Register the login item once, and only for the installed app (not dev builds in build/).
        // Accessibility is requested on the first paste, when it's actually needed.
        if Bundle.main.bundlePath.hasPrefix("/Applications/"), settings.consumeFirstLaunch(), settings.launchAtLogin {
            LoginItemManager.set(true)
        }
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        registerOpenHotKey(settings.openShortcut)
        // ⌘⇧V: paste the current clipboard as plain text, in any app.
        HotKeyManager.shared.register(id: HotKeyID.plainPaste, keyCode: UInt32(kVK_ANSI_V),
                                      modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            guard let self else { return }
            // Inside the popover, ⌘⇧V plain-pastes the selected row instead (StatusBarController).
            if self.statusBar.isShown {
                if let id = self.model.selectedID { self.model.use(id, plain: true) }
                return
            }
            Task { await self.paste.pasteClipboardAsPlainText() }
        }
    }

    private func registerOpenHotKey(_ shortcut: OpenShortcut) {
        guard let modifiers = shortcut.carbonModifiers else {
            HotKeyManager.shared.unregister(id: HotKeyID.open)
            return
        }
        HotKeyManager.shared.register(id: HotKeyID.open, keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers) { [weak self] in
            self?.statusBar.toggle()
        }
    }

    /// Applies the current image/file/text rules to clips stored by older builds (runs once per rules version).
    private func reclassifyOnce() {
        let key = "classificationVersion", version = 4
        guard UserDefaults.standard.integer(forKey: key) < version else { return }
        let repo = repo!
        Task {
            let changed = await Task.detached(priority: .utility) {
                (try? repo.reanalyzeAll(PasteboardCodec.analyze)) ?? 0
            }.value
            UserDefaults.standard.set(version, forKey: key)
            if changed > 0 { model.reload() }
        }
    }

    // MARK: Accessibility

    private var accessibilityTimer: Timer?

    /// When Accessibility isn't fully available at launch, check every second. Once the user turns
    /// it on in System Settings, restart quietly if this process still can't post the ⌘V keystroke
    /// (macOS only refreshes that on restart). A grant then takes effect without any manual step.
    private func watchForAccessibilityGrant() {
        guard !(AXIsProcessTrusted() && CGPreflightPostEventAccess()) else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.accessibilityTimer?.invalidate()
                self.accessibilityTimer = nil
                if Permissions.needsRelaunchForEvents {
                    NSLog("Clippy: Accessibility granted; restarting so pasting takes effect")
                    Permissions.relaunch()
                }
            }
        }
    }

    // MARK: Retention & limits

    private func startRetention() {
        runRetention()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { self.runRetention() }
        }
    }

    private func runRetention() {
        let limits = settings.limits
        let repo = repo!
        Task {
            await Task.detached(priority: .utility) {
                _ = try? repo.purgeExpired(keepDays: limits.keepDays)
                try? repo.enforceLimits(limits)
            }.value
            model.reload()
        }
    }

    private func observeSettings() {
        settings.$appearance.dropFirst()
            .sink { [weak self] in self?.statusBar.applyAppearance($0) }
            .store(in: &cancellables)
        settings.$openShortcut.dropFirst().removeDuplicates()
            .sink { [weak self] in self?.registerOpenHotKey($0) }
            .store(in: &cancellables)
        // Re-apply limits and retention shortly after the user changes them.
        Publishers.Merge3(settings.$keepDays.dropFirst(), settings.$maxText.dropFirst(), settings.$maxImages.dropFirst())
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.runRetention() }
            .store(in: &cancellables)
    }
}
