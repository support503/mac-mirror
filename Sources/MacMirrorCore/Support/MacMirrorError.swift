import Foundation

public enum MacMirrorError: LocalizedError, Equatable, Sendable {
    case snapshotNotFound(String)
    case noPinnedSnapshot
    case noSupportedChromeInstallation
    case missingAccessibilityPermission
    case missingScreenRecordingPermission
    case unsupportedOperation(String)
    case invalidSnapshot(String)
    case runtimeInstallFailed(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .snapshotNotFound(let value):
            return "Snapshot not found: \(value)"
        case .noPinnedSnapshot:
            return "No pinned snapshot is configured."
        case .noSupportedChromeInstallation:
            return "Google Chrome could not be found in /Applications."
        case .missingAccessibilityPermission:
            return "Accessibility permission is required for window placement."
        case .missingScreenRecordingPermission:
            return "Screen Recording permission is required for complete window discovery."
        case .unsupportedOperation(let value):
            return value
        case .invalidSnapshot(let value):
            return "Invalid snapshot: \(value)"
        case .runtimeInstallFailed(let value):
            return "Runtime installation failed: \(value)"
        case .commandFailed(let value):
            return value
        }
    }
}
