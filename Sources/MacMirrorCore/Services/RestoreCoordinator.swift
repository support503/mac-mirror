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

        for target in snapshot.windowTargets.sorted(by: { $0.launchOrder < $1.launchOrder }) {
            try? spaceService.switchToSpace(target.targetSpaceIndex)
            try launchTarget(target)
            Thread.sleep(forTimeInterval: target.kind == .chromeProfile ? 1.3 : 0.8)
            accessibilityWindowService.clickChromeRestoreButtonIfPresent()

            let remappedGeometry = remapGeometry(target.geometry, for: target.targetDisplayID, using: displayMappings)
            var adjustedTarget = target
            adjustedTarget.geometry = remappedGeometry

            let window = windowDiscoveryService.waitForWindow(
                bundleIdentifier: adjustedTarget.bundleIdentifier,
                excluding: knownWindowNumbers,
                targetGeometry: adjustedTarget.geometry
            )

            if let window {
                knownWindowNumbers.insert(window.windowNumber)
            }

            try accessibilityWindowService.applyWindowTarget(
                adjustedTarget,
                bundleIdentifier: adjustedTarget.bundleIdentifier,
                referenceWindow: window
            )
            Thread.sleep(forTimeInterval: 0.25)
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
}
