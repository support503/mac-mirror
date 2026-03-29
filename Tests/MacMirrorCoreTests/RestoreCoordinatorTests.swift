import Foundation
import Testing
@testable import MacMirrorCore

struct RestoreCoordinatorTests {
    @Test
    func restoreContinuesAfterChromeWindowTimeout() throws {
        let display = makeDisplay()
        let space = makeSpace()
        let chromeService = StubChromeProfileService(running: false)
        let displayService = StubDisplayService(displays: [display])
        let windowDiscoveryService = StubWindowDiscoveryService(
            discoverSequence: [
                [],
                [],
                [],
                [makeWindow(windowNumber: 502, spaceIndex: 1)],
            ],
            waitResults: [
                nil,
                makeWindow(windowNumber: 502, title: "Personal", spaceIndex: 1),
            ]
        )
        let accessibilityService = StubAccessibilityWindowService()
        let spaceService = StubSpaceService(layout: makeLayout(displayIdentifier: display.stableIdentifier, space: space))
        let coordinator = makeCoordinator(
            chromeService: chromeService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            accessibilityService: accessibilityService,
            spaceService: spaceService
        )

        let report = try coordinator.restore(snapshot: makeSnapshot())

        #expect(chromeService.launchedProfiles == ["Profile 1", "Profile 2"])
        #expect(report.totalTargets == 2)
        #expect(report.restoredCount == 1)
        #expect(report.failedCount == 1)
        #expect(report.failedTargets.first?.targetDescription.contains("Work") == true)
        #expect(report.failedTargets.first?.message?.contains("No new window appeared") == true)
        #expect(windowDiscoveryService.waitTimeouts == [20, 20])
        #expect(report.summaryLine == "Restored 1 of 2 targets. 1 failed.")
    }

    @Test
    func restoreContinuesAfterDesktopVerificationFailure() throws {
        let display = makeDisplay()
        let space = makeSpace()
        let chromeService = StubChromeProfileService(running: true)
        let displayService = StubDisplayService(displays: [display])
        let windowDiscoveryService = StubWindowDiscoveryService(
            discoverSequence: [
                [],
                [],
                [makeWindow(windowNumber: 501, title: "Work", spaceIndex: 2, spaceUUID: "WRONG-SPACE")],
                [makeWindow(windowNumber: 501, title: "Work", spaceIndex: 2, spaceUUID: "WRONG-SPACE")],
                [makeWindow(windowNumber: 501, title: "Work", spaceIndex: 2, spaceUUID: "WRONG-SPACE")],
                [],
                [makeWindow(windowNumber: 502, title: "Personal", spaceIndex: 1)],
            ],
            waitResults: [
                makeWindow(windowNumber: 501, title: "Work", spaceIndex: 1),
                makeWindow(windowNumber: 502, title: "Personal", spaceIndex: 1),
            ]
        )
        let accessibilityService = StubAccessibilityWindowService()
        let spaceService = StubSpaceService(layout: makeLayout(displayIdentifier: display.stableIdentifier, space: space))
        let coordinator = makeCoordinator(
            chromeService: chromeService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            accessibilityService: accessibilityService,
            spaceService: spaceService
        )

        let report = try coordinator.restore(snapshot: makeSnapshot())

        #expect(chromeService.launchedProfiles == ["Profile 1", "Profile 2"])
        #expect(report.restoredCount == 1)
        #expect(report.failedCount == 1)
        #expect(report.failedTargets.first?.message?.contains("Window restore verification failed") == true)
        #expect(accessibilityService.applyCallCount == 3)
        #expect(windowDiscoveryService.waitTimeouts == [12, 12])
    }

