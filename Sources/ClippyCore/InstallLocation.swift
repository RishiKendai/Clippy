import Foundation

/// Rules for "trash the app = uninstall it" (see CLAUDE.md). macOS has no uninstall hook and Finder
/// won't trash a running app, so a LaunchAgent written by the installed app does the cleanup.
public enum InstallLocation {
    /// Only an installed copy (in /Applications or ~/Applications) cleans up after itself.
    /// Dev builds in build/ never do, so `make clean` can't wipe anyone's history.
    public static func isInstalled(_ bundlePath: String, home: String = NSHomeDirectory()) -> Bool {
        bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home + "/Applications/")
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

    /// How long the app may be missing before it counts as uninstalled (Finder can take a few
    /// seconds to put a replacement in place).
    public static let uninstallGraceSeconds = 60

    /// The installed copy the agent was written for. Finder keeps a bundle's file ID when it moves
    /// it, and every fresh copy (DMG install, update, reinstall) gets a new one.
    public struct InstalledCopy: Equatable, Sendable {
        public var path: String
        public var fileID: UInt64
        /// CFBundleVersion (BUILD_NUMBER). Updates ship a different build; reinstalling the same
        /// DMG brings back the same build.
        public var build: String

        public init(path: String, fileID: UInt64, build: String) {
            self.path = path
            self.fileID = fileID
            self.build = build
        }
    }

    /// Shell script the agent runs whenever the app bundle changes:
    /// - same copy still there (same file ID) → nothing happened, exit;
    /// - a new copy with a **different** build → an update, keep everything;
    /// - a new copy with the **same** build → trashed and reinstalled: wipe, and restart the new
    ///   copy fresh if it was already running;
    /// - no copy for `uninstallGraceSeconds` → uninstalled: wipe (unless another copy of Clippy,
    ///   e.g. a dev build, is running).
    /// Wiping deletes Clippy's data, preferences and privacy permissions, then the agent itself.
    public static func cleanupScript(_ copy: InstalledCopy, bundleID: String, home: String = NSHomeDirectory()) -> String {
        let label = cleanupAgentLabel(bundleID: bundleID)
        let app = shellQuote(copy.path)
        let info = shellQuote(copy.path + "/Contents/Info.plist")
        let removals = dataLocations(bundleID: bundleID, home: home).map { "rm -rf \(shellQuote($0))" }
        return ([
            "reinstalled=0; reopen=0; i=0",
            "while [ $i -lt \(uninstallGraceSeconds) ]; do",
            "  if [ -f \(info) ]; then",
            "    [ \"$(stat -f %i \(app))\" = \(shellQuote(String(copy.fileID))) ] && exit 0",
            "    sleep 2",
            "    [ \"$(plutil -extract CFBundleVersion raw -o - \(info) 2>/dev/null)\" != \(shellQuote(copy.build)) ] && exit 0",
            "    reinstalled=1; break",
            "  fi",
            "  sleep 1; i=$((i+1))",
            "done",
            // "MacOS" via a variable so this script's own command line doesn't match the pattern.
            "M=MacOS",
            "for pid in $(pgrep -f \"/Contents/$M/Clippy\"); do",
            "  case \"$(ps -o command= -p \"$pid\")\" in",
            "    \(app)/*) kill \"$pid\"; reopen=1 ;;",
            "    *) exit 0 ;;",
            "  esac",
            "done",
            "sleep 1",
            "defaults delete \(shellQuote(bundleID)) >/dev/null 2>&1",
        ] + removals + [
            "tccutil reset All \(shellQuote(bundleID)) >/dev/null 2>&1",
            "rm -f \(shellQuote(cleanupAgentPath(bundleID: bundleID, home: home)))",
            // The fresh copy writes a new agent when it starts, replacing this one.
            "[ $reinstalled = 1 ] && [ $reopen = 1 ] && { open \(app); exit 0; }",
            "launchctl bootout gui/$(id -u)/\(label) >/dev/null 2>&1",
            "exit 0",
        ]).joined(separator: "\n")
    }

    /// The LaunchAgent property list (WatchPaths on the app bundle).
    public static func cleanupAgentPlist(_ copy: InstalledCopy, bundleID: String, home: String = NSHomeDirectory()) -> [String: Any] {
        [
            "Label": cleanupAgentLabel(bundleID: bundleID),
            "ProgramArguments": ["/bin/sh", "-c", cleanupScript(copy, bundleID: bundleID, home: home)],
            "WatchPaths": [copy.path],
            // Shows the agent as Clippy's in System Settings → Login Items.
            "AssociatedBundleIdentifiers": [bundleID],
            "ProcessType": "Background",
        ]
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
