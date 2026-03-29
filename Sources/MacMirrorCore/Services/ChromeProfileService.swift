import AppKit
import Foundation

enum ChromeRestoreMode: String, Sendable {
    case normalStartup
    case crashSessionRecovery
}

enum ChromeProfileExitType: String, Sendable {
    case crashed = "Crashed"
    case normal = "Normal"
    case sessionEnded = "SessionEnded"
}

public final class ChromeProfileService: Sendable {
    public let chromeSupportDirectory: URL
    public let chromeApplicationURL: URL

    public init(
        chromeSupportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true),
        chromeApplicationURL: URL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    ) {
        self.chromeSupportDirectory = chromeSupportDirectory
        self.chromeApplicationURL = chromeApplicationURL
    }

    public func discoverProfiles() throws -> [ChromeProfile] {
        let localStateURL = chromeSupportDirectory.appendingPathComponent("Local State")
        guard FileManager.default.fileExists(atPath: localStateURL.path) else {
            return []
        }

        let data = try Data(contentsOf: localStateURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let profile = object?["profile"] as? [String: Any]
        let infoCache = profile?["info_cache"] as? [String: Any] ?? [:]

        let profiles = infoCache.compactMap { key, value -> ChromeProfile? in
            guard let info = value as? [String: Any] else { return nil }
            return ChromeProfile(
                id: key,
                name: (info["name"] as? String) ?? key,
                email: info["user_name"] as? String,
                gaiaName: info["gaia_name"] as? String,
                profileDirectory: key,
                windowPlacement: try? loadWindowPlacement(profileDirectory: key),
                lastActiveTime: info["active_time"] as? Double
            )
        }

        return profiles.sorted { lhs, rhs in
            if lhs.lastActiveTime == rhs.lastActiveTime {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return (lhs.lastActiveTime ?? 0) > (rhs.lastActiveTime ?? 0)
        }
    }

    public func loadWindowPlacement(profileDirectory: String) throws -> WindowGeometry? {
        guard let object = try loadPreferences(profileDirectory: profileDirectory) else {
            return nil
        }
        let browser = object["browser"] as? [String: Any]
        let placement = browser?["window_placement"] as? [String: Any]

        guard
            let left = placement?["left"] as? Double ?? (placement?["left"] as? NSNumber)?.doubleValue,
            let top = placement?["top"] as? Double ?? (placement?["top"] as? NSNumber)?.doubleValue,
            let right = placement?["right"] as? Double ?? (placement?["right"] as? NSNumber)?.doubleValue,
            let bottom = placement?["bottom"] as? Double ?? (placement?["bottom"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return WindowGeometry(
            x: left,
            y: top,
            width: max(100, right - left),
            height: max(100, bottom - top),
            maximized: (placement?["maximized"] as? Bool) ?? false
        )
    }

    public func chromeExecutableURL() throws -> URL {
        let executable = chromeApplicationURL
            .appendingPathComponent("Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MacMirrorError.noSupportedChromeInstallation
        }
        return executable
    }

    public func isChromeRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
    }

    func restoreMode(for profileDirectory: String, chromeWasRunningAtStart: Bool) -> ChromeRestoreMode {
        guard chromeWasRunningAtStart == false else {
            return .normalStartup
        }

        guard loadExitType(profileDirectory: profileDirectory) == .crashed else {
            return .normalStartup
        }

        return .crashSessionRecovery
    }

    func loadExitType(profileDirectory: String) -> ChromeProfileExitType? {
        guard
            let object = try? loadPreferences(profileDirectory: profileDirectory),
            let profile = object["profile"] as? [String: Any],
            let rawValue = profile["exit_type"] as? String
        else {
            return nil
        }

        return ChromeProfileExitType(rawValue: rawValue)
    }

    public func launchProfile(profileDirectory: String) throws {
        try launchProfile(profileDirectory: profileDirectory, mode: .normalStartup)
    }

    func launchProfile(profileDirectory: String, mode: ChromeRestoreMode) throws {
        guard FileManager.default.fileExists(atPath: chromeApplicationURL.path) else {
            throw MacMirrorError.noSupportedChromeInstallation
        }

        let executableURL = try chromeExecutableURL()
        let process = Process()
        process.executableURL = executableURL
        switch mode {
        case .normalStartup:
            process.arguments = [
                "--profile-directory=\(profileDirectory)",
                "--new-window",
                "about:blank",
            ]

        case .crashSessionRecovery:
            process.arguments = [
                "--profile-directory=\(profileDirectory)",
            ]
        }
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if process.isRunning {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.terminationStatus != 0 {
            let stderr = (process.standardError as? Pipe)
                .flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = (process.standardOutput as? Pipe)
                .flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr?.isEmpty == false ? stderr! : (stdout?.isEmpty == false ? stdout! : "Unknown Chrome launch failure.")
            throw MacMirrorError.commandFailed("Google Chrome launch failed: \(message)")
        }
    }

    private func loadPreferences(profileDirectory: String) throws -> [String: Any]? {
        let preferencesURL = chromeSupportDirectory
            .appendingPathComponent(profileDirectory, isDirectory: true)
            .appendingPathComponent("Preferences")
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: preferencesURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
