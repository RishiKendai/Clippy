import AppKit
import ClippyCore

/// "Move Clippy to the Trash" = uninstall: watches the app's own bundle and, when it lands in the
/// Trash (or is deleted), removes all of Clippy's data, its login item and permission entries,
/// then quits so the menu bar icon disappears. Only installed copies do this (InstallLocation).
@MainActor
final class Uninstaller {
    private let originalPath = Bundle.main.bundlePath
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.clippy.app"
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var checking = false

    /// Stops Clippy's own work (timers, hotkeys, status item) before the data is removed.
    var onUninstall: () -> Void = {}

    func start() {
        guard InstallLocation.isInstalled(originalPath) else { return }
        fd = open(originalPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.bundleMoved() }
        }
        source.resume()
        self.source = source
    }

    private func bundleMoved() {
        guard !checking else { return }
        checking = true
        Task {
            // Give Finder a moment: replacing the app with a newer copy puts a bundle back here.
            try? await Task.sleep(for: .seconds(2))
            let uninstalled = InstallLocation.wasUninstalled(
                originalPath: originalPath,
                currentPath: currentBundlePath(),
                originalStillExists: FileManager.default.fileExists(atPath: originalPath)
            )
            checking = false
            guard uninstalled else {
                NSLog("Clippy: bundle moved to \(currentBundlePath() ?? "?"); not an uninstall")
                return
            }
            uninstall()
        }
    }

    /// Where the bundle is now, following moves (the descriptor tracks the directory itself).
    private func currentBundlePath() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fd >= 0, fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func uninstall() {
        NSLog("Clippy: moved to the Trash; removing all data and quitting")
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd) }
        fd = -1

        onUninstall()
        LoginItemManager.set(false)
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        for path in InstallLocation.dataLocations(bundleID: bundleID) {
            try? FileManager.default.removeItem(atPath: path)
        }
        // Accessibility and other privacy entries for this app.
        let tcc = Process()
        tcc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tcc.arguments = ["reset", "All", bundleID]
        try? tcc.run()
        tcc.waitUntilExit()

        // exit, not terminate: nothing may write preferences or the database again.
        exit(0)
    }
}
