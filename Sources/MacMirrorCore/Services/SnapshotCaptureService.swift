import Foundation

public final class SnapshotCaptureService: Sendable {
    private let chromeProfileService: ChromeProfileService
    private let displayService: DisplayService
    private let windowDiscoveryService: WindowDiscoveryService
    private let spaceService: SpaceService

    public init(
        chromeProfileService: ChromeProfileService = ChromeProfileService(),
        displayService: DisplayService = DisplayService(),
        windowDiscoveryService: WindowDiscoveryService = WindowDiscoveryService(),
        spaceService: SpaceService = SpaceService()
    ) {
        self.chromeProfileService = chromeProfileService
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
        let currentSpaceIndex = (try? spaceService.currentLayout().monitors.first?.currentSpaceIndex) ?? 1

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

    private func captureChromeTargets(
        displays: [DisplaySignature],
        discoveredWindows: [DiscoveredWindow],
        defaultSpaceIndex: Int
    ) throws -> [WindowTarget] {
        let profiles = try chromeProfileService.discoverProfiles()
        let chromeWindows = discoveredWindows.filter { $0.ownerName == "Google Chrome" }
        let matches = matchChromeProfilesToWindows(profiles: profiles, windows: chromeWindows)

        return profiles.compactMap { profile in
            let liveWindow = matches[profile.id]
            let geometry = liveWindow?.frame ?? profile.windowPlacement
            guard let geometry else { return nil }
            let display = liveWindow.flatMap { liveWindow in
                displays.first(where: { $0.stableIdentifier == liveWindow.displayID })
            } ?? displayService.display(containing: geometry, displays: displays) ?? displays.first

            guard let display else { return nil }

            return WindowTarget(
                kind: .chromeProfile,
                applicationName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                executablePath: chromeProfileService.chromeApplicationURL.path,
                chromeProfileID: profile.profileDirectory,
                chromeProfileName: profile.name,
                windowTitle: liveWindow?.windowTitle,
                launchOrder: 0,
                geometry: geometry,
                targetDisplayID: display.stableIdentifier,
                targetDisplayName: display.localizedName,
                targetSpaceIndex: liveWindow?.spaceIndex ?? defaultSpaceIndex,
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
                    isHidden: app.isHidden,
                    isMinimized: false
                )
            }
        }
    }

    private func matchChromeProfilesToWindows(
        profiles: [ChromeProfile],
        windows: [DiscoveredWindow]
    ) -> [String: DiscoveredWindow] {
        var remainingWindows = windows
        var output: [String: DiscoveredWindow] = [:]

        for profile in profiles {
            guard let placement = profile.windowPlacement else { continue }
            let bestIndex = remainingWindows.enumerated().min { lhs, rhs in
                lhs.element.frame.distance(to: placement) < rhs.element.frame.distance(to: placement)
            }?.offset
            if let bestIndex {
                output[profile.profileDirectory] = remainingWindows.remove(at: bestIndex)
            }
        }

        return output
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
}

private extension WindowGeometry {
    func distance(to other: WindowGeometry) -> Double {
        abs(x - other.x) + abs(y - other.y) + abs(width - other.width) + abs(height - other.height)
    }
}
