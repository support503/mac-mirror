import Foundation

public struct LaunchAtLoginStatus: Sendable {
    public let enabled: Bool
    public let helperPath: String?
}

public final class LaunchAtLoginController: Sendable {
    private let runtimeInstaller: RuntimeInstaller

    public init(runtimeInstaller: RuntimeInstaller = RuntimeInstaller()) {
        self.runtimeInstaller = runtimeInstaller
    }

    public func status() -> LaunchAtLoginStatus {
        guard
            FileManager.default.fileExists(atPath: AppSupportPaths.launchAgentPlist.path),
            let plist = NSDictionary(contentsOf: AppSupportPaths.launchAgentPlist),
            let arguments = plist["ProgramArguments"] as? [String],
            let helperPath = arguments.first
        else {
            return LaunchAtLoginStatus(enabled: false, helperPath: nil)
        }

        return LaunchAtLoginStatus(enabled: true, helperPath: helperPath)
    }

    public func setEnabled(_ enabled: Bool, currentExecutable: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])) throws {
        if enabled {
            let runtime = try runtimeInstaller.installSiblingToolsIfAvailable(from: currentExecutable)
            guard let helperURL = runtime.loginHelperURL else {
                throw MacMirrorError.runtimeInstallFailed("mac-mirror-login was not found next to the current executable.")
            }
            try installLaunchAgent(helperURL: helperURL)
        } else {
            try uninstallLaunchAgent()
        }
    }

    private func installLaunchAgent(helperURL: URL) throws {
        try AppSupportPaths.ensureDirectoriesExist()
        let launchAgentDirectory = AppSupportPaths.launchAgentPlist.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": "com.macmirror.restore-login",
            "ProgramArguments": [helperURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "WorkingDirectory": AppSupportPaths.appSupportDirectory.path,
            "StandardOutPath": AppSupportPaths.runtimeLogFile.path,
            "StandardErrorPath": AppSupportPaths.runtimeLogFile.path,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: AppSupportPaths.launchAgentPlist, options: .atomic)

        _ = try? Shell.run("/bin/launchctl", arguments: ["bootout", "gui/\(getuid())", AppSupportPaths.launchAgentPlist.path])
        _ = try Shell.run("/bin/launchctl", arguments: ["bootstrap", "gui/\(getuid())", AppSupportPaths.launchAgentPlist.path])
    }

    private func uninstallLaunchAgent() throws {
        if FileManager.default.fileExists(atPath: AppSupportPaths.launchAgentPlist.path) {
            _ = try? Shell.run("/bin/launchctl", arguments: ["bootout", "gui/\(getuid())", AppSupportPaths.launchAgentPlist.path])
            try FileManager.default.removeItem(at: AppSupportPaths.launchAgentPlist)
        }
    }
}
