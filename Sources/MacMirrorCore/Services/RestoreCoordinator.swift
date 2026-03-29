import AppKit
import Foundation

protocol RestoreChromeLaunching: Sendable {
    func isChromeRunning() -> Bool
    func restoreMode(for profileDirectory: String, chromeWasRunningAtStart: Bool) -> ChromeRestoreMode
    func launchProfile(profileDirectory: String, mode: ChromeRestoreMode) throws
}

protocol RestoreDisplayServicing: Sendable {
    func currentDisplays() -> [DisplaySignature]
    func mapDisplays(saved: [DisplaySignature], current: [DisplaySignature]) -> [String: DisplayMapping]
}

protocol RestoreWindowDiscovering: Sendable {
    func discoverWindows() -> [DiscoveredWindow]
    func waitForWindow(
        bundleIdentifier: String,
        excluding existingWindowNumbers: Set<Int>,
        targetGeometry: WindowGeometry?,
        timeout: TimeInterval
    ) -> DiscoveredWindow?
}

protocol RestoreAccessibilityWindowServicing: Sendable {
    func applyWindowTarget(
        _ target: WindowTarget,
        bundleIdentifier: String,
        referenceWindow: DiscoveredWindow?
    ) throws
    func clickChromeRestoreButtonIfPresent() -> Bool
    func pressChromeRestoreDefaultAction() -> Bool
}

protocol RestoreSpaceServicing: Sendable {
    func currentLayout() throws -> SpacesLayout
    func mapMonitorsToDisplays(
        layout: SpacesLayout,
        currentDisplays: [DisplaySignature],
        discoveredWindows: [DiscoveredWindow]
    ) -> [String: SpacesLayout.Monitor]
    func switchToSpace(
        savedSpaceUUID: String?,
        savedSpaceIndex: Int,
        onDisplayID displayID: String,
        currentDisplays: [DisplaySignature],
        discoveredWindowsProvider: () -> [DiscoveredWindow]
    ) throws -> SpacesLayout.Space
}

extension ChromeProfileService: RestoreChromeLaunching {}
extension DisplayService: RestoreDisplayServicing {}
extension WindowDiscoveryService: RestoreWindowDiscovering {}
extension AccessibilityWindowService: RestoreAccessibilityWindowServicing {}
extension SpaceService: RestoreSpaceServicing {}

private struct ChromeRestoreOutcome {
    let window: DiscoveredWindow
    let sessionRestored: Bool
    let restorePromptClicked: Bool
}

