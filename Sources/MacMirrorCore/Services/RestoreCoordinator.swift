import AppKit
import Foundation

public final class RestoreCoordinator: Sendable {
    private let snapshotStore: SnapshotStore
    private let chromeProfileService: ChromeProfileService
    private let displayService: DisplayService
    private let windowDiscoveryService: WindowDiscoveryService
    private let accessibilityWindowService: AccessibilityWindowService
    private let spaceService: SpaceService

    public init(
        snapshotStore: SnapshotStore = SnapshotStore(),
        chromeProfileService: ChromeProfileService = ChromeProfileService(),
        displayService: DisplayService = DisplayService(),
        windowDiscoveryService: WindowDiscoveryService = WindowDiscoveryService(),
        accessibilityWindowService: AccessibilityWindowService = AccessibilityWindowService(),
        spaceService: SpaceService = SpaceService()
    ) {
        self.snapshotStore = snapshotStore
        self.chromeProfileService = chromeProfileService
        self.displayService = displayService
        self.windowDiscoveryService = windowDiscoveryService
        self.accessibilityWindowService = accessibilityWindowService
        self.spaceService = spaceService
    }

    public func restorePinnedSnapshot() throws {
        let snapshot = try snapshotStore.loadPinnedSnapshot()
        try restore(snapshot: snapshot)
    }

    public func restoreSnapshot(named idOrName: String) throws {
        let snapshot = try snapshotStore.loadSnapshot(idOrName: idOrName)
        try restore(snapshot: snapshot)
    }

    public func restore(snapshot: Snapshot) throws {
        let permissions = PermissionService.status(promptMissing: false)
        guard permissions.accessibilityAuthorized else {
            throw MacMirrorError.missingAccessibilityPermission
        }

        let currentDisplays = displayService.currentDisplays()
        let displayMappings = displayService.mapDisplays(saved: snapshot.displaySignatures, current: currentDisplays)
        var knownWindowNumbers = Set(windowDiscoveryService.discoverWindows().map(\.windowNumber))

        if snapshot.usesLegacySpaceFallback {
            Logger.log("Snapshot \(snapshot.name) is using legacy desktop indexes only. Re-save it for exact desktop restore.")
        }

        for target in snapshot.windowTargets.sorted(by: { $0.launchOrder < $1.launchOrder }) {
            var adjustedTarget = target
            if let mappedDisplay = displayMappings[target.targetDisplayID]?.current {
                adjustedTarget.targetDisplayID = mappedDisplay.stableIdentifier
                adjustedTarget.targetDisplayName = mappedDisplay.localizedName
            }
            adjustedTarget.geometry = remapGeometry(
                target.geometry,
                for: target.targetDisplayID,
                using: displayMappings
            )

            let layout = try? spaceService.currentLayout()
            let monitorMappings = layout.map {
                spaceService.mapMonitorsToDisplays(
                    layout: $0,
                    currentDisplays: currentDisplays,
                    discoveredWindows: windowDiscoveryService.discoverWindows()
                )
            }
            let availableSpaces = monitorMappings?[adjustedTarget.targetDisplayID]?.spaces.map {
                "\($0.index):\($0.uuid ?? "Desktop 1")"
            }.joined(separator: ", ") ?? "unavailable"

            Logger.log(
                """
                Restoring target kind=\(adjustedTarget.kind.rawValue) app=\(adjustedTarget.applicationName) \
                display=\(adjustedTarget.targetDisplayID) savedSpaceIndex=\(adjustedTarget.targetSpaceIndex) \
                savedSpaceUUID=\(adjustedTarget.targetSpaceUUID ?? "nil") availableSpaces=[\(availableSpaces)]
                """
            )

            do {
                try restoreTarget(
                    adjustedTarget,
                    currentDisplays: currentDisplays,
                    knownWindowNumbers: &knownWindowNumbers
                )
            } catch {
                Logger.log("Restore failed for \(adjustedTarget.applicationName): \(error.localizedDescription)")
                throw error
            }
        }
    }

    private func launchTarget(_ target: WindowTarget) throws {
        switch target.kind {
        case .chromeProfile:
            guard let profileDirectory = target.chromeProfileID else {
                throw MacMirrorError.invalidSnapshot("Chrome target \(target.applicationName) is missing a profile directory.")
            }
            try chromeProfileService.launchProfile(profileDirectory: profileDirectory)

        case .applicationWindow:
            try launchApplication(bundleIdentifier: target.bundleIdentifier, executablePath: target.executablePath)
        }
    }

