import Foundation

/// Rules for "trash the app = uninstall it" (see CLAUDE.md). macOS has no uninstall hook, so the
/// running app watches its own bundle and applies these rules when the bundle moves.
public enum InstallLocation {
    /// Only an installed copy (in /Applications or ~/Applications) cleans up after itself.
    /// Dev builds in build/ never do, so `make clean` can't wipe anyone's history.
    public static func isInstalled(_ bundlePath: String, home: String = NSHomeDirectory()) -> Bool {
        bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home + "/Applications/")
    }

    public static func isInTrash(_ path: String) -> Bool {
        path.contains("/.Trash/") || path.contains("/.Trashes/")
    }

    /// Decides, after the bundle at `originalPath` was moved or deleted, whether the user
    /// uninstalled Clippy. `currentPath` is where the bundle is now (nil if it's gone).
    /// A new copy back at the original path means an update (Finder "Replace"), not an uninstall.
    public static func wasUninstalled(originalPath: String, currentPath: String?, originalStillExists: Bool) -> Bool {
        if originalStillExists { return false }
        guard let currentPath, currentPath != originalPath else { return true }
        return isInTrash(currentPath)
    }

    /// Everything Clippy writes to the user's Library, removed on uninstall.
    public static func dataLocations(bundleID: String, home: String = NSHomeDirectory()) -> [String] {
        let lib = home + "/Library"
        return [
            lib + "/Application Support/Clippy",
            lib + "/Preferences/\(bundleID).plist",
            lib + "/Caches/\(bundleID)",
            lib + "/HTTPStorages/\(bundleID)",
            lib + "/HTTPStorages/\(bundleID).binarycookies",
            lib + "/Saved Application State/\(bundleID).savedState",
            lib + "/WebKit/\(bundleID)",
        ]
    }

    // MARK: Cleanup agent
    //
    // Finder won't trash an app while it's running, so Clippy is never running when it's
    // uninstalled. A tiny LaunchAgent (system tools only, nothing inside the app bundle) watches
    // the app bundle and cleans up once it's gone. It watches the bundle itself: launchd never
    // fires for /Applications (a firmlink) when an item inside it is removed.

    public static func cleanupAgentLabel(bundleID: String) -> String { bundleID + ".cleanup" }

    public static func cleanupAgentPath(bundleID: String, home: String = NSHomeDirectory()) -> String {
        home + "/Library/LaunchAgents/\(cleanupAgentLabel(bundleID: bundleID)).plist"
    }

    /// Shell script run by the agent whenever the app bundle changes. If the app is still (or
    /// again, after an update) at `appPath` a few seconds later, it does nothing. Otherwise it
    /// deletes Clippy's data, preferences and privacy permissions, then removes itself.
    public static func cleanupScript(appPath: String, bundleID: String, home: String = NSHomeDirectory()) -> String {
        let label = cleanupAgentLabel(bundleID: bundleID)
        let removals = dataLocations(bundleID: bundleID, home: home).map { "rm -rf \(shellQuote($0))" }
        return ([
            "sleep 3",
            "[ -e \(shellQuote(appPath)) ] && exit 0",
            "pkill -x Clippy",
            "defaults delete \(shellQuote(bundleID)) >/dev/null 2>&1",
        ] + removals + [
            "tccutil reset All \(shellQuote(bundleID)) >/dev/null 2>&1",
            "rm -f \(shellQuote(cleanupAgentPath(bundleID: bundleID, home: home)))",
            "launchctl bootout gui/$(id -u)/\(label) >/dev/null 2>&1",
            "exit 0",
        ]).joined(separator: "\n")
    }

    /// The LaunchAgent property list (WatchPaths on the app bundle).
    public static func cleanupAgentPlist(appPath: String, bundleID: String, home: String = NSHomeDirectory()) -> [String: Any] {
        [
            "Label": cleanupAgentLabel(bundleID: bundleID),
            "ProgramArguments": ["/bin/sh", "-c", cleanupScript(appPath: appPath, bundleID: bundleID, home: home)],
            "WatchPaths": [appPath],
            // Shows the agent as Clippy's in System Settings → Login Items.
            "AssociatedBundleIdentifiers": [bundleID],
            "ProcessType": "Background",
        ]
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