public final class RestoreCoordinator: Sendable {
    private let snapshotStore: SnapshotStore
    private let chromeProfileService: any RestoreChromeLaunching
    private let displayService: any RestoreDisplayServicing
    private let windowDiscoveryService: any RestoreWindowDiscovering
    private let accessibilityWindowService: any RestoreAccessibilityWindowServicing
    private let spaceService: any RestoreSpaceServicing
    private let permissionStatusProvider: @Sendable (Bool) -> PermissionStatus
    private let sleepHandler: @Sendable (TimeInterval) -> Void
    private let nowProvider: @Sendable () -> Date

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
        self.permissionStatusProvider = { PermissionService.status(promptMissing: $0) }
        self.sleepHandler = { Thread.sleep(forTimeInterval: $0) }
        self.nowProvider = Date.init
    }

    init(
        snapshotStore: SnapshotStore = SnapshotStore(),
        chromeProfileService: any RestoreChromeLaunching,
        displayService: any RestoreDisplayServicing,
        windowDiscoveryService: any RestoreWindowDiscovering,
        accessibilityWindowService: any RestoreAccessibilityWindowServicing,
        spaceService: any RestoreSpaceServicing,
        permissionStatusProvider: @escaping @Sendable (Bool) -> PermissionStatus,
        sleepHandler: @escaping @Sendable (TimeInterval) -> Void,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.snapshotStore = snapshotStore
        self.chromeProfileService = chromeProfileService
        self.displayService = displayService
        self.windowDiscoveryService = windowDiscoveryService
        self.accessibilityWindowService = accessibilityWindowService
        self.spaceService = spaceService
        self.permissionStatusProvider = permissionStatusProvider
        self.sleepHandler = sleepHandler
        self.nowProvider = nowProvider
    }

    public func restorePinnedSnapshot() throws -> RestoreReport {
        let snapshot = try snapshotStore.loadPinnedSnapshot()
        return try restore(snapshot: snapshot)
    }

    public func restoreSnapshot(named idOrName: String) throws -> RestoreReport {
        let snapshot = try snapshotStore.loadSnapshot(idOrName: idOrName)
        return try restore(snapshot: snapshot)
    }

    public func restore(snapshot: Snapshot) throws -> RestoreReport {
        let permissions = permissionStatusProvider(false)
        guard permissions.accessibilityAuthorized else {
            throw MacMirrorError.missingAccessibilityPermission
        }

        let currentDisplays = displayService.currentDisplays()
        let displayMappings = displayService.mapDisplays(saved: snapshot.displaySignatures, current: currentDisplays)
        var knownWindowNumbers = Set(windowDiscoveryService.discoverWindows().map(\.windowNumber))
        let chromeWasRunningAtStart = chromeProfileService.isChromeRunning()
        var results: [RestoreTargetResult] = []

        Logger.log(
            """
            Starting restore snapshot=\(snapshot.name) totalTargets=\(snapshot.targetCount) \
            chromeTargets=\(snapshot.chromeTargetCount) chromeWasRunningAtStart=\(chromeWasRunningAtStart)
            """
        )

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

            let result = restoreTarget(
                adjustedTarget,
                currentDisplays: currentDisplays,
                knownWindowNumbers: &knownWindowNumbers,
                chromeWasRunningAtStart: chromeWasRunningAtStart
            )
            results.append(result)
        }

        let report = RestoreReport(snapshotID: snapshot.id, snapshotName: snapshot.name, results: results)
        Logger.log("Restore report snapshot=\(snapshot.name) restored=\(report.restoredCount) failed=\(report.failedCount) total=\(report.totalTargets)")
        for failure in report.failedTargets {
            Logger.log("Restore target failure \(failure.targetDescription): \(failure.message ?? "Unknown error")")
        }
        return report
    }

    private func launchTarget(_ target: WindowTarget, chromeWasRunningAtStart: Bool) throws {
        switch target.kind {
        case .chromeProfile:
            guard let profileDirectory = target.chromeProfileID else {
                throw MacMirrorError.invalidSnapshot("Chrome target \(target.applicationName) is missing a profile directory.")
            }
            let restoreMode = chromeProfileService.restoreMode(
                for: profileDirectory,
                chromeWasRunningAtStart: chromeWasRunningAtStart
            )
            try launchChromeTarget(
                target,
                profileDirectory: profileDirectory,
                restoreMode: restoreMode,
                chromeWasRunningAtStart: chromeWasRunningAtStart
            )

        case .applicationWindow:
            try launchApplication(bundleIdentifier: target.bundleIdentifier, executablePath: target.executablePath)
        }
    }

    private func launchChromeTarget(
        _ target: WindowTarget,
        profileDirectory: String,
        restoreMode: ChromeRestoreMode,
        chromeWasRunningAtStart: Bool
    ) throws {
        let chromeRunningBeforeLaunch = chromeProfileService.isChromeRunning()
        Logger.log(
            """
            Chrome launch attempt profileDirectory=\(profileDirectory) \
            chromeRunningBeforeLaunch=\(chromeRunningBeforeLaunch) coldStartRestore=\(chromeWasRunningAtStart == false) \
            mode=\(restoreMode.rawValue)
            """
        )
        try chromeProfileService.launchProfile(profileDirectory: profileDirectory, mode: restoreMode)
        Logger.log("Chrome profile launched profileDirectory=\(profileDirectory) mode=\(restoreMode.rawValue)")
    }

    private func launchApplication(bundleIdentifier: String, executablePath: String?) throws {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try openApplicationAndWait(at: appURL, configuration: config, label: bundleIdentifier)
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
        knownWindowNumbers: inout Set<Int>,
        chromeWasRunningAtStart: Bool
    ) -> RestoreTargetResult {
        do {
            try performTargetRestore(
                target,
                currentDisplays: currentDisplays,
                knownWindowNumbers: &knownWindowNumbers,
                chromeWasRunningAtStart: chromeWasRunningAtStart
            )
            return makeResult(for: target, succeeded: true)
        } catch {
            Logger.log("Restore failed for \(targetDescription(for: target)): \(error.localizedDescription)")
            return makeResult(for: target, succeeded: false, message: error.localizedDescription)
        }
    }

    private func performTargetRestore(
        _ target: WindowTarget,
        currentDisplays: [DisplaySignature],
        knownWindowNumbers: inout Set<Int>,
        chromeWasRunningAtStart: Bool
    ) throws {
        switch target.kind {
        case .chromeProfile:
            try performChromeTargetRestore(
                target,
                currentDisplays: currentDisplays,
                knownWindowNumbers: &knownWindowNumbers,
                chromeWasRunningAtStart: chromeWasRunningAtStart
            )
        case .applicationWindow:
            try performApplicationTargetRestore(
                target,
                currentDisplays: currentDisplays,
                knownWindowNumbers: &knownWindowNumbers,
                chromeWasRunningAtStart: chromeWasRunningAtStart
            )
        }
    }

    private func performApplicationTargetRestore(
        _ target: WindowTarget,
        currentDisplays: [DisplaySignature],
        knownWindowNumbers: inout Set<Int>,
        chromeWasRunningAtStart: Bool
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

        try launchApplication(bundleIdentifier: target.bundleIdentifier, executablePath: target.executablePath)
        let launchDelay = launchSettlingDelay(
            for: target,
            chromeWasRunningAtStart: chromeWasRunningAtStart,
            chromeRestoreMode: nil
        )
        sleepHandler(launchDelay)

        let window = windowDiscoveryService.waitForWindow(
            bundleIdentifier: target.bundleIdentifier,
            excluding: knownWindowNumbers,
            targetGeometry: target.geometry,
            timeout: windowTimeout(
                for: target,
                chromeWasRunningAtStart: chromeWasRunningAtStart,
                chromeRestoreMode: nil
            )
        )
        guard let window else {
            let timeout = Int(
                windowTimeout(
                    for: target,
                    chromeWasRunningAtStart: chromeWasRunningAtStart,
                    chromeRestoreMode: nil
                )
            )
            let description = targetDescription(for: target)
            Logger.log("No new window detected for \(description) within \(timeout)s.")
            throw MacMirrorError.commandFailed("No new window appeared for \(description) within \(timeout) seconds.")
        }
        knownWindowNumbers.insert(window.windowNumber)

        try applyPlacementAndVerify(
            target,
            resolvedSpace: resolvedSpace,
            currentDisplays: currentDisplays,
            referenceWindow: window
        )
    }

    private func performChromeTargetRestore(
        _ target: WindowTarget,
        currentDisplays: [DisplaySignature],
        knownWindowNumbers: inout Set<Int>,
        chromeWasRunningAtStart: Bool
    ) throws {
        guard let profileDirectory = target.chromeProfileID else {
            throw MacMirrorError.invalidSnapshot("Chrome target \(target.applicationName) is missing a profile directory.")
        }

        let restoreMode = chromeProfileService.restoreMode(
            for: profileDirectory,
            chromeWasRunningAtStart: chromeWasRunningAtStart
        )
        Logger.log(
            "Resolved Chrome restore mode profileDirectory=\(profileDirectory) mode=\(restoreMode.rawValue)"
        )

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

        if restoreMode == .crashSessionRecovery,
           let existingWindow = existingRestoredChromeWindow(
            for: target,
            resolvedSpace: resolvedSpace,
            excluding: knownWindowNumbers
           ) {
            Logger.log(
                "Reusing existing Chrome restored window for \(targetDescription(for: target)) window=\(existingWindow.windowNumber)"
            )
            knownWindowNumbers.insert(existingWindow.windowNumber)
            try applyPlacementAndVerify(
                target,
                resolvedSpace: resolvedSpace,
                currentDisplays: currentDisplays,
                referenceWindow: existingWindow
            )
            return
        }

        try launchChromeTarget(
            target,
            profileDirectory: profileDirectory,
            restoreMode: restoreMode,
            chromeWasRunningAtStart: chromeWasRunningAtStart
        )

        let launchDelay = launchSettlingDelay(
            for: target,
            chromeWasRunningAtStart: chromeWasRunningAtStart,
            chromeRestoreMode: restoreMode
        )
        sleepHandler(0.25)
        sleepHandler(max(0, launchDelay - 0.25))

        if restoreMode == .crashSessionRecovery {
            let triggeredRestore = accessibilityWindowService.clickChromeRestoreButtonIfPresent() ||
                accessibilityWindowService.pressChromeRestoreDefaultAction()
            if triggeredRestore {
                Logger.log("Triggered Chrome crash restore input for \(targetDescription(for: target)).")
            }
        }

        let timeout = windowTimeout(
            for: target,
            chromeWasRunningAtStart: chromeWasRunningAtStart,
            chromeRestoreMode: restoreMode
        )
        let outcome = try waitForChromeRestoreOutcome(
            target,
            existingWindowNumbers: knownWindowNumbers,
            restoreMode: restoreMode,
            timeout: timeout
        )
        knownWindowNumbers.insert(outcome.window.windowNumber)

        if outcome.restorePromptClicked {
            Logger.log("Chrome restore prompt clicked for \(targetDescription(for: target)).")
        } else if restoreMode == .crashSessionRecovery {
            Logger.log("No Chrome restore prompt detected for \(targetDescription(for: target)).")
        }

        if outcome.sessionRestored {
            Logger.log(
                "Chrome session restored for \(targetDescription(for: target)) window=\(outcome.window.windowNumber)"
            )
        } else if restoreMode == .crashSessionRecovery {
            Logger.log(
                """
                Chrome session did not restore pages for \(targetDescription(for: target)); \
                using fallback window \(outcome.window.windowNumber)
                """
            )
        }

        try applyPlacementAndVerify(
            target,
            resolvedSpace: resolvedSpace,
            currentDisplays: currentDisplays,
            referenceWindow: outcome.window
        )

        if restoreMode == .crashSessionRecovery, outcome.sessionRestored == false {
            throw MacMirrorError.commandFailed(
                "Chrome session did not restore pages for \(targetDescription(for: target)), but layout was applied."
            )
        }
    }

    private func applyPlacementAndVerify(
        _ target: WindowTarget,
        resolvedSpace: SpacesLayout.Space,
        currentDisplays: [DisplaySignature],
        referenceWindow: DiscoveredWindow
    ) throws {
        try accessibilityWindowService.applyWindowTarget(
            target,
            bundleIdentifier: target.bundleIdentifier,
            referenceWindow: referenceWindow
        )
        Logger.log("Layout applied for \(targetDescription(for: target)) window=\(referenceWindow.windowNumber)")
        sleepHandler(0.25)

        if try verifyTargetSpace(target, resolvedSpace: resolvedSpace, referenceWindow: referenceWindow) {
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

        let retryWindow = verificationWindow(for: target, preferredWindowNumber: referenceWindow.windowNumber)
        try accessibilityWindowService.applyWindowTarget(
            target,
            bundleIdentifier: target.bundleIdentifier,
            referenceWindow: retryWindow ?? referenceWindow
        )
        Logger.log(
            "Layout reapplied for \(targetDescription(for: target)) window=\((retryWindow ?? referenceWindow).windowNumber)"
        )
        sleepHandler(0.25)

        guard try verifyTargetSpace(target, resolvedSpace: resolvedSpace, referenceWindow: retryWindow ?? referenceWindow) else {
            throw MacMirrorError.commandFailed(
                "Window restore verification failed for \(target.applicationName). Expected Desktop \(resolvedSpace.index) on \(target.targetDisplayName)."
            )
        }
    }

    private func waitForChromeRestoreOutcome(
        _ target: WindowTarget,
        existingWindowNumbers: Set<Int>,
        restoreMode: ChromeRestoreMode,
        timeout: TimeInterval
    ) throws -> ChromeRestoreOutcome {
        switch restoreMode {
        case .normalStartup:
            guard let window = windowDiscoveryService.waitForWindow(
                bundleIdentifier: target.bundleIdentifier,
                excluding: existingWindowNumbers,
                targetGeometry: target.geometry,
                timeout: timeout
            ) else {
                let description = targetDescription(for: target)
                Logger.log("No new window detected for \(description) within \(Int(timeout))s.")
                throw MacMirrorError.commandFailed(
                    "No new window appeared for \(description) within \(Int(timeout)) seconds."
                )
            }
            return ChromeRestoreOutcome(window: window, sessionRestored: true, restorePromptClicked: false)

        case .crashSessionRecovery:
            let deadline = nowProvider().addingTimeInterval(timeout)
            var fallbackWindow: DiscoveredWindow?
            var restorePromptClicked = false

            while nowProvider() < deadline {
                if accessibilityWindowService.clickChromeRestoreButtonIfPresent() {
                    restorePromptClicked = true
                }

                let candidates = chromeWindowCandidates(
                    for: target,
                    excluding: existingWindowNumbers
                )
                if let restoredWindow = bestChromeSessionWindow(in: candidates, target: target) {
                    return ChromeRestoreOutcome(
                        window: restoredWindow,
                        sessionRestored: true,
                        restorePromptClicked: restorePromptClicked
                    )
                }

                if let candidate = bestChromeFallbackWindow(in: candidates, target: target) {
                    fallbackWindow = chooseBetterChromeFallback(
                        current: fallbackWindow,
                        candidate: candidate,
                        target: target
                    )
                }

                sleepHandler(0.4)
            }

            if let fallbackWindow {
                return ChromeRestoreOutcome(
                    window: fallbackWindow,
                    sessionRestored: false,
                    restorePromptClicked: restorePromptClicked
                )
            }

            let description = targetDescription(for: target)
            Logger.log("No new window detected for \(description) within \(Int(timeout))s.")
            throw MacMirrorError.commandFailed(
                "No new window appeared for \(description) within \(Int(timeout)) seconds."
            )
        }
    }

    private func chromeWindowCandidates(
        for target: WindowTarget,
        excluding existingWindowNumbers: Set<Int>
    ) -> [DiscoveredWindow] {
        windowDiscoveryService.discoverWindows().filter { window in
            window.ownerName == target.applicationName &&
            existingWindowNumbers.contains(window.windowNumber) == false
        }
    }

    private func existingRestoredChromeWindow(
        for target: WindowTarget,
        resolvedSpace: SpacesLayout.Space,
        excluding existingWindowNumbers: Set<Int>
    ) -> DiscoveredWindow? {
        let candidates = chromeWindowCandidates(
            for: target,
            excluding: existingWindowNumbers
        ).filter { window in
            windowMatchesResolvedSpace(window, resolvedSpace: resolvedSpace)
        }

        if let restored = bestChromeSessionWindow(in: candidates, target: target) {
            return restored
        }
        return bestChromeFallbackWindow(in: candidates, target: target)
    }

    private func bestChromeSessionWindow(
        in windows: [DiscoveredWindow],
        target: WindowTarget
    ) -> DiscoveredWindow? {
        let candidates = windows.filter { isLikelyRestoredChromeSessionWindow($0, target: target) }
        return candidates.min { chromeSessionScore($0, target: target) < chromeSessionScore($1, target: target) }
    }

    private func bestChromeFallbackWindow(
        in windows: [DiscoveredWindow],
        target: WindowTarget
    ) -> DiscoveredWindow? {
        windows.min { chromeFallbackScore($0, target: target) < chromeFallbackScore($1, target: target) }
    }

    private func chooseBetterChromeFallback(
        current: DiscoveredWindow?,
        candidate: DiscoveredWindow,
        target: WindowTarget
    ) -> DiscoveredWindow {
        guard let current else {
            return candidate
        }

        if chromeFallbackScore(candidate, target: target) < chromeFallbackScore(current, target: target) {
            return candidate
        }
        return current
    }

    private func isLikelyRestoredChromeSessionWindow(
        _ window: DiscoveredWindow,
        target: WindowTarget
    ) -> Bool {
        let normalizedTitle = normalizeWindowTitle(window.windowTitle)
        if normalizedTitle.isEmpty || normalizedTitle == "about:blank" || isLikelyChromeNewTabTitle(normalizedTitle) {
            return false
        }
        if isLikelyTransientChromeWindow(window, target: target) {
            return false
        }
        return true
    }

    private func isLikelyTransientChromeWindow(
        _ window: DiscoveredWindow,
        target: WindowTarget
    ) -> Bool {
        let normalizedTitle = normalizeWindowTitle(window.windowTitle)
        if normalizedTitle.contains("who's using chrome") || normalizedTitle == "profiles" {
            return true
        }
        if normalizedTitle == "google chrome" && (window.frame.width < 900 || window.frame.height < 700) {
            return true
        }
        if normalizedTitle.isEmpty == false {
            return false
        }

        let widthThreshold = max(700, target.geometry.width * 0.75)
        let heightThreshold = max(700, target.geometry.height * 0.75)
        return window.frame.width < widthThreshold || window.frame.height < heightThreshold
    }

    private func chromeSessionScore(_ window: DiscoveredWindow, target: WindowTarget) -> Double {
        var score = chromeFallbackScore(window, target: target)
        let normalizedTitle = normalizeWindowTitle(window.windowTitle)
        let normalizedTargetTitle = normalizeWindowTitle(target.windowTitle)
        if normalizedTargetTitle.isEmpty == false {
            score += normalizedTitle.contains(normalizedTargetTitle) ? -750 : 250
        }
        return score
    }

    private func chromeFallbackScore(_ window: DiscoveredWindow, target: WindowTarget) -> Double {
        var score = windowDistance(window.frame, target.geometry)
        let normalizedTitle = normalizeWindowTitle(window.windowTitle)
        if normalizedTitle == "about:blank" {
            score += 250
        }
        if isLikelyChromeNewTabTitle(normalizedTitle) {
            score += 400
        }
        if isLikelyTransientChromeWindow(window, target: target) {
            score += 5_000
        }
        return score
    }

    private func isLikelyChromeNewTabTitle(_ normalizedTitle: String) -> Bool {
        normalizedTitle.contains("new tab")
    }

    private func normalizeWindowTitle(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func windowDistance(_ lhs: WindowGeometry, _ rhs: WindowGeometry) -> Double {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    private func windowMatchesResolvedSpace(_ window: DiscoveredWindow, resolvedSpace: SpacesLayout.Space) -> Bool {
        let observedUUID = normalizeSpaceUUID(window.spaceUUID)
        let expectedUUID = normalizeSpaceUUID(resolvedSpace.uuid)
        if let expectedUUID {
            return observedUUID == expectedUUID
        }
        return window.spaceIndex == resolvedSpace.index
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

    private func windowTimeout(for target: WindowTarget, chromeWasRunningAtStart: Bool) -> TimeInterval {
        windowTimeout(for: target, chromeWasRunningAtStart: chromeWasRunningAtStart, chromeRestoreMode: nil)
    }

    private func windowTimeout(
        for target: WindowTarget,
        chromeWasRunningAtStart: Bool,
        chromeRestoreMode: ChromeRestoreMode?
    ) -> TimeInterval {
        switch target.kind {
        case .chromeProfile:
            if chromeRestoreMode == .crashSessionRecovery {
                return chromeWasRunningAtStart ? 18 : 28
            }
            return chromeWasRunningAtStart ? 12 : 20
        case .applicationWindow:
            return 12
        }
    }

    private func launchSettlingDelay(for target: WindowTarget, chromeWasRunningAtStart: Bool) -> TimeInterval {
        launchSettlingDelay(for: target, chromeWasRunningAtStart: chromeWasRunningAtStart, chromeRestoreMode: nil)
    }

    private func launchSettlingDelay(
        for target: WindowTarget,
        chromeWasRunningAtStart: Bool,
        chromeRestoreMode: ChromeRestoreMode?
    ) -> TimeInterval {
        switch target.kind {
        case .chromeProfile:
            if chromeRestoreMode == .crashSessionRecovery {
                return chromeWasRunningAtStart ? 1.4 : 2.4
            }
            return chromeWasRunningAtStart ? 1.2 : 2.0
        case .applicationWindow:
            return 0.8
        }
    }

    private func makeResult(for target: WindowTarget, succeeded: Bool, message: String? = nil) -> RestoreTargetResult {
        RestoreTargetResult(
            targetID: target.id,
            kind: target.kind,
            applicationName: target.applicationName,
            chromeProfileID: target.chromeProfileID,
            chromeProfileName: target.chromeProfileName,
            succeeded: succeeded,
            message: message
        )
    }

    private func targetDescription(for target: WindowTarget) -> String {
        makeResult(for: target, succeeded: false).targetDescription
    }

    private func openApplicationAndWait(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        label: String
    ) throws {
        let state = RestoreLaunchRequestState()
        if Thread.isMainThread {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                state.error = error
                state.completed = true
            }

            let deadline = Date().addingTimeInterval(10)
            while state.completed == false && Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }

            if state.completed == false {
                throw MacMirrorError.commandFailed("Timed out waiting for \(label) to accept the launch request.")
            }
            if let launchError = state.error {
                Logger.log("Open application error for \(label): \(launchError.localizedDescription)")
                throw MacMirrorError.commandFailed("Failed to launch \(label): \(launchError.localizedDescription)")
            }
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            state.error = error
            state.completed = true
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw MacMirrorError.commandFailed("Timed out waiting for \(label) to accept the launch request.")
        }
        if let launchError = state.error {
            Logger.log("Open application error for \(label): \(launchError.localizedDescription)")
            throw MacMirrorError.commandFailed("Failed to launch \(label): \(launchError.localizedDescription)")
        }
    }
}

private final class RestoreLaunchRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?
    private var storedCompleted = false

    var error: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedError
        }
        set {
            lock.lock()
            storedError = newValue
            lock.unlock()
        }
    }

    var completed: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedCompleted
        }
        set {
            lock.lock()
            storedCompleted = newValue
            lock.unlock()
        }
    }
}
