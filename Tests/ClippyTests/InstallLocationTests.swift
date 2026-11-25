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

    @Test func dataLocationsCoverTheDatabaseAndPreferences() {
        let paths = InstallLocation.dataLocations(bundleID: "com.clippy.app", home: "/Users/me")
        #expect(paths.contains("/Users/me/Library/Application Support/Clippy"))
        #expect(paths.contains("/Users/me/Library/Preferences/com.clippy.app.plist"))
        #expect(paths.allSatisfy { $0.hasPrefix("/Users/me/Library/") })
    }

    @Test func cleanupAgentKnowsTheInstalledCopy() throws {
        let copy = InstallLocation.InstalledCopy(path: app, fileID: 4242, build: "7")
        let script = InstallLocation.cleanupScript(copy, bundleID: "com.clippy.app", home: "/Users/me")
        let lines = script.split(separator: "\n").map(String.init)
        // Same copy (file ID) → nothing to do; a different build → an update, keep the data.
        #expect(lines.contains("    [ \"$(stat -f %i '/Applications/Clippy.app')\" = '4242' ] && exit 0"))
        #expect(lines.contains("    [ \"$(plutil -extract CFBundleVersion raw -o - '/Applications/Clippy.app/Contents/Info.plist' 2>/dev/null)\" != '7' ] && exit 0"))
        // Stops copies running from the removed path; any other running Clippy means it's in use.
        #expect(lines.contains("    '/Applications/Clippy.app'/*) kill \"$pid\"; reopen=1 ;;"))
        #expect(lines.contains("    *) exit 0 ;;"))
        #expect(lines.contains("rm -rf '/Users/me/Library/Application Support/Clippy'"))
        #expect(lines.contains("tccutil reset All 'com.clippy.app' >/dev/null 2>&1"))
        #expect(lines.contains("rm -f '/Users/me/Library/LaunchAgents/com.clippy.app.cleanup.plist'"))

        let plist = InstallLocation.cleanupAgentPlist(copy, bundleID: "com.clippy.app", home: "/Users/me")
        #expect(plist["Label"] as? String == "com.clippy.app.cleanup")
        #expect(plist["WatchPaths"] as? [String] == ["/Applications/Clippy.app"])
        #expect((plist["ProgramArguments"] as? [String])?.last == script)
    }

    @Test func shellQuotingSurvivesApostrophes() {
        #expect(InstallLocation.shellQuote("/Users/o'neil/x") == "'/Users/o'\\''neil/x'")
    }
}
