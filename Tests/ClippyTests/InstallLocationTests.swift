import Testing
@testable import ClippyCore

@Suite struct InstallLocationTests {
    let app = "/Applications/Clippy.app"

    @Test func onlyInstalledCopiesCleanUp() {
        #expect(InstallLocation.isInstalled(app, home: "/Users/me"))
        #expect(InstallLocation.isInstalled("/Users/me/Applications/Clippy.app", home: "/Users/me"))
        #expect(!InstallLocation.isInstalled("/Users/me/code/clippy/build/release/Clippy.app", home: "/Users/me"))
        #expect(!InstallLocation.isInstalled("/Volumes/Clippy/Clippy.app", home: "/Users/me"))
    }

    @Test func movingToTrashIsAnUninstall() {
        #expect(InstallLocation.wasUninstalled(originalPath: app, currentPath: "/Users/me/.Trash/Clippy.app", originalStillExists: false))
        #expect(InstallLocation.wasUninstalled(originalPath: app, currentPath: "/Users/me/.Trash/Clippy 23.10.04.app", originalStillExists: false))
    }

    @Test func deletingOutrightIsAnUninstall() {
        #expect(InstallLocation.wasUninstalled(originalPath: app, currentPath: nil, originalStillExists: false))
        #expect(InstallLocation.wasUninstalled(originalPath: app, currentPath: app, originalStillExists: false))
    }

    @Test func replacingWithAnUpdateIsNot() {
        #expect(!InstallLocation.wasUninstalled(originalPath: app, currentPath: "/Users/me/.Trash/Clippy.app", originalStillExists: true))
    }

    @Test func movingElsewhereIsNot() {
        #expect(!InstallLocation.wasUninstalled(originalPath: app, currentPath: "/Users/me/Desktop/Clippy.app", originalStillExists: false))
    }

    @Test func dataLocationsCoverTheDatabaseAndPreferences() {
        let paths = InstallLocation.dataLocations(bundleID: "com.clippy.app", home: "/Users/me")
        #expect(paths.contains("/Users/me/Library/Application Support/Clippy"))
        #expect(paths.contains("/Users/me/Library/Preferences/com.clippy.app.plist"))
        #expect(paths.allSatisfy { $0.hasPrefix("/Users/me/Library/") })
    }

    @Test func cleanupAgentWatchesTheAppAndOnlyActsWhenItIsGone() throws {
        let script = InstallLocation.cleanupScript(appPath: app, bundleID: "com.clippy.app", home: "/Users/me")
        let lines = script.split(separator: "\n").map(String.init)
        // Waits, then exits early while the app (or an update of it) is still installed.
        #expect(lines.prefix(2) == ["sleep 3", "[ -e '/Applications/Clippy.app' ] && exit 0"])
        #expect(lines.contains("rm -rf '/Users/me/Library/Application Support/Clippy'"))
        #expect(lines.contains("tccutil reset All 'com.clippy.app' >/dev/null 2>&1"))
        #expect(lines.contains("rm -f '/Users/me/Library/LaunchAgents/com.clippy.app.cleanup.plist'"))

        let plist = InstallLocation.cleanupAgentPlist(appPath: app, bundleID: "com.clippy.app", home: "/Users/me")
        #expect(plist["Label"] as? String == "com.clippy.app.cleanup")
        #expect(plist["WatchPaths"] as? [String] == ["/Applications/Clippy.app"])
        #expect((plist["ProgramArguments"] as? [String])?.last == script)
    }

    @Test func shellQuotingSurvivesApostrophes() {
        #expect(InstallLocation.shellQuote("/Users/o'neil/x") == "'/Users/o'\\''neil/x'")
    }
}
