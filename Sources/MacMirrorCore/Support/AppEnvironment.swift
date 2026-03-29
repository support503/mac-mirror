import Foundation

public struct AppEnvironment: Sendable {
    public let snapshotStore: SnapshotStore
    public let chromeProfileService: ChromeProfileService
    public let chromeSessionMetadataService: ChromeSessionMetadataService
    public let displayService: DisplayService
    public let spaceService: SpaceService
    public let windowDiscoveryService: WindowDiscoveryService
    public let accessibilityWindowService: AccessibilityWindowService
    public let snapshotCaptureService: SnapshotCaptureService
    public let restoreCoordinator: RestoreCoordinator
    public let runtimeInstaller: RuntimeInstaller
    public let launchAtLoginController: LaunchAtLoginController

    public init() {
        let snapshotStore = SnapshotStore()
        let chromeProfileService = ChromeProfileService()
        let chromeSessionMetadataService = ChromeSessionMetadataService(
            chromeSupportDirectory: chromeProfileService.chromeSupportDirectory
        )
        let displayService = DisplayService()
        let spaceService = SpaceService()
        let windowDiscoveryService = WindowDiscoveryService(displayService: displayService, spaceService: spaceService)
        let accessibilityWindowService = AccessibilityWindowService()
        let snapshotCaptureService = SnapshotCaptureService(
            chromeProfileService: chromeProfileService,
            chromeSessionMetadataService: chromeSessionMetadataService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            spaceService: spaceService
        )
        let runtimeInstaller = RuntimeInstaller()
        let launchAtLoginController = LaunchAtLoginController(runtimeInstaller: runtimeInstaller)
        let restoreCoordinator = RestoreCoordinator(
            snapshotStore: snapshotStore,
            chromeProfileService: chromeProfileService,
            displayService: displayService,
            windowDiscoveryService: windowDiscoveryService,
            accessibilityWindowService: accessibilityWindowService,
            spaceService: spaceService
        )

        self.snapshotStore = snapshotStore
        self.chromeProfileService = chromeProfileService
        self.chromeSessionMetadataService = chromeSessionMetadataService
        self.displayService = displayService
        self.spaceService = spaceService
        self.windowDiscoveryService = windowDiscoveryService
        self.accessibilityWindowService = accessibilityWindowService
        self.snapshotCaptureService = snapshotCaptureService
        self.restoreCoordinator = restoreCoordinator
        self.runtimeInstaller = runtimeInstaller
        self.launchAtLoginController = launchAtLoginController
    }
}
