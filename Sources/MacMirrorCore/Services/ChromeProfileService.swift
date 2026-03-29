import Foundation

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
        let preferencesURL = chromeSupportDirectory
            .appendingPathComponent(profileDirectory, isDirectory: true)
            .appendingPathComponent("Preferences")
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: preferencesURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let browser = object?["browser"] as? [String: Any]
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

    public func launchProfile(profileDirectory: String) throws {
        let process = Process()
        process.executableURL = try chromeExecutableURL()
        process.arguments = [
            "--profile-directory=\(profileDirectory)",
            "--new-window",
            "about:blank",
        ]
        try process.run()
    }
}
