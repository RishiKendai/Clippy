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
}
