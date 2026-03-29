import Foundation
import Testing
@testable import MacMirrorCore

struct ChromeProfileServiceTests {
    @Test
    func readsProfileInfoAndWindowPlacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)

        let localState = """
        {
          "profile": {
            "info_cache": {
              "Profile 1": {
                "name": "Work",
                "user_name": "work@example.com",
                "gaia_name": "Work User",
                "active_time": 123.0
              }
            }
          }
        }
        """
        try localState.data(using: .utf8)?.write(to: root.appendingPathComponent("Local State"))

        let preferences = """
        {
          "browser": {
            "window_placement": {
              "left": 100,
              "top": 80,
              "right": 1600,
              "bottom": 980,
              "maximized": false
            }
          }
        }
        """
        try preferences.data(using: .utf8)?.write(to: root.appendingPathComponent("Profile 1/Preferences"))

        let service = ChromeProfileService(
            chromeSupportDirectory: root,
            chromeApplicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let profiles = try service.discoverProfiles()

        #expect(profiles.count == 1)
        #expect(profiles.first?.name == "Work")
        #expect(profiles.first?.windowPlacement?.x == 100)
        #expect(profiles.first?.windowPlacement?.width == 1500)
    }

    @Test
    func resolvesCrashRecoveryModeFromChromePreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)

        let preferences = """
        {
          "profile": {
            "exit_type": "Crashed"
          }
        }
        """
        try preferences.data(using: .utf8)?.write(to: root.appendingPathComponent("Profile 1/Preferences"))

        let service = ChromeProfileService(
            chromeSupportDirectory: root,
            chromeApplicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )

        #expect(service.loadExitType(profileDirectory: "Profile 1") == .crashed)
        #expect(service.restoreMode(for: "Profile 1", chromeWasRunningAtStart: false) == .crashSessionRecovery)
        #expect(service.restoreMode(for: "Profile 1", chromeWasRunningAtStart: true) == .normalStartup)
    }
}