    private func launchApplication(bundleIdentifier: String, executablePath: String?) throws {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error {
                    Logger.log("Open application error for \(bundleIdentifier): \(error.localizedDescription)")
                }
            }
            return
        }

        if let executablePath {
            let result = try Shell.run("/usr/bin/open", arguments: ["-a", executablePath])
            guard result.exitCode == 0 else {
                throw MacMirrorError.commandFailed(result.stderr)
            }
        }
    }

    private func remapGeometry(
        _ geometry: WindowGeometry,
        for savedDisplayID: String,
        using mappings: [String: DisplayMapping]
    ) -> WindowGeometry {
        guard let mapping = mappings[savedDisplayID] else {
            return geometry
        }

        let savedRect = mapping.saved.rect
        let currentRect = mapping.current.rect
        let offsetX = geometry.x - savedRect.origin.x
        let offsetY = geometry.y - savedRect.origin.y

        return WindowGeometry(
            x: currentRect.origin.x + offsetX,
            y: currentRect.origin.y + offsetY,
            width: min(geometry.width, currentRect.width),
            height: min(geometry.height, currentRect.height),
            maximized: geometry.maximized
        )
    }

    private func restoreTarget(
        _ target: WindowTarget,
        currentDisplays: [DisplaySignature],
        knownWindowNumbers: inout Set<Int>
    ) throws {
        let resolvedSpace = try spaceService.switchToSpace(
            savedSpaceUUID: target.targetSpaceUUID,
            savedSpaceIndex: target.targetSpaceIndex,
            onDisplayID: target.targetDisplayID,
            currentDisplays: currentDisplays
        ) { [windowDiscoveryService] in
            windowDiscoveryService.discoverWindows()
        }
        Logger.log(
            "Resolved restore desktop for \(target.applicationName) -> index=\(resolvedSpace.index) uuid=\(resolvedSpace.uuid ?? "nil")"
        )

        try launchTarget(target)
        Thread.sleep(forTimeInterval: target.kind == .chromeProfile ? 1.3 : 0.8)
        accessibilityWindowService.clickChromeRestoreButtonIfPresent()

        let window = windowDiscoveryService.waitForWindow(
            bundleIdentifier: target.bundleIdentifier,
            excluding: knownWindowNumbers,
            targetGeometry: target.geometry
        )
        if let window {
            knownWindowNumbers.insert(window.windowNumber)
        }

        try accessibilityWindowService.applyWindowTarget(
            target,
            bundleIdentifier: target.bundleIdentifier,
            referenceWindow: window
        )
        Thread.sleep(forTimeInterval: 0.25)

        if try verifyTargetSpace(target, resolvedSpace: resolvedSpace, referenceWindow: window) {
            return
        }

        Logger.log("Desktop verification failed for \(target.applicationName). Retrying switch and placement once.")
        _ = try spaceService.switchToSpace(
            savedSpaceUUID: target.targetSpaceUUID,
            savedSpaceIndex: target.targetSpaceIndex,
            onDisplayID: target.targetDisplayID,
            currentDisplays: currentDisplays
        ) { [windowDiscoveryService] in
            windowDiscoveryService.discoverWindows()
        }

        let retryWindow = verificationWindow(for: target, preferredWindowNumber: window?.windowNumber)
        try accessibilityWindowService.applyWindowTarget(
            target,
            bundleIdentifier: target.bundleIdentifier,
            referenceWindow: retryWindow ?? window
        )
        Thread.sleep(forTimeInterval: 0.25)

        guard try verifyTargetSpace(target, resolvedSpace: resolvedSpace, referenceWindow: retryWindow ?? window) else {
            throw MacMirrorError.commandFailed(
                "Window restore verification failed for \(target.applicationName). Expected Desktop \(resolvedSpace.index) on \(target.targetDisplayName)."
            )
        }
    }

    private func verifyTargetSpace(
        _ target: WindowTarget,
        resolvedSpace: SpacesLayout.Space,
        referenceWindow: DiscoveredWindow?
    ) throws -> Bool {
        let verifiedWindow = verificationWindow(for: target, preferredWindowNumber: referenceWindow?.windowNumber)
        guard let verifiedWindow else {
            throw MacMirrorError.commandFailed("Unable to verify the restored window for \(target.applicationName).")
        }

        let observedUUID = normalizeSpaceUUID(verifiedWindow.spaceUUID)
        let expectedUUID = normalizeSpaceUUID(resolvedSpace.uuid ?? target.targetSpaceUUID)
        let matchesExpectedSpace: Bool
        if let expectedUUID {
            matchesExpectedSpace = observedUUID == expectedUUID
        } else {
            matchesExpectedSpace = verifiedWindow.spaceIndex == resolvedSpace.index
        }

        Logger.log(
            """
            Verified target app=\(target.applicationName) window=\(verifiedWindow.windowNumber) \
            observedSpaceIndex=\(verifiedWindow.spaceIndex ?? 0) observedSpaceUUID=\(observedUUID ?? "nil") \
            expectedSpaceIndex=\(resolvedSpace.index) expectedSpaceUUID=\(expectedUUID ?? "nil")
            """
        )

        return matchesExpectedSpace
    }

    private func verificationWindow(
        for target: WindowTarget,
        preferredWindowNumber: Int?
    ) -> DiscoveredWindow? {
        if let preferredWindowNumber,
           let exact = windowDiscoveryService.discoverWindows().first(where: { $0.windowNumber == preferredWindowNumber }) {
            return exact
        }

        return windowDiscoveryService.waitForWindow(
            bundleIdentifier: target.bundleIdentifier,
            excluding: [],
            targetGeometry: target.geometry,
            timeout: 2
        )
    }

    private func normalizeSpaceUUID(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
