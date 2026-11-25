import AppKit
import ClippyCore

/// "Move Clippy to the Trash" = uninstall. Only installed copies do this (InstallLocation).
///
/// - Usual case: Finder refuses to trash a running app, so the user quits Clippy first. The
///   cleanup LaunchAgent this class installs (system tools only) notices the app is gone and
///   removes all data, preferences and privacy entries, then itself.
/// - If the bundle is removed while Clippy runs (e.g. from Terminal), Clippy watches its own bundle
///   and does the same cleanup itself, then quits so the menu bar icon disappears.
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
        installCleanupAgent()
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

    /// Writes and loads the cleanup LaunchAgent, or refreshes it if the app moved or the rules changed.
    private func installCleanupAgent() {
        let plistPath = InstallLocation.cleanupAgentPath(bundleID: bundleID)
        let label = InstallLocation.cleanupAgentLabel(bundleID: bundleID)
        let plist = InstallLocation.cleanupAgentPlist(appPath: originalPath, bundleID: bundleID)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        Task.detached(priority: .utility) {
            let domain = "gui/\(getuid())"
            let unchanged = FileManager.default.contents(atPath: plistPath) == data
            let loaded = Self.launchctl(["print", "\(domain)/\(label)"]) == 0
            if unchanged && loaded { return }
            if loaded { _ = Self.launchctl(["bootout", "\(domain)/\(label)"]) }
            do {
                try FileManager.default.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent,
                                                        withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
            } catch {
                NSLog("Clippy: couldn't write the cleanup agent: \(error)")
                return
            }
            let status = Self.launchctl(["bootstrap", domain, plistPath])
            NSLog("Clippy: cleanup agent \(status == 0 ? "loaded" : "failed to load (\(status))")")
        }
    }

    private func removeCleanupAgent() {
        let label = InstallLocation.cleanupAgentLabel(bundleID: bundleID)
        try? FileManager.default.removeItem(atPath: InstallLocation.cleanupAgentPath(bundleID: bundleID))
        _ = Self.launchctl(["bootout", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    nonisolated private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
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
        removeCleanupAgent()

        // exit, not terminate: nothing may write preferences or the database again.
        exit(0)
    }
}