    @Test
    func crashRestorePrefersRestoredSessionWindowOverTransientChromeWindow() throws {
        let display = makeDisplay()
        let space = makeSpace()
        let chromeService = StubChromeProfileService(
            running: false,
            restoreModes: ["Profile 1": .crashSessionRecovery]
        )
        let displayService = StubDisplayService(displays: [display])
        let transientWindow = makeWindow(
            windowNumber: 610,
            title: "Google Chrome",
            geometry: WindowGeometry(x: 60, y: 60, width: 620, height: 540),
            spaceIndex: 1
        )
        let restoredWindow = makeWindow(
            windowNumber: 611,
            title: "Work Dashboard",
            geometry: WindowGeometry(x: 10, y: 10, width: 1200, height: 900),
            spaceIndex: 1
        )
        let windowDiscoveryService = StubWindowDiscoveryService(
            discoverSequence: [
                [],
                [],
                [],
                [transientWindow],
                [restoredWindow],
                [restoredWindow],
            ],
            waitResults: []
        )
        let accessibilityService = StubAccessibilityWindowService(
            restorePromptClicks: [true, false]
        )
        let spaceService = StubSpaceService(layout: makeLayout(displayIdentifier: display.stableIdentifier, space: space))
        let clock = ManualClock()
        let coordinator = makeCoordinator(
            chromeService: chromeService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            accessibilityService: accessibilityService,
            spaceService: spaceService,
            clock: clock
        )

        let report = try coordinator.restore(snapshot: makeSnapshot(targets: [
            makeChromeTarget(profileDirectory: "Profile 1", profileName: "Work", launchOrder: 0),
        ]))

        #expect(report.restoredCount == 1)
        #expect(report.failedCount == 0)
        #expect(chromeService.launchedProfiles == ["Profile 1"])
        #expect(chromeService.launchedModes == [.crashSessionRecovery])
        #expect(accessibilityService.restorePromptClickCallCount == 3)
        #expect(accessibilityService.applyCallCount == 1)
        #expect(windowDiscoveryService.waitTimeouts.isEmpty)
    }

    @Test
    func crashRestoreReportsSessionFailureAndContinuesToNextProfile() throws {
        let display = makeDisplay()
        let space = makeSpace()
        let chromeService = StubChromeProfileService(
            running: false,
            restoreModes: [
                "Profile 1": .crashSessionRecovery,
                "Profile 2": .normalStartup,
            ]
        )
        let displayService = StubDisplayService(displays: [display])
        let fallbackWindow = makeWindow(
            windowNumber: 620,
            title: "Dark New Tab",
            geometry: WindowGeometry(x: 10, y: 10, width: 1200, height: 900),
            spaceIndex: 1
        )
        let successWindow = makeWindow(
            windowNumber: 621,
            title: "Personal Portal",
            geometry: WindowGeometry(x: 10, y: 10, width: 1200, height: 900),
            spaceIndex: 1
        )
        let windowDiscoveryService = StubWindowDiscoveryService(
            discoverSequence: [
                [],
                [],
                [],
                [fallbackWindow],
            ],
            waitResults: [
                successWindow,
                successWindow,
            ]
        )
        let accessibilityService = StubAccessibilityWindowService()
        let spaceService = StubSpaceService(layout: makeLayout(displayIdentifier: display.stableIdentifier, space: space))
        let clock = ManualClock()
        let coordinator = makeCoordinator(
            chromeService: chromeService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            accessibilityService: accessibilityService,
            spaceService: spaceService,
            clock: clock
        )

        let report = try coordinator.restore(snapshot: makeSnapshot())

        #expect(chromeService.launchedProfiles == ["Profile 1", "Profile 2"])
        #expect(chromeService.launchedModes == [.crashSessionRecovery, .normalStartup])
        #expect(report.restoredCount == 1)
        #expect(report.failedCount == 1)
        #expect(report.failedTargets.first?.targetDescription.contains("Work") == true)
        #expect(report.failedTargets.first?.message?.contains("Chrome session did not restore pages") == true)
        #expect(accessibilityService.applyCallCount == 2)
        #expect(windowDiscoveryService.waitTimeouts == [20, 2])
    }

    private func makeCoordinator(
        chromeService: StubChromeProfileService,
        displayService: StubDisplayService,
        windowDiscoveryService: StubWindowDiscoveryService,
        accessibilityService: StubAccessibilityWindowService,
        spaceService: StubSpaceService,
        clock: ManualClock = ManualClock()
    ) -> RestoreCoordinator {
        RestoreCoordinator(
            chromeProfileService: chromeService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            accessibilityWindowService: accessibilityService,
            spaceService: spaceService,
            permissionStatusProvider: { _ in
                PermissionStatus(
                    accessibilityAuthorized: true,
                    screenRecordingAuthorized: true,
                    automationAvailable: true
                )
            },
            sleepHandler: { clock.advance(by: $0) },
            nowProvider: { clock.now }
        )
    }

