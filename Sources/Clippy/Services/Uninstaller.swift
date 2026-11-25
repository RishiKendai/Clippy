import AppKit
import ClippyCore

/// "Move Clippy to the Trash" = uninstall. Only installed copies take part (InstallLocation).
///
/// Finder won't trash a running app, so the user quits Clippy first and nothing of Clippy runs
/// when it's removed. The installed app therefore writes a small cleanup LaunchAgent (system tools
/// only) that watches the app bundle. When the bundle is gone for good, or replaced by a copy of
/// the same build (trash + reinstall), it removes all data, preferences and privacy entries.
/// A different build is an update and keeps everything. See InstallLocation.cleanupScript.
@MainActor
final class Uninstaller {
    private let appPath = Bundle.main.bundlePath
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.clippy.app"

    func start() {
        guard InstallLocation.isInstalled(appPath) else { return }
        installCleanupAgent()
    }

    /// Writes and loads the cleanup LaunchAgent, or refreshes it if the app moved or the rules changed.
    private func installCleanupAgent() {
        let plistPath = InstallLocation.cleanupAgentPath(bundleID: bundleID)
        let label = InstallLocation.cleanupAgentLabel(bundleID: bundleID)
        let attrs = try? FileManager.default.attributesOfItem(atPath: appPath)
        guard let fileID = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let copy = InstallLocation.InstalledCopy(path: appPath, fileID: fileID, build: build)
        let plist = InstallLocation.cleanupAgentPlist(copy, bundleID: bundleID)
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
}
