import Foundation
import MacMirrorCore

enum CLIError: Error {
    case invalidUsage(String)
}

@main
struct MacMirrorCLI {
    static func main() {
        let environment = AppEnvironment()

        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.isEmpty == false else {
                printHelp()
                return
            }

            switch arguments[0] {
            case "snapshot":
                try handleSnapshot(arguments: Array(arguments.dropFirst()), environment: environment)
            case "launch-agent":
                try handleLaunchAgent(arguments: Array(arguments.dropFirst()), environment: environment)
            case "permissions":
                printPermissions()
            case "apps":
                try handleApps(arguments: Array(arguments.dropFirst()), environment: environment)
            default:
                throw CLIError.invalidUsage("Unknown command: \(arguments[0])")
            }
        } catch {
            fputs("mac-mirror: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func handleSnapshot(arguments: [String], environment: AppEnvironment) throws {
        guard let command = arguments.first else {
            throw CLIError.invalidUsage("Expected a snapshot subcommand.")
        }

        switch command {
        case "save":
            guard arguments.count >= 2 else {
                throw CLIError.invalidUsage("Usage: mac-mirror snapshot save <name>")
            }
            var settings = try environment.snapshotStore.loadSettings()
            let name = arguments.dropFirst().joined(separator: " ")
            let snapshot = try environment.snapshotCaptureService.captureSnapshot(
                name: name,
                selectedApplications: settings.selectedApplications
            )
            try environment.snapshotStore.saveSnapshot(snapshot)
            settings.lastSavedSnapshotID = snapshot.id
            if settings.pinnedSnapshotID == nil {
                settings.pinnedSnapshotID = snapshot.id
            }
            try environment.snapshotStore.saveSettings(settings)
            print("Saved snapshot '\(snapshot.name)' (\(snapshot.id.uuidString)) with \(snapshot.detailedTargetSummary).")

        case "list":
            let settings = try environment.snapshotStore.loadSettings()
            let snapshots = try environment.snapshotStore.listSnapshots()
            if snapshots.isEmpty {
                print("No snapshots saved.")
                return
            }

            for snapshot in snapshots {
                let pinned = settings.pinnedSnapshotID == snapshot.id ? "*" : " "
                print("\(pinned) \(snapshot.name)\t\(snapshot.id.uuidString)\t\(snapshot.updatedAt.ISO8601Format())\t\(snapshot.detailedTargetSummary)")
            }

        case "restore":
            if arguments.count == 1 {
                let report = try environment.restoreCoordinator.restorePinnedSnapshot()
                printRestoreReport(report)
            } else {
                let name = arguments.dropFirst().joined(separator: " ")
                let report = try environment.restoreCoordinator.restoreSnapshot(named: name)
                printRestoreReport(report)
            }

        case "pin":
            guard arguments.count >= 2 else {
                throw CLIError.invalidUsage("Usage: mac-mirror snapshot pin <name-or-id>")
            }
            let value = arguments.dropFirst().joined(separator: " ")
            try environment.snapshotStore.pinSnapshot(idOrName: value)
            print("Pinned '\(value)'.")

        case "delete":
            guard arguments.count >= 2 else {
                throw CLIError.invalidUsage("Usage: mac-mirror snapshot delete <name-or-id>")
            }
            let value = arguments.dropFirst().joined(separator: " ")
            let snapshot = try environment.snapshotStore.loadSnapshot(idOrName: value)
            try environment.snapshotStore.deleteSnapshot(idOrName: value)

            var settings = try environment.snapshotStore.loadSettings()
            if settings.pinnedSnapshotID == snapshot.id {
                settings.pinnedSnapshotID = nil
            }
            if settings.lastSavedSnapshotID == snapshot.id {
                settings.lastSavedSnapshotID = nil
            }
            try environment.snapshotStore.saveSettings(settings)
            print("Deleted '\(snapshot.name)'.")

        case "export":
            guard arguments.count >= 2 else {
                throw CLIError.invalidUsage("Usage: mac-mirror snapshot export <path> [name-or-id]")
            }
            let destination = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let source = arguments.count >= 3 ? arguments.dropFirst(2).joined(separator: " ") : "pinned"
            if source == "pinned" {
                let snapshot = try environment.snapshotStore.loadPinnedSnapshot()
                try environment.snapshotStore.exportSnapshot(idOrName: snapshot.id.uuidString, to: destination)
                print("Exported pinned snapshot to \(destination.path).")
            } else {
                try environment.snapshotStore.exportSnapshot(idOrName: source, to: destination)
                print("Exported '\(source)' to \(destination.path).")
            }

        case "import":
            guard arguments.count == 2 else {
                throw CLIError.invalidUsage("Usage: mac-mirror snapshot import <path>")
            }
            let url = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let snapshot = try environment.snapshotStore.importSnapshot(from: url)
            print("Imported snapshot '\(snapshot.name)' (\(snapshot.id.uuidString)) with \(snapshot.detailedTargetSummary).")

        default:
            throw CLIError.invalidUsage("Unknown snapshot subcommand: \(command)")
        }
    }

    private static func handleLaunchAgent(arguments: [String], environment: AppEnvironment) throws {
        guard let command = arguments.first else {
            throw CLIError.invalidUsage("Usage: mac-mirror launch-agent <enable|disable|status>")
        }

        switch command {
        case "enable":
            try environment.launchAtLoginController.setEnabled(true)
            print("LaunchAgent installed.")
        case "disable":
            try environment.launchAtLoginController.setEnabled(false)
            print("LaunchAgent removed.")
        case "status":
            let status = environment.launchAtLoginController.status()
            print(status.enabled ? "enabled\t\(status.helperPath ?? "-")" : "disabled")
        default:
            throw CLIError.invalidUsage("Unknown launch-agent subcommand: \(command)")
        }
    }

    private static func handleApps(arguments: [String], environment: AppEnvironment) throws {
        guard arguments == ["list"] else {
            throw CLIError.invalidUsage("Usage: mac-mirror apps list")
        }

        let settings = try environment.snapshotStore.loadSettings()
        let selected = Set(settings.selectedApplications.map(\.bundleIdentifier))
        for app in environment.windowDiscoveryService.runningApplications() {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            let marker = selected.contains(bundleIdentifier) ? "*" : " "
            print("\(marker) \(app.displayName)\t\(bundleIdentifier)")
        }
    }

    private static func printPermissions() {
        let status = PermissionService.status(promptMissing: false)
        print("accessibility\t\(status.accessibilityAuthorized)")
        print("screen_recording\t\(status.screenRecordingAuthorized)")
        print("automation\t\(status.automationAvailable)")
    }

    private static func printRestoreReport(_ report: RestoreReport) {
        print(report.summaryLine)
        for failure in report.failedTargets {
            print("Failed: \(failure.targetDescription) - \(failure.message ?? "Unknown error")")
        }
    }

    private static func printHelp() {
        print(
            """
            mac-mirror

            Commands:
              mac-mirror snapshot save <name>
              mac-mirror snapshot list
              mac-mirror snapshot restore [name-or-id]
              mac-mirror snapshot pin <name-or-id>
              mac-mirror snapshot delete <name-or-id>
              mac-mirror snapshot export <path> [name-or-id]
              mac-mirror snapshot import <path>
              mac-mirror launch-agent <enable|disable|status>
              mac-mirror permissions
              mac-mirror apps list
            """
        )
    }
}