    private func makeSnapshot(
        targets: [WindowTarget]? = nil
    ) -> Snapshot {
        Snapshot(
            name: "Desk Setup",
            machineIdentifier: "machine-1",
            displaySignatures: [makeDisplay()],
            windowTargets: targets ?? [
                makeChromeTarget(
                    profileDirectory: "Profile 1",
                    profileName: "Work",
                    launchOrder: 0
                ),
                makeChromeTarget(
                    profileDirectory: "Profile 2",
                    profileName: "Personal",
                    launchOrder: 1
                ),
            ]
        )
    }

    private func makeChromeTarget(
        profileDirectory: String,
        profileName: String,
        launchOrder: Int
    ) -> WindowTarget {
        WindowTarget(
            kind: .chromeProfile,
            applicationName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            executablePath: "/Applications/Google Chrome.app",
            chromeProfileID: profileDirectory,
            chromeProfileName: profileName,
            windowTitle: profileName,
            launchOrder: launchOrder,
            geometry: WindowGeometry(x: 10, y: 10, width: 1200, height: 900),
            targetDisplayID: makeDisplay().stableIdentifier,
            targetDisplayName: makeDisplay().localizedName,
            targetSpaceIndex: 1,
            targetSpaceUUID: nil,
            isHidden: false,
            isMinimized: false
        )
    }

    private func makeDisplay() -> DisplaySignature {
        DisplaySignature(
            stableIdentifier: "display-1",
            displayID: 1,
            localizedName: "Main Display",
            originX: 0,
            originY: 0,
            width: 1512,
            height: 982,
            isPrimary: true
        )
    }

    private func makeSpace() -> SpacesLayout.Space {
        SpacesLayout.Space(index: 1, uuid: nil, id64: 1)
    }

    private func makeLayout(displayIdentifier: String, space: SpacesLayout.Space) -> SpacesLayout {
        SpacesLayout(
            monitors: [
                SpacesLayout.Monitor(
                    displayIdentifier: displayIdentifier,
                    currentSpace: space,
                    spaces: [space]
                )
            ],
            windowAssignments: [:],
            usesSeparateSpaces: false
        )
    }

    private func makeWindow(
        windowNumber: Int,
        title: String = "Chrome",
        geometry: WindowGeometry = WindowGeometry(x: 10, y: 10, width: 1200, height: 900),
        spaceIndex: Int?,
        spaceUUID: String? = nil
    ) -> DiscoveredWindow {
        DiscoveredWindow(
            pid: 1,
            windowNumber: windowNumber,
            ownerName: "Google Chrome",
            windowTitle: title,
            frame: geometry,
            layer: 0,
            isOnscreen: true,
            displayID: "display-1",
            displayName: "Main Display",
            spaceIndex: spaceIndex,
            spaceUUID: spaceUUID
        )
    }
}

private final class StubChromeProfileService: RestoreChromeLaunching, @unchecked Sendable {
    private(set) var launchedProfiles: [String] = []
    private(set) var launchedModes: [ChromeRestoreMode] = []
    private var running: Bool
    private let restoreModes: [String: ChromeRestoreMode]

    init(running: Bool, restoreModes: [String: ChromeRestoreMode] = [:]) {
        self.running = running
        self.restoreModes = restoreModes
    }

    func isChromeRunning() -> Bool {
        running
    }

    func restoreMode(for profileDirectory: String, chromeWasRunningAtStart: Bool) -> ChromeRestoreMode {
        restoreModes[profileDirectory] ?? .normalStartup
    }

    func launchProfile(profileDirectory: String, mode: ChromeRestoreMode) throws {
        launchedProfiles.append(profileDirectory)
        launchedModes.append(mode)
        running = true
    }
}

private final class StubDisplayService: RestoreDisplayServicing, @unchecked Sendable {
    private let displays: [DisplaySignature]

