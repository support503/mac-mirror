import Foundation

public enum AppSupportPaths {
    public static let bundleIdentifier = "com.macmirror.app"

    public static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MacMirror", isDirectory: true)
    }

    public static var snapshotsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Snapshots", isDirectory: true)
    }

    public static var exportsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    public static var binDirectory: URL {
        appSupportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    public static var settingsFile: URL {
        appSupportDirectory.appendingPathComponent("settings.json")
    }

    public static var runtimeLogFile: URL {
        appSupportDirectory.appendingPathComponent("runtime.log")
    }

    public static var launchAgentPlist: URL {
        let launchAgents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return launchAgents.appendingPathComponent("com.macmirror.restore-login.plist")
    }

    public static func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        for url in [appSupportDirectory, snapshotsDirectory, exportsDirectory, binDirectory] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
