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
}
