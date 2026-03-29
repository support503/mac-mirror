import ApplicationServices
import CoreGraphics
import Foundation

public struct PermissionStatus: Sendable {
    public let accessibilityAuthorized: Bool
    public let screenRecordingAuthorized: Bool
    public let automationAvailable: Bool
}

public enum PermissionService {
    public static func status(promptMissing: Bool) -> PermissionStatus {
        PermissionStatus(
            accessibilityAuthorized: accessibilityAuthorized(promptIfNeeded: promptMissing),
            screenRecordingAuthorized: screenRecordingAuthorized(promptIfNeeded: promptMissing),
            automationAvailable: automationAvailable()
        )
    }

    public static func accessibilityAuthorized(promptIfNeeded: Bool) -> Bool {
        if promptIfNeeded {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    public static func screenRecordingAuthorized(promptIfNeeded: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard promptIfNeeded else { return false }
        return CGRequestScreenCaptureAccess()
    }

    public static func automationAvailable() -> Bool {
        let script = "tell application \"System Events\" to get name of first process"
        do {
            let result = try Shell.run("/usr/bin/osascript", arguments: ["-e", script])
            return result.exitCode == 0
        } catch {
            return false
        }
    }
}
