import Foundation

public final class SnapshotCaptureService: Sendable {
    private let chromeProfileService: ChromeProfileService
    private let chromeSessionMetadataService: ChromeSessionMetadataService
    private let displayService: DisplayService
    private let windowDiscoveryService: WindowDiscoveryService
    private let spaceService: SpaceService

    public init(
        chromeProfileService: ChromeProfileService = ChromeProfileService(),
        chromeSessionMetadataService: ChromeSessionMetadataService = ChromeSessionMetadataService(),
        displayService: DisplayService = DisplayService(),
        windowDiscoveryService: WindowDiscoveryService = WindowDiscoveryService(),
        spaceService: SpaceService = SpaceService()
    ) {
        self.chromeProfileService = chromeProfileService
        self.chromeSessionMetadataService = chromeSessionMetadataService
        self.displayService = displayService
        self.windowDiscoveryService = windowDiscoveryService
        self.spaceService = spaceService
    }

    public func captureSnapshot(name: String, selectedApplications: [AppSelection]) throws -> Snapshot {
        let permissions = PermissionService.status(promptMissing: false)
        guard permissions.accessibilityAuthorized else {
            throw MacMirrorError.missingAccessibilityPermission
        }
        guard permissions.screenRecordingAuthorized else {
            throw MacMirrorError.missingScreenRecordingPermission
        }

        let displays = displayService.currentDisplays()
        let windows = windowDiscoveryService.discoverWindows()
        let runningApps = windowDiscoveryService.runningApplications()
        let currentSpaceIndex = (try? spaceService.currentLayout().monitors.first?.currentSpace?.index) ?? 1

        var targets: [WindowTarget] = []
        targets += try captureChromeTargets(
            displays: displays,
            discoveredWindows: windows,
            defaultSpaceIndex: currentSpaceIndex
        )
        targets += captureSelectedApplicationTargets(
            selectedApplications: selectedApplications,
            runningApps: runningApps,
            discoveredWindows: windows,
            defaultSpaceIndex: currentSpaceIndex
        )

        let orderedTargets = targets
            .sorted(by: targetSort)
            .enumerated()
            .map { offset, target in
                var updated = target
                updated.launchOrder = offset
                return updated
            }

        return Snapshot(
            name: name,
            machineIdentifier: MachineIdentityService.currentMachineIdentifier(),
            displaySignatures: displays,
            windowTargets: orderedTargets
        )
    }

    func captureChromeTargets(
        displays: [DisplaySignature],
        discoveredWindows: [DiscoveredWindow],
        defaultSpaceIndex: Int
    ) throws -> [WindowTarget] {
        let profiles = try chromeProfileService.discoverProfiles()
        let sessionMetadata = chromeSessionMetadataService.discoverWindowMetadata(
            profileDirectories: profiles.map(\.profileDirectory)
        )
        let chromeWindows = discoveredWindows.filter { $0.ownerName == "Google Chrome" }
        let metadataByProfile = Dictionary(uniqueKeysWithValues: sessionMetadata.map { ($0.profileDirectory, $0) })
        let windowsByNumber = Dictionary(uniqueKeysWithValues: chromeWindows.map { ($0.windowNumber, $0) })

        return profiles.compactMap { profile in
            guard let metadata = metadataByProfile[profile.profileDirectory] else {
                Logger.log("Skipping Chrome profile \(profile.profileDirectory) because no live session metadata was found.")
                return nil
            }
            guard let liveWindow = windowsByNumber[metadata.windowNumber] else {
                Logger.log("Skipping Chrome profile \(profile.profileDirectory) because window \(metadata.windowNumber) is not currently open.")
                return nil
            }

            let geometry = liveWindow.frame
            let display = resolveDisplay(
                for: liveWindow,
                metadata: metadata,
                displays: displays,
                fallbackGeometry: geometry
            )

            guard let display else { return nil }

            return WindowTarget(
                kind: .chromeProfile,
                applicationName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                executablePath: chromeProfileService.chromeApplicationURL.path,
                chromeProfileID: profile.profileDirectory,
                chromeProfileName: profile.name,
                windowTitle: metadata.windowTitle ?? liveWindow.windowTitle,
                launchOrder: 0,
                geometry: geometry,
                targetDisplayID: display.stableIdentifier,
                targetDisplayName: display.localizedName,
                targetSpaceIndex: liveWindow.spaceIndex ?? defaultSpaceIndex,
                targetSpaceUUID: normalizedSpaceUUID(liveWindow.spaceUUID) ?? metadata.workspaceUUID,
                isHidden: false,
                isMinimized: false
            )
        }
    }

    private func captureSelectedApplicationTargets(
        selectedApplications: [AppSelection],
        runningApps: [RunningApplicationInfo],
        discoveredWindows: [DiscoveredWindow],
        defaultSpaceIndex: Int
    ) -> [WindowTarget] {
        let selectedBundleIDs = Set(selectedApplications.map(\.bundleIdentifier))
        let filteredApps = runningApps.filter { app in
            guard let bundleIdentifier = app.bundleIdentifier else { return false }
            return selectedBundleIDs.contains(bundleIdentifier) && bundleIdentifier != "com.google.Chrome"
        }

        return filteredApps.flatMap { app in
            let appWindows = discoveredWindows
                .filter { $0.pid == app.pid }
                .sorted { lhs, rhs in lhs.windowNumber < rhs.windowNumber }

            return appWindows.map { window in
                WindowTarget(
                    kind: .applicationWindow,
                    applicationName: app.displayName,
                    bundleIdentifier: app.bundleIdentifier ?? app.displayName,
                    executablePath: app.executablePath,
                    chromeProfileID: nil,
                    chromeProfileName: nil,
                    windowTitle: window.windowTitle,
                    launchOrder: 0,
                    geometry: window.frame,
                    targetDisplayID: window.displayID ?? "main",
                    targetDisplayName: window.displayName ?? "Main",
                    targetSpaceIndex: window.spaceIndex ?? defaultSpaceIndex,
                    targetSpaceUUID: normalizedSpaceUUID(window.spaceUUID),
                    isHidden: app.isHidden,
                    isMinimized: false
                )
            }
        }
    }

    private func resolveDisplay(
        for liveWindow: DiscoveredWindow,
        metadata: ChromeSessionWindowMetadata,
        displays: [DisplaySignature],
        fallbackGeometry: WindowGeometry
    ) -> DisplaySignature? {
        if let displayID = liveWindow.displayID,
           let display = displays.first(where: { $0.stableIdentifier == displayID }) {
            return display
        }

        if let screenLayoutUUID = metadata.screenLayoutUUID,
           let display = displays.first(where: { $0.stableIdentifier == screenLayoutUUID }) {
            return display
        }

        if let frame = metadata.frame,
           let display = displayService.display(containing: frame, displays: displays) {
            return display
        }

        return displayService.display(containing: fallbackGeometry, displays: displays) ?? displays.first
    }

    private func targetSort(_ lhs: WindowTarget, _ rhs: WindowTarget) -> Bool {
        if lhs.targetDisplayID == rhs.targetDisplayID {
            if lhs.targetSpaceIndex == rhs.targetSpaceIndex {
                if lhs.geometry.y == rhs.geometry.y {
                    return lhs.geometry.x < rhs.geometry.x
                }
                return lhs.geometry.y < rhs.geometry.y
            }
            return lhs.targetSpaceIndex < rhs.targetSpaceIndex
        }
        return lhs.targetDisplayName.localizedCaseInsensitiveCompare(rhs.targetDisplayName) == .orderedAscending
    }

    private func normalizedSpaceUUID(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