    init(displays: [DisplaySignature]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplaySignature] {
        displays
    }

    func mapDisplays(saved: [DisplaySignature], current: [DisplaySignature]) -> [String: DisplayMapping] {
        Dictionary(uniqueKeysWithValues: saved.map { savedDisplay in
            let currentDisplay = current.first(where: { $0.stableIdentifier == savedDisplay.stableIdentifier }) ?? current.first ?? savedDisplay
            return (savedDisplay.stableIdentifier, DisplayMapping(saved: savedDisplay, current: currentDisplay, usedFallback: false))
        })
    }
}

private final class StubWindowDiscoveryService: RestoreWindowDiscovering, @unchecked Sendable {
    private var discoverSequence: [[DiscoveredWindow]]
    private var waitResults: [DiscoveredWindow?]
    private(set) var waitTimeouts: [TimeInterval] = []
    private var fallbackWindows: [DiscoveredWindow] = []

    init(discoverSequence: [[DiscoveredWindow]], waitResults: [DiscoveredWindow?]) {
        self.discoverSequence = discoverSequence
        self.waitResults = waitResults
    }

    func discoverWindows() -> [DiscoveredWindow] {
        if discoverSequence.isEmpty {
            return fallbackWindows
        }
        let next = discoverSequence.removeFirst()
        fallbackWindows = next
        return next
    }

    func waitForWindow(
        bundleIdentifier: String,
        excluding existingWindowNumbers: Set<Int>,
        targetGeometry: WindowGeometry?,
        timeout: TimeInterval
    ) -> DiscoveredWindow? {
        waitTimeouts.append(timeout)
        if waitResults.isEmpty {
            return nil
        }
        return waitResults.removeFirst()
    }
}

private final class StubAccessibilityWindowService: RestoreAccessibilityWindowServicing, @unchecked Sendable {
    private(set) var applyCallCount = 0
    private(set) var restorePromptClickCallCount = 0
    private(set) var restoreDefaultActionCallCount = 0
    private var restorePromptClicks: [Bool]
    private var restoreDefaultActions: [Bool]

    init(restorePromptClicks: [Bool] = [], restoreDefaultActions: [Bool] = []) {
        self.restorePromptClicks = restorePromptClicks
        self.restoreDefaultActions = restoreDefaultActions
    }

    func applyWindowTarget(
        _ target: WindowTarget,
        bundleIdentifier: String,
        referenceWindow: DiscoveredWindow?
    ) throws {
        applyCallCount += 1
    }

    func clickChromeRestoreButtonIfPresent() -> Bool {
        restorePromptClickCallCount += 1
        if restorePromptClicks.isEmpty {
            return false
        }
        return restorePromptClicks.removeFirst()
    }

    func pressChromeRestoreDefaultAction() -> Bool {
        restoreDefaultActionCallCount += 1
        if restoreDefaultActions.isEmpty {
            return false
        }
        return restoreDefaultActions.removeFirst()
    }
}

private final class StubSpaceService: RestoreSpaceServicing, @unchecked Sendable {
    private let layout: SpacesLayout

    init(layout: SpacesLayout) {
        self.layout = layout
    }

    func currentLayout() throws -> SpacesLayout {
        layout
    }

    func mapMonitorsToDisplays(
        layout: SpacesLayout,
        currentDisplays: [DisplaySignature],
        discoveredWindows: [DiscoveredWindow]
    ) -> [String: SpacesLayout.Monitor] {
        guard let monitor = layout.monitors.first else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: currentDisplays.map { ($0.stableIdentifier, monitor) })
    }

    func switchToSpace(
        savedSpaceUUID: String?,
        savedSpaceIndex: Int,
        onDisplayID displayID: String,
        currentDisplays: [DisplaySignature],
        discoveredWindowsProvider: () -> [DiscoveredWindow]
    ) throws -> SpacesLayout.Space {
        layout.monitors.first?.spaces.first ?? SpacesLayout.Space(index: savedSpaceIndex, uuid: savedSpaceUUID, id64: nil)
    }
}

private final class ManualClock: @unchecked Sendable {
    private(set) var now: Date

    init(now: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }
}
